-- ApplicantScout — encodes M+ applicant snapshots as a QR code rendered into a
-- visible QR frame and triggers Screenshot() so the companion (external Python
-- tool) can decode the resulting JPG via pyzbar and show WCL N/H/M/M+
-- percentiles for each applicant. The QR defaults to TOPLEFT but can be moved
-- with /apscout qrmove.
--
-- WHY raw frame, not Ace3: Ace3 shares CallbackHandler-1.0 with other addons
-- (BetterBags, AlterEgo, ...); their taint contaminates our handler stack and
-- can block protected-mode APIs. Raw frame + NewTicker drains the dirty flag
-- from a clean C-side scheduler, immune to peer-addon taint propagation.
--
-- WHY screenshot transport, not chatlog/SendChatMessage: see CLAUDE.md
-- "WoW chatlog file is fundamentally unsuitable for real-time addon→external
-- transport in Midnight 12.0" trap row. Screenshot() is unprotected in 12.0
-- and produces a JPG within ~0.5s synchronously, with no taint propagation,
-- no chat anti-spam, no file buffer.
--
-- WHY QR over custom pixel marker: Reed-Solomon ECC built in (15% recovery at
-- level M); industry-standard finder/alignment patterns survive any DPI scale,
-- rotation, partial occlusion. Custom marker had zero error correction and
-- broke on dark-terrain backgrounds + non-integer DPI scales.

local addonName = ...
local ADDON_VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version") or "?"

local DB_DEFAULTS = {
    enabled = true,
    debug = false,
    autoCompetitivePlaystyle = true,
    -- One-shot migration sentinel. Existing installs may have `debug=true`
    -- stuck from a prior `/apscout debug on` (default flipped from "on-stuck"
    -- to "off after explicit toggle" in this version). When the key is
    -- absent we force `debug=false` exactly once, then mark migrated so
    -- subsequent user toggles persist normally.
    debugDefaultMigrated = false,
    -- Pre-transport screenshot CVar values, captured once when we force
    -- screenshotQuality/screenshotFormat for QR reliability. Restored on
    -- /apscout off so users who run the addon once don't get stuck with larger
    -- JPG manual screenshots forever. nil = never changed by us.
    priorScreenshotQuality = nil,
    priorScreenshotFormat = nil,
    -- PVEFrame movement state. nil = never moved (use Blizzard's UIPanelLayout
    -- default). Once user Alt+drags the LFG window, OnDragStop writes
    -- {point, x, y} from GetPoint(); OnShow restore replays it next time
    -- the panel opens. Defensive PLAYER_LOGOUT save catches positions changed
    -- via slash macros / scripted moves.
    pveFramePosition = nil,
    -- QR frame position. nil = default TOPLEFT. Stored as canonical top-left
    -- offsets relative to UIParent: {x=number, y=number}. y is normally <= 0.
    qrFramePosition = nil,
}

-- Session lifecycle. INVARIANT: isSessionActive == true ⇔ companion overlay
-- visible.
local isSessionActive = false
local sessionGen = 0             -- bumped in StartSession; deferred cleanups verify match

-- Set by event handlers (pure boolean assignment; primitives can't carry
-- taint to readers). Drained by scan-tick from a clean native-scheduler frame.
local scanDirty = false

-- ───────────────────────────────────────────────────────────
-- QR Code transport
--
-- Companion side decodes via pyzbar (zbar lib — battle-tested QR reader, ships
-- bundled libzbar-64.dll on Windows via pip). Earlier opencv-based decoder was
-- swapped out: cv2.QRCodeDetector empirically fails on QR Version ≥25 produced
-- by 30-applicant payloads at typical 3-4 px module sizes; pyzbar handles them.
--
-- WHY row-RLE rendering: a Version 25 QR has 117x117 = 13689 modules. One
-- texture per module crashes WoW's renderer (verified empirically with the
-- prior 23400-tile pixel-marker design — UI hard-froze on Show). Row-based
-- run-length encoding folds adjacent black modules into single rectangle
-- textures — typical QR has ~10-15 runs per row, so 117 rows × 12 runs ≈ 1400
-- textures worst case. Well within the ~5000 safe texture budget.
--
-- WHY frame stays VISIBLE (alpha=1) for the entire active session, not
-- alpha=0 between shots: tried alpha-flicker (Show()'d at alpha=0 between
-- shots, alpha=1 for one frame around Screenshot()) — Screenshot() in the
-- After(0) callback empirically fires before SetAlpha(1) reaches the GPU
-- framebuffer on real-world WoW setups, capturing alpha=0 (= no QR on JPG, no
-- APS1 marker, companion logs "skip — no APS1 marker" forever). The earlier
-- Show→After(50ms)→Screenshot→Hide cycle had its own race at non-integer
-- DPI scales (first-render-missed-framebuffer). Constant alpha=1 from
-- StartSession to EndSession deferred-Hide is the only timing-robust mode:
-- frame is already fully painted by the time any Screenshot() can fire.
-- Trade-off: user sees the QR (defaults TOPLEFT, covers minimap area) for the whole
-- LFG-hosting duration. Acceptable vs the alternative of "doesn't work".
--
-- 3 px/module is a balance between screen footprint and JPG-quantization
-- robustness. At 4 px the frame for 20 applicants was ~500 px (covered minimap
-- + buff bar). At 3 px the same payload fits in ~375 px. Reed-Solomon ECC at
-- level M (15% recovery) handles JPG noise on 3×3 module blocks reliably; 2 px
-- modules decoded unreliably in early prototypes (JPG DCT artifacts blurred
-- 1-pixel-wide runs). screenshotQuality=8 (set in EnsureScreenshotCVars)
-- provides headroom for the smaller modules.
local QR_MODULE_PX = 3                 -- screen pixels per QR module
local QR_RENDER_SETTLE_S = 0.3         -- lets QR paint reach framebuffer before Screenshot()
-- Quiet zone is the white border the spec mandates around a QR (4 modules
-- per ISO/IEC 18004). pyzbar/zbar tolerates 2 modules reliably on clean
-- digital sources where finder patterns aren't degraded by print/camera noise
-- — saves 2 * QR_MODULE_PX * 2 = 12 px on each axis (visible win at typical
-- frame size). If decode rate ever drops, bump back to 4.
local QR_QUIET_ZONE = 2                -- modules of white border around QR
local QR_EC_LEVEL = 2                  -- error correction: 1=L 2=M 3=Q 4=H. M=15% recovery

local qrFrame = nil                    -- containing frame
local qrBackground = nil               -- one white texture covering entire frame
local qrTexturePool = {}               -- pool of black-module rectangle textures (reused)
local qrTextureUsed = 0                -- count of textures CURRENTLY shown (rest hidden)
local qrFrameCreated = false           -- one-shot init guard
local qrCurrentSize = 0                -- current frame side length in screen pixels (0 = unknown)

-- forward-decl locals so helpers and consumers can reference each other regardless
-- of definition order; assignment via `name = function(...)` lands on the LOCAL slot.
-- WHY MaybeTriggerScreenshot here: EndSession calls it before MaybeTriggerScreenshot
-- is defined further down. Without the forward-decl, Lua resolves the name as
-- _G.MaybeTriggerScreenshot (= nil) and call fails with "attempt to call a nil value".
local SafeStr, APSPrint, InitDB, StartSession, EndSession, CheckSessionTransition,
      MaybeTriggerScreenshot,
      -- Settings panel (pinned above PVEFrame). Forward-decl'd so slash handler
      -- + PLAYER_LOGIN handler can reference before bodies are defined.
      _SetEnabled, _SetDebug, _SetAutoCompetitivePlaystyle, _AttachSettingsPanel,
      _AddSettingsRow, _SetWidgetTooltip,
      -- Visibility coordinator + interaction-frame tracking. Replaces direct
      -- qrFrame:Show/Hide calls so a single function decides visibility from
      -- three orthogonal axes: isSessionActive (auto), _qrSuppressedByInteraction
      -- (auto, see below), qrAlwaysVisible (manual debug override).
      _RefreshQRVisibility, _RefreshQRMouse, _RecomputeInteractionSuppression,
      _TryHookInfoPanels, _OnInteractionEvent,
      -- PVEFrame movement (Phase 2). Forward-decl'd so PLAYER_LOGIN handler
      -- and _AttachSettingsPanel's ADDON_LOADED watcher can both reference it
      -- before the body is defined further down.
      _SetupPVEFrameMovement,
      -- Group Finder creation helpers. Kept separate from QR/session state:
      -- this defaults Blizzard's own entry-creation form only.
      _SetupLFGAutoCompetitive, _MaybeAutoSelectCompetitive
-- Forward-decl mutable state used by StartSession/EndSession/reset. WHY: those
-- functions assign via bare `x = ...`; without forward-decl, the `local` keyword
-- on declarations later in this file would shadow them and the bare assignments
-- silently target globals.
-- qrAlwaysVisible is forward-decl'd here so EndSession (above the slash handler
-- that owns the toggle) can preserve the user's debug visibility setting when
-- session ends.
-- qrMoveMode is opt-in mouse/drag mode. Normal visible QR must not capture
-- mouse input because it sits over gameplay HUD while hosting.
-- _qrSuppressedByInteraction: orthogonal to session/debug — true while any
-- tracked Blizzard interaction frame (vendor, NPC, quest, mail, bank, taxi,
-- character, map, etc.) is open. Hides QR so user can read those windows
-- without the QR overlay obscuring text. Companion misses ~10-30s of emits
-- while user has interaction window open — acceptable per scope.
local lastSnapshotHash, lastShotTime, pendingShotDirty,
      qrAlwaysVisible, qrMoveMode, suppressShotsUntil,
      _qrSuppressedByInteraction, lastQREncodeMode,
      lastQREncodeBytes, lastQREncodeError

-- Settings panel state. settingsFrame = parent of all widgets; created lazily
-- in _AttachSettingsPanel. settingsFrameAttached = one-shot init guard.
-- stackedHeight = running tally of (rowHeight + ROW_GAP) used by
-- _AddSettingsRow to anchor next widget under the title and resize the frame.
local settingsFrame, enabledCheckbox, debugCheckbox, autoCompetitiveCheckbox
local settingsFrameAttached = false
local stackedHeight = 0

local lfgAutoCompetitiveHooksSetup = false
local lfgAutoCompetitiveApplying = false
local lfgAutoCompetitiveHookError = nil
local lfgAutoCompetitiveTouchedPanels = setmetatable({}, { __mode = "k" })

-- ───────────────────────────────────────────────────────────
-- helpers

local function IsSecretValue(v)
    local issv = _G.issecretvalue
    return issv and issv(v) or false
end

SafeStr = function(v, secretFallback)
    -- Boundary cleanse for C_LFGList field reads. Secret detection must be
    -- the first operation on potential API values: even tostring(secret), type
    -- checks after stringification, or string ops can propagate secret-taint.
    if IsSecretValue(v) then
        if secretFallback ~= nil then return secretFallback end
        return "?"
    end
    if v == nil then return "" end
    if type(v) == "boolean" then return v and "1" or "0" end
    local s = tostring(v)
    -- ~ historically used as field separator in chatlog era; kept as defensive
    -- substitution since some companion code paths still parse on it as a
    -- delimiter when displaying free-text fields.
    s = s:gsub("~", "-")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")  -- color start |cAARRGGBB
    s = s:gsub("|c%x%x%x%x%x%x", "")      -- short color |cRRGGBB
    s = s:gsub("|r", "")                   -- color reset
    s = s:gsub("|H[^|]*|h", "")            -- link start
    s = s:gsub("|h", "")                   -- link end
    s = s:gsub("|T[^|]*|t", "")            -- texture
    s = s:gsub("|t", "")                   -- texture end
    s = s:gsub("|n", " ")                  -- newline → space
    s = s:gsub("|", "")                    -- any remaining bare | (defensive)
    -- Newlines/tabs in clipboard-pasted comments would corrupt our binary
    -- length-prefixed encoding (the count byte covers utf-8 bytes, but companion
    -- displays the string verbatim — multi-line comments look broken in overlay).
    s = s:gsub("[\r\n\t]+", " ")
    return s
end

local function SafeDiag(v)
    if IsSecretValue(v) then return "<secret>" end
    if v == nil then return "nil" end
    return tostring(v)
end

local function SafeNumber(v, default)
    if IsSecretValue(v) then return default or 0 end
    if v == nil then return default or 0 end
    local tv = type(v)
    if tv ~= "number" and tv ~= "string" then return default or 0 end
    local n = tonumber(v)
    if n == nil or n ~= n then return default or 0 end
    return n
end

local function SafeRoundedNumber(v, default)
    return math.floor(SafeNumber(v, default) + 0.5)
end

local function SafeTable(v)
    if IsSecretValue(v) then return nil end
    if type(v) == "table" then return v end
    return nil
end

local function SafeEnumKey(v, default)
    if IsSecretValue(v) then return default end
    local tv = type(v)
    if tv == "string" or tv == "number" then return v end
    return default
end

local function IsChatMessagingLockdown()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
           and C_ChatInfo.InChatMessagingLockdown() or false
end

InitDB = function()
    if type(ApplicantScoutDB) ~= "table" then ApplicantScoutDB = {} end
    for k, v in pairs(DB_DEFAULTS) do
        if ApplicantScoutDB[k] == nil then ApplicantScoutDB[k] = v end
    end
    if not ApplicantScoutDB.debugDefaultMigrated then
        ApplicantScoutDB.debug = false
        ApplicantScoutDB.debugDefaultMigrated = true
    end
end

APSPrint = function(msg)
    print("|cff00ff7fApplicantScout|r " .. msg)
end

-- ───────────────────────────────────────────────────────────
-- Session lifecycle: tied to the player's own LFG listing.
--   StartSession: invariant transition false→true. Resets snapshot dedup
--                 state for fresh full snapshot.
--   EndSession:   invariant transition true→false. Force-emits final empty
--                 snapshot (clears companion overlay state).
--   sessionGen:   monotonic counter — verified by EndSession's deferred Hide
--                 callback so a fast Start→End→Start sequence doesn't have
--                 the prior End's deferred Hide fire mid-new-session.

StartSession = function()
    if isSessionActive then return end
    isSessionActive = true
    sessionGen = sessionGen + 1

    -- QR transport state reset: force fresh full snapshot at session start.
    -- BuildPayload emits VERSION on every shot so companion-launched-mid-session
    -- still receives region/realm info from the freshest backlog snapshot.
    lastSnapshotHash = nil
    pendingShotDirty = false
    lastQREncodeMode = "never"
    lastQREncodeBytes = 0
    lastQREncodeError = nil

    -- QR_RENDER_SETTLE_S grace before first snapshot. The frame just transitioned from
    -- Hide()'d to Show()+alpha=1 — on some setups (high refresh rate, deferred
    -- compositors, non-integer DPI) the GPU framebuffer needs multiple render
    -- passes before the painted QR textures are visible to Screenshot(). Without
    -- this gate, the very first snapshot after listing creation can capture an
    -- empty-or-half-painted frame → no APS1 marker → companion logs "skip" and
    -- overlay never appears. MaybeTriggerScreenshot honours this via
    -- suppressShotsUntil; pendingShotDirty=true ensures the scan-tick drain
    -- retries once the window expires (within ~0.55s of session start).
    suppressShotsUntil = GetTime() + QR_RENDER_SETTLE_S

    -- Show QR frame fully visible (alpha=1) for the entire active session.
    -- Reasoning at top of file: alpha-flicker captured alpha=0 framebuffers
    -- in real-world WoW setups (Screenshot() outraces SetAlpha propagation),
    -- so the frame stays painted at alpha=1 from session start to
    -- EndSession's deferred Hide. Visible cost: defaults over TOPLEFT minimap
    -- region while user hosts. /apscout qrvisible toggle still overrides (forces
    -- visible even outside session, debug aid). _qrSuppressedByInteraction
    -- can also hide it transiently while user has vendor/NPC/etc open.
    -- _RefreshQRVisibility encodes all three axes; suppressShotsUntil set
    -- BEFORE the call so the hidden→shown transition guard inside doesn't
    -- need to overwrite a freshly-set value.
    _RefreshQRVisibility()
end

EndSession = function()
    if not isSessionActive then return end
    isSessionActive = false  -- claim the transition; further scans early-return

    scanDirty = false
    -- Force-shot path bypasses suppressShotsUntil via force=true, but clear
    -- the gate explicitly so a fresh StartSession that happens before the
    -- old gate would have expired starts with a clean render-settle window.
    suppressShotsUntil = 0

    -- Final force-shot: BuildPayload now sees isSessionActive=false → entry=nil
    -- → emits has_listing=0 + 0 applicants. Companion's apply_snapshot diff:
    -- removes all applicants, clears listing → overlay hides. Bypasses dedup +
    -- throttle (force=true) since this is one-shot terminal event.
    MaybeTriggerScreenshot(true)
    -- Defensive: force-shot path resets pendingShotDirty on success, but if it
    -- early-returned (qrFrame missing, QR encode failure) the flag could persist
    -- across sessions and trigger empty drains in the scan ticker. Clear here.
    pendingShotDirty = false

    -- Schedule deferred Hide AFTER the final clear-shot has had a chance to
    -- fire. The screenshot path inside MaybeTriggerScreenshot is
    -- C_Timer.After(0, Screenshot()), so the actual capture happens NEXT
    -- frame. Hiding synchronously here would make the screenshot capture an
    -- empty screen (no QR), companion never sees the clear signal, overlay
    -- stuck showing pre-end applicants. QR_RENDER_SETTLE_S lets the
    -- Screenshot() fire first.
    -- All gating (qrAlwaysVisible, new-session-started) re-checked at fire
    -- time so the deferred Hide respects the latest toggle state — important
    -- for /apscout off which resets qrAlwaysVisible right after EndSession.
    if qrFrame then
        local genAtSchedule = sessionGen
        C_Timer.After(QR_RENDER_SETTLE_S, function()
            -- Re-enter the visibility coordinator only if we're still in the
            -- same gen AND the session has actually ended. _RefreshQRVisibility
            -- handles qrAlwaysVisible (debug override stays visible across
            -- session boundaries). Without the gen check a fast Start→End→Start
            -- sequence would apply this old End's "hide" decision atop a fresh
            -- session's StartSession-driven Show.
            if sessionGen == genAtSchedule and not isSessionActive then
                _RefreshQRVisibility()
            end
        end)
    end
end

CheckSessionTransition = function()
    local hasEntry = C_LFGList.HasActiveEntryInfo()
    local entry = nil
    if hasEntry then
        entry = SafeTable(C_LFGList.GetActiveEntryInfo())
    end
    local hosting = entry ~= nil

    if hosting and not isSessionActive then
        StartSession()
    elseif not hosting and isSessionActive then
        EndSession()
    end
    -- Returns the active LFG entry (or nil) so the scan-tick caller can pass
    -- it straight to MaybeTriggerScreenshot — saves a second
    -- C_LFGList.GetActiveEntryInfo() call per scan.
    return entry
end

-- ───────────────────────────────────────────────────────────
-- event dispatch (raw frame; rationale at top)

-- Single transition logger: clean→dirty fires the debug print once per
-- scan cycle (avoids spam during applicant bursts where 30+ events fire <1s
-- apart). All events funnel here; behavior decisions live in ScanAndEmit /
-- CheckSessionTransition — DRY-locked.
local function MarkDirty(reason)
    local wasClean = not scanDirty
    scanDirty = true
    if wasClean and ApplicantScoutDB and ApplicantScoutDB.debug then
        print("|cff999999[APS-debug]|r DIRTY reason=" .. tostring(reason))
    end
end

-- ───────────────────────────────────────────────────────────
-- QR frame setup
--
-- One containing frame, sized to whatever QR version we just generated
-- (adaptive). White background covers the entire frame; row-RLE pool of
-- black-rectangle textures draws the QR data.
local QR_POSITION_LIMIT = 100000

local function _IsFiniteQRPositionNumber(v)
    return type(v) == "number" and v == v
           and v > -QR_POSITION_LIMIT and v < QR_POSITION_LIMIT
end

local function _NormalizeQRPosition(pos)
    if type(pos) ~= "table" then return 0, 0, false end
    local x, y = pos.x, pos.y
    if not (_IsFiniteQRPositionNumber(x) and _IsFiniteQRPositionNumber(y)) then
        return 0, 0, false
    end
    return x, y, true
end

local function _ClampQRPosition(x, y, frameSize)
    frameSize = _IsFiniteQRPositionNumber(frameSize) and frameSize or 64
    local parentW = UIParent and UIParent:GetWidth() or 0
    local parentH = UIParent and UIParent:GetHeight() or 0
    if not _IsFiniteQRPositionNumber(parentW) or parentW <= 0 then parentW = frameSize end
    if not _IsFiniteQRPositionNumber(parentH) or parentH <= 0 then parentH = frameSize end

    local maxX = parentW - frameSize
    local minY = frameSize - parentH
    if maxX < 0 then maxX = 0 end
    if minY > 0 then minY = 0 end

    if x < 0 then x = 0 elseif x > maxX then x = maxX end
    if y > 0 then y = 0 elseif y < minY then y = minY end
    return x, y
end

local function _GetQRFrameSize()
    if qrFrame then
        local w = qrFrame:GetWidth()
        if _IsFiniteQRPositionNumber(w) and w > 0 then return w end
    end
    return qrCurrentSize > 0 and qrCurrentSize or 64
end

local function _ApplyQRFramePosition()
    if not qrFrame then return end
    local x, y = _NormalizeQRPosition(ApplicantScoutDB and ApplicantScoutDB.qrFramePosition)
    x, y = _ClampQRPosition(x, y, _GetQRFrameSize())
    qrFrame:ClearAllPoints()
    qrFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
end

local function _SaveQRFramePositionFromFrame()
    if not (qrFrame and ApplicantScoutDB) then return false end
    local frameLeft, frameTop = qrFrame:GetLeft(), qrFrame:GetTop()
    local parentLeft = UIParent and UIParent:GetLeft() or 0
    local parentTop = UIParent and UIParent:GetTop() or (UIParent and UIParent:GetHeight() or 0)
    if not (_IsFiniteQRPositionNumber(frameLeft) and _IsFiniteQRPositionNumber(frameTop)
            and _IsFiniteQRPositionNumber(parentLeft) and _IsFiniteQRPositionNumber(parentTop)) then
        return false
    end
    local x = frameLeft - parentLeft
    local y = frameTop - parentTop
    x, y = _ClampQRPosition(x, y, _GetQRFrameSize())
    ApplicantScoutDB.qrFramePosition = { x = x, y = y }
    _ApplyQRFramePosition()
    return true
end

local function _ResetQRFramePosition()
    if ApplicantScoutDB then ApplicantScoutDB.qrFramePosition = nil end
    _ApplyQRFramePosition()
end

local function _CurrentQRPositionText()
    if not qrFrame then return "(frame missing)" end
    local x, y, valid = _NormalizeQRPosition(ApplicantScoutDB and ApplicantScoutDB.qrFramePosition)
    x, y = _ClampQRPosition(x, y, _GetQRFrameSize())
    local saved = valid and "saved" or "default"
    return string.format("%s @ (%.0f, %.0f)", saved, x, y)
end

local function _OnQRFrameDragStart(self)
    if not qrMoveMode or not IsAltKeyDown() then return end
    local ok = pcall(self.StartMoving, self)
    if ok then self.apsMoving = true end
end

local function _OnQRFrameDragStop(self)
    if not self.apsMoving then return end
    pcall(self.StopMovingOrSizing, self)
    self.apsMoving = false
    if _SaveQRFramePositionFromFrame() then
        APSPrint("QR position saved: " .. _CurrentQRPositionText())
    else
        APSPrint("QR position not saved — frame anchor unavailable")
    end
end

local function CreateQRFrame()
    if qrFrameCreated then return end
    qrFrame = CreateFrame("Frame", "ApplicantScoutQRFrame", UIParent)
    qrFrame:SetIgnoreParentScale(true)
    -- DIALOG strata: above gameplay HUD but below modal popups (StaticPopup,
    -- ColorPicker, dropdowns). Avoids FULLSCREEN_DIALOG which has been
    -- empirically observed to interfere with input chain on heavy renders.
    qrFrame:SetFrameStrata("DIALOG")
    qrFrame:SetSize(64, 64)  -- placeholder; PaintQR resizes per-snapshot
    qrFrame:SetMovable(true)
    qrFrame:SetClampedToScreen(true)
    qrFrame:RegisterForDrag("LeftButton")
    qrFrame:SetScript("OnDragStart", _OnQRFrameDragStart)
    qrFrame:SetScript("OnDragStop", _OnQRFrameDragStop)
    _ApplyQRFramePosition()

    -- White background — single texture covering the whole frame, BACKGROUND
    -- layer. Black module textures (BORDER layer above) overlay it. pyzbar's
    -- QR detector relies on black-on-white contrast — this gives it the
    -- canonical look.
    qrBackground = qrFrame:CreateTexture(nil, "BACKGROUND")
    qrBackground:SetColorTexture(1, 1, 1, 1)
    qrBackground:SetAllPoints(qrFrame)

    qrFrameCreated = true
    -- Hidden by default. StartSession does Show()+SetAlpha(1); EndSession
    -- defers Hide() after final clear-shot fires.
    if _RefreshQRMouse then _RefreshQRMouse() end
    qrFrame:Hide()
end

-- /apscout qrvisible state — forces frame to stay visible regardless of session
-- state (debug aid for visual inspection). Forward-declared at top so EndSession
-- can respect the toggle when hiding the frame.
qrAlwaysVisible = false
qrMoveMode = false

-- ───────────────────────────────────────────────────────────
-- QR auto-fade on Blizzard interaction frames
--
-- WHY: at Version 25 with 30 applicants the QR is ~600-900px wide on a 1440p
-- display — wide enough to obscure most Blizzard panels (vendor, gossip,
-- quest text, mail, bank, taxi, etc.). Hiding the QR while ANY tracked
-- interaction frame is open lets the user actually read those windows.
-- Companion misses the screenshots during the fade window — acceptable
-- because the user isn't actively monitoring applicants while they're at a
-- vendor. _RefreshQRVisibility re-arms suppressShotsUntil on each
-- hidden→shown transition so the next Screenshot() doesn't capture an
-- unpainted post-Hide frame.
--
-- WHY hybrid event + OnShow/OnHide: vendor-class frames have dedicated
-- events (MERCHANT_SHOW etc) that fire even when third-party addons replace
-- the Blizzard frame entirely (BetterMerchant, custom gossip overlays).
-- Info panels (CharacterFrame, WorldMapFrame, EncounterJournalFrame, etc.)
-- have no dedicated events but are rarely replaced — OnShow/OnHide hooks on
-- the frame itself are reliable for those.
--
-- WHY ADDON_LOADED-driven re-scan: many info panels live in load-on-demand
-- addons (Blizzard_AchievementUI, Blizzard_EncounterJournal, etc.) and don't
-- exist at PLAYER_LOGIN. Hooking via re-scan on every ADDON_LOADED catches
-- them as their addons load. _hookedInfoPanels set keeps re-scans idempotent.

-- desired = true  → event opens an interaction frame (suppress QR)
-- desired = false → event closes one (clear that slot)
-- desired = nil   → event ignored (no state change)
local INTERACTION_EVENT_DESIRED = {
    MERCHANT_SHOW          = true,  MERCHANT_CLOSED        = false,
    GOSSIP_SHOW            = true,  GOSSIP_CLOSED          = false,
    QUEST_DETAIL           = true,  QUEST_GREETING         = true,
    QUEST_PROGRESS         = true,  QUEST_COMPLETE         = true,
    QUEST_FINISHED         = false,
    MAIL_SHOW              = true,  MAIL_CLOSED            = false,
    BANKFRAME_OPENED       = true,  BANKFRAME_CLOSED       = false,
    GUILDBANKFRAME_OPENED  = true,  GUILDBANKFRAME_CLOSED  = false,
    -- VOID_STORAGE_* removed in Midnight 12.x — `Frame:RegisterEvent` warns
    -- "Attempt to register unknown event" 3x. Void storage UI no longer fires
    -- those events; the frame uses different mechanics. No replacement event
    -- is needed (companion's QR fade-on-interaction list isn't user-facing).
    TAXIMAP_OPENED         = true,  TAXIMAP_CLOSED         = false,
    BARBER_SHOP_OPEN       = true,  BARBER_SHOP_CLOSE      = false,
    TRADE_SHOW             = true,  TRADE_CLOSED           = false,
    AUCTION_HOUSE_SHOW     = true,  AUCTION_HOUSE_CLOSED   = false,
    TRADE_SKILL_SHOW       = true,  TRADE_SKILL_CLOSE      = false,
}

-- Map event name → "kind" (slot key). Multiple events share a slot
-- (QUEST_DETAIL/GREETING/PROGRESS/COMPLETE all set "quest" true; QUEST_FINISHED
-- clears it). Set-true events are idempotent — repeated writes don't break
-- aggregation because they all write the same slot+value.
local INTERACTION_EVENT_KIND = {
    MERCHANT_SHOW          = "vendor",       MERCHANT_CLOSED        = "vendor",
    GOSSIP_SHOW            = "gossip",       GOSSIP_CLOSED          = "gossip",
    QUEST_DETAIL           = "quest",        QUEST_GREETING         = "quest",
    QUEST_PROGRESS         = "quest",        QUEST_COMPLETE         = "quest",
    QUEST_FINISHED         = "quest",
    MAIL_SHOW              = "mail",         MAIL_CLOSED            = "mail",
    BANKFRAME_OPENED       = "bank",         BANKFRAME_CLOSED       = "bank",
    GUILDBANKFRAME_OPENED  = "guildbank",    GUILDBANKFRAME_CLOSED  = "guildbank",
    TAXIMAP_OPENED         = "taxi",         TAXIMAP_CLOSED         = "taxi",
    BARBER_SHOP_OPEN       = "barber",       BARBER_SHOP_CLOSE      = "barber",
    TRADE_SHOW             = "trade",        TRADE_CLOSED           = "trade",
    AUCTION_HOUSE_SHOW     = "auctionhouse", AUCTION_HOUSE_CLOSED   = "auctionhouse",
    TRADE_SKILL_SHOW       = "professions",  TRADE_SKILL_CLOSE      = "professions",
}

-- Frames without dedicated events. OnShow/OnHide hooked when the frame
-- becomes available. Most are LoD; _TryHookInfoPanels re-runs on
-- ADDON_LOADED to catch each as it materializes.
local INFO_PANEL_FRAMES = {
    "WorldMapFrame", "EncounterJournalFrame", "SpellBookFrame",
    "PlayerSpellsFrame", "CharacterFrame", "CollectionsJournal",
    "AchievementFrame", "CommunitiesFrame", "FriendsFrame",
    "ProfessionsFrame", "FlightMapFrame", "SettingsPanel",
}

local _interactionSlots = {}  -- kind → bool (only set when active; nil = inactive)
local _hookedInfoPanels  = {} -- frame name → true once OnShow/OnHide hooks installed

-- Single visibility decision. Three axes:
--   isSessionActive             — auto: player is hosting an LFG listing
--   _qrSuppressedByInteraction  — auto: a tracked interaction frame is open
--   qrAlwaysVisible             — manual: /apscout qrvisible debug override
--   qrMoveMode                  — manual: /apscout qrmove drag/debug mode
-- Debug override wins over interaction fade (user explicitly said "show me").
_RefreshQRMouse = function()
    if not qrFrame then return end
    qrFrame:EnableMouse(qrMoveMode and true or false)
end

_RefreshQRVisibility = function()
    if not qrFrame then return end
    local wasShown = qrFrame:IsShown()
    local shouldShow = (isSessionActive and not _qrSuppressedByInteraction)
                       or qrAlwaysVisible
                       or qrMoveMode
    if shouldShow and not wasShown then
        qrFrame:SetAlpha(1)
        qrFrame:Show()
        -- WHY QR_RENDER_SETTLE_S grace on every hidden→shown transition (not just session
        -- start): the GPU framebuffer needs paint time after Show, same race
        -- as session-start. Without this, a vendor-close → fast Screenshot
        -- captures the post-Hide unpainted frame → companion logs "no APS1".
        -- Reuses the existing suppression mechanism — no parallel state.
        suppressShotsUntil = GetTime() + QR_RENDER_SETTLE_S
        pendingShotDirty = true  -- scan-tick drain retries post-grace
    elseif not shouldShow and wasShown then
        qrFrame:Hide()
    end
end

-- Aggregator: walks events table + info-panel hooks to determine if any
-- interaction frame is currently open. Calls _RefreshQRVisibility only when
-- the suppression boolean actually flips — avoids redundant Show/Hide calls
-- on every event burst.
_RecomputeInteractionSuppression = function()
    local anyActive = false
    for _, active in pairs(_interactionSlots) do
        if active then anyActive = true; break end
    end
    if not anyActive then
        for name in pairs(_hookedInfoPanels) do
            local frame = _G[name]
            if frame and frame:IsShown() then
                anyActive = true; break
            end
        end
    end
    if anyActive ~= (_qrSuppressedByInteraction or false) then
        _qrSuppressedByInteraction = anyActive
        _RefreshQRVisibility()
    end
end

-- Event-driven slot updater. Idempotent: repeated set-true for the same kind
-- writes the same slot. desired=nil events filtered upstream by EVENT_HANDLERS
-- registration (only events present in INTERACTION_EVENT_DESIRED are bound).
_OnInteractionEvent = function(event)
    local kind = INTERACTION_EVENT_KIND[event]
    local desired = INTERACTION_EVENT_DESIRED[event]
    if not kind or desired == nil then return end
    -- Sparse storage: false → nil to keep the table minimal; aggregator's
    -- pairs() loop only walks active slots.
    _interactionSlots[kind] = desired or nil
    _RecomputeInteractionSuppression()
end

-- Lazy hookup. Called at PLAYER_LOGIN and every ADDON_LOADED. Idempotent via
-- _hookedInfoPanels set — once a frame is hooked, subsequent calls skip it.
-- Frames not yet existing (LoD that hasn't loaded) are silently skipped;
-- next ADDON_LOADED triggers another scan.
_TryHookInfoPanels = function()
    for _, name in ipairs(INFO_PANEL_FRAMES) do
        if not _hookedInfoPanels[name] then
            local frame = _G[name]
            if frame and frame.HookScript then
                frame:HookScript("OnShow", _RecomputeInteractionSuppression)
                frame:HookScript("OnHide", _RecomputeInteractionSuppression)
                _hookedInfoPanels[name] = true
            end
        end
    end
end

-- ───────────────────────────────────────────────────────────
-- PVEFrame movement (Alt+drag, persistent across /reload)
--
-- WHY in-place HookScript instead of BlizzMove's PanelDragBarTemplate
-- secure-handle: BlizzMove's complexity supports DOZENS of frames with
-- shared combat-lockdown queues. We support exactly one frame (PVEFrame).
-- SetMovable / RegisterForDrag / OnDragStart / OnDragStop / SetPoint /
-- SetUserPlaced are all unprotected on PVEFrame in Midnight 12.x — verified
-- empirically by BlizzMove itself using these APIs directly. The only
-- protected path is Show/Hide from addon code, which we never call.
-- SetPoint mid-combat may error on protected frames; guard via
-- InCombatLockdown().
--
-- WHY title-bar-only drag (NOT whole-frame): clicking applicant
-- buttons / tabs inside PVEFrame must NOT initiate a window drag. Drag from
-- TitleContainer (or NineSlice fallback) keeps child clicks intact.
--
-- WHY pcall on initial SetMovable: future Blizzard policy change could
-- protect this method on PVEFrame. Pcall fails soft → user falls back to
-- BlizzMove. No addon-load crash.
--
-- WHY BlizzMove cohabitation: if user has BlizzMove installed, defer
-- entirely (early return). Avoids two competing drag handlers fighting over
-- the same frame.
local function _OnPVEFrameDragStart()
    if InCombatLockdown() then return end
    PVEFrame:StartMoving()
    PVEFrame.apsMoving = true
end

local function _OnPVEFrameDragStop()
    if not PVEFrame.apsMoving then return end
    PVEFrame:StopMovingOrSizing()
    PVEFrame.apsMoving = false
    -- WARNING (CLAUDE.md trap): GetPoint() returns nil if no anchor set.
    -- Guard before writing to DB to avoid clobbering valid prior position
    -- with a nil entry that next OnShow would silently skip.
    local point, _, _, x, y = PVEFrame:GetPoint()
    if point and ApplicantScoutDB then
        ApplicantScoutDB.pveFramePosition = { point = point, x = x, y = y }
    end
end

_SetupPVEFrameMovement = function()
    if not _G.PVEFrame then return end
    if PVEFrame.apsMovementSetup then return end  -- idempotent

    -- BlizzMove cohabitation: it owns the frame, no-op our setup.
    if C_AddOns and C_AddOns.IsAddOnLoaded
       and C_AddOns.IsAddOnLoaded("BlizzMove") then
        return
    end

    -- Defensive: future Blizzard patch might protect SetMovable on PVEFrame.
    -- Pcall fail-soft so addon load doesn't crash.
    local ok, err = pcall(PVEFrame.SetMovable, PVEFrame, true)
    if not ok then
        APSPrint("|cffff8888warning|r could not enable LFG window movement: "
                 .. tostring(err) .. " — install BlizzMove if you need this")
        return
    end
    PVEFrame:SetClampedToScreen(true)

    -- Three-tier title-region fallback. TitleContainer is the modern
    -- (Dragonflight+) title bar widget; NineSlice is the chrome border;
    -- whole frame is last-resort drag-from-anywhere mode.
    local titleRegion = PVEFrame.TitleContainer or PVEFrame.NineSlice or PVEFrame
    titleRegion:EnableMouse(true)
    titleRegion:RegisterForDrag("LeftButton")
    -- HookScript chains atop any existing handler. PVEFrame's title widgets
    -- don't register OnDragStart by default in 12.x, but HookScript is
    -- forward-compatible if Blizzard adds one later.
    titleRegion:HookScript("OnDragStart", _OnPVEFrameDragStart)
    titleRegion:HookScript("OnDragStop", _OnPVEFrameDragStop)

    -- Position restore on every Show. WHY C_Timer.After(0, ...) defer:
    -- Blizzard's UIPanelLayout positions PVEFrame the same frame OnShow
    -- fires; inline SetPoint can lose visually for one frame to layout-cache
    -- restore (visible flicker on /reload). The 0-delay timer dispatches
    -- next frame after layout cache settles. Re-checks lockdown + IsShown
    -- since user could close PVEFrame in the one-frame gap.
    PVEFrame:HookScript("OnShow", function(self)
        local saved = ApplicantScoutDB and ApplicantScoutDB.pveFramePosition
        if not (saved and saved.point) then return end
        if InCombatLockdown() then return end
        C_Timer.After(0, function()
            if InCombatLockdown() then return end
            if not self:IsShown() then return end
            -- WARNING (CLAUDE.md SetUserPlaced trap): order is
            -- ClearAllPoints -> SetPoint -> SetUserPlaced(true). Wrong
            -- order leaks WoW's layout-cache restore atop our anchor.
            self:ClearAllPoints()
            self:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
            self:SetUserPlaced(true)
        end)
    end)

    PVEFrame.apsMovementSetup = true
end

-- Set screenshot format. Reed-Solomon ECC handles JPG quantization noise on
-- 3-px QR modules but tolerance shrinks vs 4 px — bump quality floor to 8
-- (~75% JPG quality) for safety with the smaller modules. Idempotent across
-- /reloads. SetCVar persists in Config.wtf — user's own manual screenshots
-- also get this quality (acceptable side-effect, undone on /apscout off via
-- RestoreScreenshotCVars).
local function EnsureScreenshotCVars()
    if not (SetCVar and GetCVar) then return end
    local q = tonumber(GetCVar("screenshotQuality")) or 0
    if q < 8 then
        -- Stash original ONCE — if user already disabled+enabled this would
        -- otherwise overwrite our recorded prior value with our own escalated 8.
        if ApplicantScoutDB and ApplicantScoutDB.priorScreenshotQuality == nil then
            ApplicantScoutDB.priorScreenshotQuality = q
        end
        SetCVar("screenshotQuality", "8")
        -- Verify the write took effect — CVar can be locked / addon load order
        -- can interfere. If readback diverges, JPG quality could affect
        -- decoder reliability silently; loud warn lets user notice.
        local verify = tonumber(GetCVar("screenshotQuality")) or 0
        if verify < 8 then
            if APSPrint then
                APSPrint("WARN: screenshotQuality SetCVar didn't stick (read back " ..
                         verify .. "); QR decode reliability may suffer at 3-px modules")
            end
        elseif APSPrint then
            APSPrint("set screenshotQuality=8 (was " .. q ..
                     ") for QR-decode reliability with 3-px modules")
        end
    end
    local currentFormat = tostring(GetCVar("screenshotFormat") or "")
    if currentFormat:lower() ~= "jpg" then
        if ApplicantScoutDB and ApplicantScoutDB.priorScreenshotFormat == nil then
            ApplicantScoutDB.priorScreenshotFormat = currentFormat
        end
        SetCVar("screenshotFormat", "jpg")
        local verifyFormat = tostring(GetCVar("screenshotFormat") or "")
        if verifyFormat:lower() ~= "jpg" then
            if APSPrint then
                APSPrint("WARN: screenshotFormat SetCVar didn't stick (read back " ..
                         verifyFormat .. "); QR transport expects JPG screenshots")
            end
        elseif APSPrint then
            APSPrint("set screenshotFormat=jpg (was " .. currentFormat ..
                     ") for QR screenshot transport")
        end
    end
end

-- Restore the user's pre-addon screenshot CVars on /apscout off. Each stash is
-- restored independently so one missing prior value never blocks the other.
-- Clears stashes after restore/skip so a fresh enable cycle records the
-- THEN-current values.
local function RestoreScreenshotCVars()
    if not (SetCVar and GetCVar) then return end
    if not ApplicantScoutDB then return end

    if ApplicantScoutDB.priorScreenshotQuality ~= nil then
        local prior = tonumber(ApplicantScoutDB.priorScreenshotQuality) or 0
        local currentQuality = tonumber(GetCVar("screenshotQuality")) or 0
        if prior >= 0 and prior <= 10 then
            if currentQuality == 8 then
                SetCVar("screenshotQuality", tostring(prior))
                if APSPrint then
                    APSPrint("restored screenshotQuality=" .. prior .. " (pre-ApplicantScout value)")
                end
            elseif APSPrint then
                APSPrint("kept screenshotQuality=" .. currentQuality ..
                         " (changed after ApplicantScout forced 8)")
            end
        end
        ApplicantScoutDB.priorScreenshotQuality = nil
    end

    if ApplicantScoutDB.priorScreenshotFormat ~= nil then
        local priorFormat = tostring(ApplicantScoutDB.priorScreenshotFormat or "")
        local currentFormat = tostring(GetCVar("screenshotFormat") or "")
        if priorFormat ~= "" then
            if currentFormat:lower() == "jpg" then
                SetCVar("screenshotFormat", priorFormat)
                if APSPrint then
                    APSPrint("restored screenshotFormat=" .. priorFormat ..
                             " (pre-ApplicantScout value)")
                end
            elseif APSPrint then
                APSPrint("kept screenshotFormat=" .. currentFormat ..
                         " (changed after ApplicantScout forced jpg)")
            end
        end
        ApplicantScoutDB.priorScreenshotFormat = nil
    end
end

local function RestoreScreenshotCVarsWhenSafe(delay, requiredSessionGen)
    local function restoreIfStillDisabled()
        if not ApplicantScoutDB or ApplicantScoutDB.enabled then return end
        if isSessionActive then return end
        if requiredSessionGen and sessionGen ~= requiredSessionGen then return end
        RestoreScreenshotCVars()
    end

    if delay and delay > 0 and C_Timer and C_Timer.After then
        C_Timer.After(delay, restoreIfStillDisabled)
    else
        restoreIfStillDisabled()
    end
end

-- ───────────────────────────────────────────────────────────
-- Payload encoder + QR painter
--
-- Wire format (binary, big-endian; unchanged from prior pixel transport — QR
-- is purely a transport upgrade, the same bytes flow end-to-end):
--   Header:    "APS1" magic + version byte + uint16 length + 2 reserved bytes
--   Listing:   has_listing byte; if 1: uint32 activityID + uint16 categoryID +
--              uint16 difficultyID + key_level byte +
--              len-prefixed dungeonName/listingName/comment (uint8 len + utf8)
--   Version:   has_version byte; if 1: len-prefixed addonVer/gameVer +
--              region_id byte + len-prefixed playerName
--   Apps:      uint16 count; per applicant: uint32 id + uint8 member_idx +
--              uint8 classID + uint16 specID + uint16 ilvl + uint16 score +
--              uint8 role + uint8 nameLen + utf8 name (CLAMPED to 255 bytes)
--   Trailer:   uint32 CRC32 (IEEE 802.3) over [magic..last applicant byte]
--
-- WHY keep the magic + CRC even though QR has its own ECC: the magic gives the
-- companion a quick "is this really our payload" check that catches
-- false-positive QR hits (e.g. user runs the companion against a folder with
-- random QR codes from another addon). CRC catches the rare corner where QR's
-- ECC reports success but a few bits flipped — empirically rare but
-- belt-and-suspenders.
--
-- Applicants sorted by ID before serialization → identical state produces
-- identical bytes → HashSnapshot dedup works reliably.

-- WoW classID 1-13 (retail Midnight). Inverse of LOCALIZED_CLASS_NAMES_MALE.
local CLASS_NAME_TO_ID = {
    WARRIOR=1, PALADIN=2, HUNTER=3, ROGUE=4, PRIEST=5, DEATHKNIGHT=6,
    SHAMAN=7, MAGE=8, WARLOCK=9, MONK=10, DRUID=11, DEMONHUNTER=12, EVOKER=13,
}
local ROLE_NAME_TO_BYTE = { TANK=0, HEALER=1, DAMAGER=2 }

-- LFG status values that mean "applicant gone" (won't appear in companion).
-- Whitelist-by-exclusion: enum names shifted across patches; safer than positive
-- match.
local APP_DEAD_STATUSES = {
    cancelled=true, declined=true, failed=true, timedout=true,
    invitedeclined=true, declined_full=true, declined_delisted=true,
    inviteaccepted=true,
}

-- Big-endian uint packing
local function _Uint32BE(n)
    n = math.floor(SafeNumber(n, 0)) % 4294967296
    return string.char(
        math.floor(n / 16777216) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 256) % 256,
        n % 256
    )
end
local function _Uint16BE(n)
    n = math.floor(SafeNumber(n, 0)) % 65536
    return string.char(math.floor(n / 256), n % 256)
end

-- Return a prefix no longer than maxBytes that never ends inside a UTF-8
-- sequence. Lua 5.1 has byte strings and no native utf8 library.
local function _TruncateUTF8Bytes(str, maxBytes)
    if #str <= maxBytes then return str end

    local start = maxBytes
    while start > 0 do
        local b = string.byte(str, start)
        if not (b and b >= 128 and b <= 191) then
            break
        end
        start = start - 1
    end

    if start <= 0 then return "" end

    local b = string.byte(str, start)
    local len
    if b <= 127 then
        len = 1
    elseif b >= 194 and b <= 223 then
        len = 2
    elseif b >= 224 and b <= 239 then
        len = 3
    elseif b >= 240 and b <= 244 then
        len = 4
    else
        return str:sub(1, start - 1)
    end

    local endsAt = start + len - 1
    if endsAt > maxBytes then
        return str:sub(1, start - 1)
    end

    for i = start + 1, endsAt do
        local cb = string.byte(str, i)
        if not (cb and cb >= 128 and cb <= 191) then
            return str:sub(1, start - 1)
        end
    end

    return str:sub(1, maxBytes)
end

-- Append len-byte + utf-8 bytes to output table. CLAMPS to 255 bytes (safety).
local function _PackLenStr(out, str)
    str = SafeStr(str)
    if #str > 255 then str = _TruncateUTF8Bytes(str, 255) end
    table.insert(out, string.char(#str))
    table.insert(out, str)
end

local function _NormalizeKeystoneLevel(value)
    local n = math.floor(SafeNumber(value, 0))
    if n >= 2 and n <= 50 then return n end
    return 0
end

local function _ExtractKeystoneLevelFromText(value)
    local s = SafeStr(value, "")
    if s == "" then return 0 end
    local m = s:match("%+(%d+)")
    return _NormalizeKeystoneLevel(m)
end

local function _GetListingKeystoneLevel(activityID, listingName, listingComment)
    -- C_LFGList.GetKeystoneForActivity is the listing-level source. Text
    -- parsing stays as fallback because some custom titles/comments include
    -- "+N", while Blizzard's active-entry name often does not.
    local keyLevel = 0
    if C_LFGList and C_LFGList.GetKeystoneForActivity and activityID > 0 then
        keyLevel = _NormalizeKeystoneLevel(C_LFGList.GetKeystoneForActivity(activityID))
    end
    if keyLevel == 0 then
        keyLevel = _ExtractKeystoneLevelFromText(listingName)
    end
    if keyLevel == 0 then
        keyLevel = _ExtractKeystoneLevelFromText(listingComment)
    end
    return keyLevel
end

-- CRC32 IEEE-802.3, table-based. Built once at file load (~5KB memory).
local CRC32_TABLE = {}
do
    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            if c % 2 == 1 then
                c = bit.bxor(bit.rshift(c, 1), 0xEDB88320)
            else
                c = bit.rshift(c, 1)
            end
        end
        CRC32_TABLE[i] = c
    end
end
local function _CRC32(s)
    local crc = 0xFFFFFFFF
    for i = 1, #s do
        crc = bit.bxor(bit.rshift(crc, 8),
                        CRC32_TABLE[bit.band(bit.bxor(crc, string.byte(s, i)), 0xFF)])
    end
    return bit.bxor(crc, 0xFFFFFFFF) % 4294967296
end

-- Builds binary payload from current LFG state. entry may be nil (no listing).
-- applicantIDs is array from C_LFGList.GetApplicants(). Returns string of bytes.
local function BuildPayload(entry, applicantIDs)
    local out = {}

    -- Header (length patched after we know body size)
    table.insert(out, "APS1")
    table.insert(out, string.char(0x03))    -- protocol version (v3: listing category/difficulty)
    table.insert(out, "\0\0")                -- length placeholder (uint16 BE)
    table.insert(out, "\0\0")                -- reserved

    -- Listing block
    local cleanEntry = SafeTable(entry)
    if cleanEntry then
        -- Midnight 12.0 returns activityIDs (table) on the primary listing —
        -- legacy entry.activityID is nil. Fall back to legacy field for
        -- forward-compat with future API renames.
        local activityIDs = SafeTable(cleanEntry.activityIDs)
        local activityID = SafeNumber(activityIDs and activityIDs[1], 0)
        if activityID <= 0 then
            activityID = SafeNumber(cleanEntry.activityID, 0)
        end
        activityID = math.floor(activityID)
        if activityID < 0 then activityID = 0 end

        local activityInfo = nil
        if activityID > 0 then
            activityInfo = SafeTable(C_LFGList.GetActivityInfoTable(activityID))
        end

        local dungeonName = "?"
        local categoryID = 0
        local difficultyID = 0
        if activityInfo then
            local shortName = SafeStr(activityInfo.shortName, "?")
            if shortName ~= "" and shortName ~= "?" then
                dungeonName = shortName
            else
                local fullName = SafeStr(activityInfo.fullName, "?")
                dungeonName = (fullName ~= "" and fullName) or "?"
            end
            categoryID = math.floor(SafeNumber(activityInfo.categoryID, 0))
            difficultyID = math.floor(SafeNumber(activityInfo.difficultyID, 0))
        end
        local isMythicPlus = (categoryID == 2)

        -- Strip player-link |Kxxx|k from listing name after SafeStr has
        -- handled secret-tagged strings and regular WoW escape sequences.
        local listingName = SafeStr(cleanEntry.name, "?"):gsub("|K[^|]*|k", "")
        local listingComment = SafeStr(cleanEntry.comment, "?")

        local keyLevel = 0
        if isMythicPlus then
            keyLevel = _GetListingKeystoneLevel(activityID, listingName, listingComment)
        end

        table.insert(out, string.char(1))
        table.insert(out, _Uint32BE(activityID))
        table.insert(out, _Uint16BE(categoryID))
        table.insert(out, _Uint16BE(difficultyID))
        table.insert(out, string.char(math.min(keyLevel, 255)))
        _PackLenStr(out, dungeonName)
        _PackLenStr(out, listingName)
        _PackLenStr(out, listingComment)
    else
        table.insert(out, string.char(0))
    end

    -- Version block — emitted in EVERY snapshot. Companion mid-session launch
    -- (user opens companion AFTER hosting LFG) misses session start; without
    -- VERSION in every shot, companion never learns realm/region and all
    -- same-realm applicants get empty realm → derive_server_slug("") → WCL
    -- "Server not found" silently for the rest of the session. Cost is
    -- ~30-60 bytes per shot (addon+game version strings + region byte + 12-char
    -- realm-qualified name) — negligible vs. QR Version 25-30 capacity.
    table.insert(out, string.char(1))
    _PackLenStr(out, ADDON_VERSION)
    local gameVer = (GetBuildInfo and select(1, GetBuildInfo())) or "?"
    _PackLenStr(out, gameVer)
    local regionID = math.floor(SafeNumber(GetCurrentRegion and GetCurrentRegion(), 0))
    if regionID < 0 then regionID = 0 elseif regionID > 255 then regionID = 0 end
    table.insert(out, string.char(regionID))
    local pname, prealm = UnitFullName("player")
    local playerName = SafeStr(pname, "?")
    if playerName == "" then playerName = "?" end
    local playerRealm = SafeStr(prealm, "")
    local fullName = playerName .. ((playerRealm ~= "") and ("-" .. playerRealm) or "")
    _PackLenStr(out, fullName)

    -- Applicants — filter out DEAD_STATUSES + sort by ID for hash stability
    local validApps = {}
    local cleanApplicantIDs = SafeTable(applicantIDs) or {}
    for _, rawID in ipairs(cleanApplicantIDs) do
        local id = math.floor(SafeNumber(rawID, 0))
        if id > 0 then
            local info = C_LFGList.GetApplicantInfo(id)
            info = SafeTable(info)
            if info then
                local status = SafeEnumKey(info.applicantStatus, "")
                local memberCount = math.floor(SafeNumber(info.numMembers, 0))
                if memberCount > 5 then memberCount = 5 end
                if memberCount > 0 and not APP_DEAD_STATUSES[status] then
                    table.insert(validApps, { id = id, members = memberCount })
                end
            end
        end
    end
    table.sort(validApps, function(a, b) return a.id < b.id end)

    -- Wire format v2: emit one block per group member (was: only the leader).
    -- Single-pass shadow-table approach — count is derived from successfully-
    -- emitted blocks, not from numMembers sum, so:
    --   (a) no count/emit race possible (header count cannot disagree with
    --       what was actually appended);
    --   (b) resilient to GetApplicantMemberInfo returning nil for transient
    --       member-load lag (rare; members 2+ may lag by ≤1 frame on first
    --       list-update). We just skip the block; next snapshot ≤0.5s later
    --       picks them up.
    -- Per-block byte layout (v2):
    --   uint32 applicant_id, u8 member_idx (1-based), u8 class_id,
    --   u16 spec_id, u16 ilvl, u16 score, u8 role, len-prefixed name.
    local memberOut = {}
    local emittedCount = 0
    for _, app in ipairs(validApps) do
        for m = 1, app.members do
            local name, class, _, _, ilvl, _, _, _, _, role, _, score, _, _, _, specID
                = C_LFGList.GetApplicantMemberInfo(app.id, m)
            local memberName = SafeStr(name, "?")
            if memberName ~= "" then
                local classToken = SafeEnumKey(class, "")
                local roleToken = SafeEnumKey(role, "DAMAGER")
                table.insert(memberOut, _Uint32BE(app.id))
                table.insert(memberOut, string.char(m))
                table.insert(memberOut, string.char(CLASS_NAME_TO_ID[classToken] or 0))
                table.insert(memberOut, _Uint16BE(SafeNumber(specID, 0)))
                table.insert(memberOut, _Uint16BE(SafeRoundedNumber(ilvl, 0)))
                table.insert(memberOut, _Uint16BE(SafeRoundedNumber(score, 0)))
                table.insert(memberOut, string.char(ROLE_NAME_TO_BYTE[roleToken] or 2))
                _PackLenStr(memberOut, memberName)
                emittedCount = emittedCount + 1
            end
        end
    end

    table.insert(out, _Uint16BE(emittedCount))
    for _, chunk in ipairs(memberOut) do
        table.insert(out, chunk)
    end

    -- Concat, patch length field, append CRC32
    local body = table.concat(out)
    local total_len = #body + 4  -- include CRC32 trailer
    body = body:sub(1, 5) .. _Uint16BE(total_len) .. body:sub(8)
    return body .. _Uint32BE(_CRC32(body))
end

-- djb2-style hash for change detection. Collision rate ~1/4B per shot.
local function HashSnapshot(payload)
    local h = 5381
    for i = 1, #payload do
        h = ((h * 33) + string.byte(payload, i)) % 4294967296
    end
    return h
end

-- Resolve QR encoder reference (set by libs/qrencode.lua via addon namespace).
-- WoW's addon loader unconditionally passes (addonName, ns) varargs to every
-- Lua file in an addon, so the namespace is always populated.
local _, _addonNS = ...
local _qrencode = _addonNS.QR.qrcode

-- Acquire (or reuse from pool) a black-rectangle texture and position+size it.
-- Returns the texture or nil if pool exhausted (caller logs warning).
-- Pool grows as needed; never shrinks. Excess textures from prior larger QRs
-- are hidden, not destroyed (cheap reuse on next render).
local QR_TEXTURE_HARD_CAP = 5000  -- safety against runaway texture creation
local function _AcquireQRTexture(x, y, w, h)
    qrTextureUsed = qrTextureUsed + 1
    local t = qrTexturePool[qrTextureUsed]
    if not t then
        if qrTextureUsed > QR_TEXTURE_HARD_CAP then
            qrTextureUsed = qrTextureUsed - 1  -- roll back; don't track unused
            return nil
        end
        t = qrFrame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 1)
        qrTexturePool[qrTextureUsed] = t
    end
    t:ClearAllPoints()
    t:SetSize(w, h)
    t:SetPoint("TOPLEFT", qrFrame, "TOPLEFT", x, -y)
    t:Show()
    return t
end

-- Paint a QR matrix (Lua table of tables, value > 0 = black, < 0 = white) into
-- the frame using row-based run-length encoding. For each row we walk left→right
-- and merge consecutive black modules into a single horizontal rectangle texture.
-- Typical QR has ~10-15 runs per row → ~10-15 textures × N rows; far below the
-- one-texture-per-module count which would crash WoW's renderer.
--
-- Returns true on success, false on overflow (texture pool exhausted — payload
-- needs a smaller QR version OR pool cap raised).
local function PaintQR(matrix)
    local rows = #matrix
    local cols = #matrix[1]
    local total_modules = rows + 2 * QR_QUIET_ZONE   -- assume square QR
    local frame_px = total_modules * QR_MODULE_PX

    qrFrame:SetSize(frame_px, frame_px)
    qrCurrentSize = frame_px
    _ApplyQRFramePosition()

    -- Reset texture usage counter — texture references in qrTexturePool stay,
    -- they just get :Show() or :Hide() per frame.
    local prev_used = qrTextureUsed
    qrTextureUsed = 0

    local quiet_offset = QR_QUIET_ZONE * QR_MODULE_PX
    -- Overflow tracking: _AcquireQRTexture returns nil when its hard cap is hit
    -- AND we'd need to create a new texture (existing pool entries reusable past
    -- the cap aren't blocked). We observe the return so we can warn at end + tell
    -- caller this QR couldn't be fully rendered.
    local overflow = false

    for y = 1, rows do
        local row = matrix[y]
        local x_start = nil  -- start col of current black run, nil = no run
        for x = 1, cols do
            local is_black = (row[x] or 0) > 0
            if is_black then
                if x_start == nil then x_start = x end
            elseif x_start ~= nil then
                -- run ended at column x; render run [x_start .. x-1]
                local run_len = x - x_start
                local px_x = quiet_offset + (x_start - 1) * QR_MODULE_PX
                local px_y = quiet_offset + (y - 1) * QR_MODULE_PX
                if not _AcquireQRTexture(px_x, px_y, run_len * QR_MODULE_PX, QR_MODULE_PX) then
                    overflow = true
                end
                x_start = nil
            end
        end
        -- Trailing run (extends to row end)
        if x_start ~= nil then
            local run_len = cols - x_start + 1
            local px_x = quiet_offset + (x_start - 1) * QR_MODULE_PX
            local px_y = quiet_offset + (y - 1) * QR_MODULE_PX
            if not _AcquireQRTexture(px_x, px_y, run_len * QR_MODULE_PX, QR_MODULE_PX) then
                overflow = true
            end
        end
    end

    -- Hide leftover textures from previous (larger) QRs — they remain in pool
    -- for reuse on next render.
    for i = qrTextureUsed + 1, prev_used do
        local t = qrTexturePool[i]
        if t then t:Hide() end
    end

    if overflow then
        if APSPrint then
            APSPrint("WARN: QR texture pool exhausted at hard cap " ..
                     QR_TEXTURE_HARD_CAP .. " — rendered QR is INCOMPLETE; companion will fail to decode")
        end
        return false  -- caller treats as render failure (skip Screenshot, retry on next data change)
    end

    return true
end

-- Hex-encode bytes as uppercase ASCII. WHY: legacy companions only know the
-- original text-QR path (`bytes.fromhex(text)` on the Python side), and hex
-- also keeps small/medium payloads in QR alphanumeric mode which is denser than
-- raw byte mode. We therefore keep hex as the preferred transport for payloads
-- that already fit, and reserve raw bytes as the overflow escape hatch.
local function _HexEncode(data)
    local out = {}
    for i = 1, #data do
        out[i] = string.format("%02X", string.byte(data, i))
    end
    return table.concat(out)
end

local function _QREncodeModeLabel(kind, ec_level)
    local ec = (ec_level == 1 and "l")
            or (ec_level == 2 and "m")
            or ("ec" .. tostring(ec_level))
    return kind .. "-" .. ec
end

local function _SetLastQREncodeDiag(mode, payload_bytes, err)
    lastQREncodeMode = mode
    lastQREncodeBytes = payload_bytes or 0
    lastQREncodeError = err
end

-- Builds QR matrix from payload bytes via embedded lua-qrcode library. The
-- transport ladder intentionally prefers the historical hex path first so
-- already-working payloads keep backward compatibility with legacy companions.
-- Raw bytes are only used when hex overflows, because that's the case that is
-- already broken today (stale overlay until applicant count drops).
-- WHY pcall: qrencode.lua's get_version_eclevel uses assert() (real Lua error)
-- on capacity overflow at line 214, NOT the documented (false, errmsg) tuple
-- return. Plain `local ok, result = _qrencode(...)` lets that error propagate
-- through scan-tick and floods BugSack with hundreds of identical errors per
-- minute on big payloads. pcall traps it; we then fall back to lower EC
-- (M=2 → L=1, ~26% more capacity at Version 40) for one more attempt.
local function _TryQrEncode(data, ec_level)
    local pcall_ok, ok, result = pcall(_qrencode, data, ec_level)
    if not pcall_ok then return nil, tostring(ok) end          -- assert blew up
    if not ok then return nil, tostring(result) end            -- documented failure
    return result, nil
end

local function BuildQRMatrix(payload)
    if not _qrencode then
        _SetLastQREncodeDiag("missing-lib", #payload, "QR library not loaded")
        if APSPrint then
            APSPrint("CRITICAL: QR library not loaded — check libs/qrencode.lua")
        end
        return nil
    end
    local hex = _HexEncode(payload)
    local attempts = {
        { kind = "hex", data = hex, ec_level = QR_EC_LEVEL, size = #hex, unit = "hex" },
    }
    if QR_EC_LEVEL ~= 1 then
        table.insert(attempts, { kind = "hex", data = hex, ec_level = 1, size = #hex, unit = "hex" })
    end
    table.insert(attempts, { kind = "raw", data = payload, ec_level = QR_EC_LEVEL, size = #payload, unit = "bytes" })
    if QR_EC_LEVEL ~= 1 then
        table.insert(attempts, { kind = "raw", data = payload, ec_level = 1, size = #payload, unit = "bytes" })
    end

    local first_label = nil
    local first_size = 0
    local first_unit = nil
    local failure_parts = {}
    for _, attempt in ipairs(attempts) do
        local label = _QREncodeModeLabel(attempt.kind, attempt.ec_level)
        if not first_label then
            first_label = label
            first_size = attempt.size
            first_unit = attempt.unit
        end
        local matrix, err = _TryQrEncode(attempt.data, attempt.ec_level)
        if matrix then
            _SetLastQREncodeDiag(label, #payload, nil)
            if APSPrint and ApplicantScoutDB and ApplicantScoutDB.debug and label ~= first_label then
                APSPrint(string.format(
                    "[APS-debug] QR fallback %s (%d %s) -> %s (%d bytes payload)",
                    first_label, first_size, first_unit, label, #payload))
            end
            return matrix
        end
        failure_parts[#failure_parts + 1] = label .. ": " .. tostring(err)
    end

    -- All strategies failed. Caller (MaybeTriggerScreenshot) gets nil → skips
    -- paint + screenshot for this snapshot. Next scan will rebuild a (hopefully
    -- smaller) payload and retry. Logged once per failure (not per scan-tick —
    -- caller dedupes via lastSnapshotHash unless force=true).
    local err = table.concat(failure_parts, " | ")
    _SetLastQREncodeDiag("failed", #payload, err)
    if APSPrint then
        APSPrint("QR encode failed (payload too large): "
                 .. tostring(err) .. " — payload=" .. #payload .. " bytes")
    end
    return nil
end

-- State for trigger throttling + dedup
-- (forward-declared at top — no `local` here. Without forward-decl, StartSession's
-- bare assignments would silently target globals instead of resetting these locals.)
lastSnapshotHash = nil
lastShotTime = 0
pendingShotDirty = false
lastQREncodeMode = "never"
lastQREncodeBytes = 0
lastQREncodeError = nil
local SHOT_THROTTLE_S = 0.5

-- Build payload, dedup vs last hash, throttle, paint QR, trigger Screenshot.
-- force=true bypasses dedup AND throttle (used by EndSession + /apscout shotnow).
-- entryHint: optional pre-fetched C_LFGList.GetActiveEntryInfo() result from
-- the scan-tick caller — avoids a second API call per scan. nil falls back
-- to fetching here (force-shot from EndSession / /apscout shotnow).
-- Frame is always-visible during active session, so no Show/Hide cycle around
-- Screenshot — eliminates the prior render-pipeline race at non-integer DPI.
MaybeTriggerScreenshot = function(force, entryHint)
    -- "Can't fire" early-returns clear pendingShotDirty so the scan-ticker drain
    -- (line further below) doesn't spin endlessly calling us back when conditions
    -- haven't changed. Throttle path (further down) is the ONLY legitimate reason
    -- to set pendingShotDirty=true.
    if not (ApplicantScoutDB and ApplicantScoutDB.enabled) and not force then
        pendingShotDirty = false
        return
    end
    if not qrFrameCreated then
        pendingShotDirty = false
        return
    end

    -- Early exit when not hosting LFG: no entry to encode, payload would be a
    -- no-op snapshot. EndSession() uses force=true to dispatch one final clear-
    -- snapshot for companion state cleanup. Outside that, idle BuildPayload
    -- spam wastes CPU on every GROUP_ROSTER_UPDATE.
    if not isSessionActive and not force then
        pendingShotDirty = false
        return
    end

    -- Render-pipeline grace right after StartSession: see suppressShotsUntil
    -- assignment in StartSession for the rationale (newly Show()'d frame
    -- needs ≥1 render pass before painted QR textures are committed to
    -- the framebuffer that Screenshot() captures). Set pendingShotDirty so
    -- the scan-tick drain retries on subsequent ticks once the window
    -- expires; force-shot path (EndSession final clear) bypasses.
    if not force and suppressShotsUntil and GetTime() < suppressShotsUntil then
        pendingShotDirty = true
        return
    end

    local entry = nil
    if isSessionActive then
        -- Reuse caller's pre-fetched entry when available (scan-tick path);
        -- fall back to direct fetch for force-shot paths (EndSession, slash).
        entry = SafeTable(entryHint)
        if not entry then
            entry = SafeTable(C_LFGList.GetActiveEntryInfo())
        end
    end
    local applicantIDs = {}
    if entry then
        applicantIDs = SafeTable(C_LFGList.GetApplicants()) or {}
    end

    local payload = BuildPayload(entry, applicantIDs)

    local h = HashSnapshot(payload)
    if not force and h == lastSnapshotHash then
        pendingShotDirty = false  -- nothing new to render for same hash
        return
    end

    local now = GetTime()
    if not force and now - lastShotTime < SHOT_THROTTLE_S then
        pendingShotDirty = true
        return
    end

    -- Encode payload as QR matrix, render via row-RLE.
    local matrix = BuildQRMatrix(payload)
    if not matrix then
        -- Stamp the failed hash so identical-payload re-scans don't re-spam the
        -- BuildQRMatrix error. Real data change → fresh hash → retry path opens.
        -- WHY not stamping lastShotTime: we WANT next non-failing snapshot to
        -- fire immediately when data changes, not wait out throttle.
        lastSnapshotHash = h
        pendingShotDirty = false
        return
    end
    if not PaintQR(matrix) then
        -- Same retry-suppression rationale as above.
        lastSnapshotHash = h
        pendingShotDirty = false
        return
    end

    lastSnapshotHash = h
    lastShotTime = now
    pendingShotDirty = false

    -- Frame is already Show()'d at alpha=1 (StartSession kept it visible for
    -- the entire session). PaintQR above just updated the textures; defer
    -- Screenshot one frame so the new texture set commits to GPU framebuffer
    -- before capture (PaintQR's SetSize + ClearAllPoints + Show stack on
    -- pooled textures takes effect on the next render pass, not the current
    -- one). No alpha dance — that empirically races Screenshot() and
    -- captures alpha=0 → no APS1 marker on JPG.
    C_Timer.After(0, function()
        if ApplicantScoutDB and ApplicantScoutDB.debug then
            print(string.format("|cff999999[APS-debug]|r CAP qr_size=%dpx hash=%x t=%.2f",
                  qrCurrentSize, h, GetTime()))
        end
        Screenshot()
    end)

    if ApplicantScoutDB and ApplicantScoutDB.debug then
        print(string.format("|cff999999[APS-debug]|r SHOT bytes=%d apps=%d hash=%x",
              #payload, #applicantIDs, h))
    end
end

-- ───────────────────────────────────────────────────────────
-- LFG entry creation: default Mythic+ playstyle to Competitive
--
-- WARNING: this intentionally keeps addon-owned state out of Blizzard frame
-- fields. The only Blizzard field we mutate is the actual form value the user
-- asked us to prefill, and live `/reload` + test-listing taint verification is
-- still required before release.
-- WHY this writes only Blizzard's entry-creation form state: C_LFGList
-- CreateListing/UpdateListing and title helpers are restricted /
-- AllowedWhenUntainted in 12.x. We prefill `generalPlaystyle` before the user
-- clicks List Group, then let Blizzard's own hardware-event path submit it.
-- Do not replace Blizzard functions or call CreateListing/UpdateListing here.

_MaybeAutoSelectCompetitive = function(panel, reason)
    if not (ApplicantScoutDB and ApplicantScoutDB.enabled
            and ApplicantScoutDB.autoCompetitivePlaystyle) then
        return false
    end

    local enum = _G.Enum
    local generalPlaystyleEnum = enum and enum.LFGEntryGeneralPlaystyle
    local competitive = generalPlaystyleEnum and generalPlaystyleEnum.FunSerious
    if competitive == nil then return false end

    if not panel or lfgAutoCompetitiveTouchedPanels[panel] then return false end

    local isEditMode = _G.LFGListEntryCreation_IsEditMode
    if type(isEditMode) ~= "function" or isEditMode(panel) then return false end

    local activityID = panel.selectedActivity
    if activityID == nil or IsSecretValue(activityID) then return false end
    if not (C_LFGList and C_LFGList.GetActivityInfoTable) then return false end

    local activityInfo = SafeTable(C_LFGList.GetActivityInfoTable(activityID))
    if not activityInfo then return false end
    if IsSecretValue(activityInfo.isMythicPlusActivity)
       or activityInfo.isMythicPlusActivity ~= true then
        return false
    end

    local currentPlaystyle = panel.generalPlaystyle
    if IsSecretValue(currentPlaystyle) then return false end
    if currentPlaystyle == competitive then return true end

    lfgAutoCompetitiveApplying = true
    local ok, err = pcall(function()
        panel.generalPlaystyle = competitive

        local updateValidState = _G.LFGListEntryCreation_UpdateValidState
        if type(updateValidState) == "function" then
            updateValidState(panel)
        end

        local dropdown = panel.PlayStyleDropdown
        if dropdown and type(dropdown.GenerateMenu) == "function" then
            dropdown:GenerateMenu()
        end
    end)
    lfgAutoCompetitiveApplying = false
    if not ok then
        if ApplicantScoutDB.debug then
            print("|cff999999[APS-debug]|r LFG auto-competitive failed: "
                  .. tostring(err))
        end
        return false
    end

    if ApplicantScoutDB.debug then
        print("|cff999999[APS-debug]|r LFG auto-competitive applied"
              .. (reason and (" (" .. reason .. ")") or ""))
    end
    return true
end

_SetupLFGAutoCompetitive = function()
    if lfgAutoCompetitiveHooksSetup or lfgAutoCompetitiveHookError then
        return lfgAutoCompetitiveHooksSetup
    end

    local hook = _G.hooksecurefunc
    local selectFn = _G.LFGListEntryCreation_Select
    local showFn = _G.LFGListEntryCreation_Show
    local setEditModeFn = _G.LFGListEntryCreation_SetEditMode
    local selectPlaystyleFn = _G.LFGListEntryCreation_OnPlayStyleSelectedInternal
    if type(hook) ~= "function"
       or type(selectFn) ~= "function"
       or type(showFn) ~= "function"
       or type(setEditModeFn) ~= "function"
       or type(selectPlaystyleFn) ~= "function" then
        return false
    end

    local ok, err = pcall(function()
        hook("LFGListEntryCreation_Select", function(panel)
            _MaybeAutoSelectCompetitive(panel, "select")
        end)
        hook("LFGListEntryCreation_Show", function(panel)
            if panel then lfgAutoCompetitiveTouchedPanels[panel] = nil end
            _MaybeAutoSelectCompetitive(panel, "show")
        end)
        hook("LFGListEntryCreation_SetEditMode", function(panel, editMode)
            if not editMode then
                _MaybeAutoSelectCompetitive(panel, "create-mode")
            end
        end)
        hook("LFGListEntryCreation_OnPlayStyleSelectedInternal", function(panel)
            if panel and not lfgAutoCompetitiveApplying then
                lfgAutoCompetitiveTouchedPanels[panel] = true
            end
        end)
    end)

    if not ok then
        lfgAutoCompetitiveHookError = tostring(err)
        if ApplicantScoutDB and ApplicantScoutDB.debug then
            print("|cff999999[APS-debug]|r LFG auto-competitive hook failed: "
                  .. lfgAutoCompetitiveHookError)
        end
        return false
    end

    lfgAutoCompetitiveHooksSetup = true
    local frame = _G.LFGListFrame
    if frame and frame.EntryCreation then
        _MaybeAutoSelectCompetitive(frame.EntryCreation, "setup")
    end
    return true
end

local EVENT_HANDLERS = {
    PLAYER_LOGIN                     = function()
        InitDB()
        MarkDirty("login")
        _AttachSettingsPanel()
        _SetupPVEFrameMovement()  -- no-ops if BlizzMove loaded OR PVEFrame missing
        _SetupLFGAutoCompetitive() -- no-ops until Blizzard LFG globals exist
        _TryHookInfoPanels()      -- initial scan; ADDON_LOADED catches LoD frames later
    end,
    PLAYER_ENTERING_WORLD            = function()
        CreateQRFrame()
        if ApplicantScoutDB and ApplicantScoutDB.enabled then
            EnsureScreenshotCVars()
        else
            RestoreScreenshotCVarsWhenSafe(0)
        end
        MarkDirty("pew")
    end,
    -- WHY register ADDON_LOADED globally: many info-panel frames live in
    -- LoD addons (Blizzard_AchievementUI, Blizzard_EncounterJournal, etc.).
    -- They don't exist at PLAYER_LOGIN. Re-scan on every ADDON_LOADED catches
    -- each as its addon loads. Cost: ~10-15 fires per session × 12-frame
    -- iteration = microseconds.
    ADDON_LOADED                     = function()
        _SetupLFGAutoCompetitive()
        _TryHookInfoPanels()
    end,
    -- WHY persist on logout (Phase 2): PLAYER_LOGOUT fires after UI teardown
    -- begins but BEFORE SavedVariables flush. Drag-stop covers obvious paths;
    -- this catches positions changed via slash macros / scripted moves /
    -- third-party UI that bypasses our drag handlers.
    PLAYER_LOGOUT                    = function()
        if PVEFrame and PVEFrame:IsUserPlaced() and ApplicantScoutDB then
            local point, _, _, x, y = PVEFrame:GetPoint()
            if point then
                ApplicantScoutDB.pveFramePosition = { point = point, x = x, y = y }
            end
        end
    end,
    LFG_LIST_APPLICANT_LIST_UPDATED  = function() MarkDirty("listupd") end,
    LFG_LIST_APPLICANT_UPDATED       = function() MarkDirty("appupd") end,
    LFG_LIST_ACTIVE_ENTRY_UPDATE     = function() MarkDirty("entryupd") end,
    PARTY_LEADER_CHANGED             = function() MarkDirty("ldrchg") end,
    GROUP_ROSTER_UPDATE              = function() MarkDirty("roster") end,
    GROUP_LEFT                       = function() MarkDirty("groupleft") end,
}

-- Bind every interaction event to _OnInteractionEvent. Loop populates the
-- table directly so the registration loop below picks them up automatically.
-- Each handler closure captures the event name in its own loop-local — Lua
-- 5.1+ for-in semantics give per-iteration distinct bindings, so closures
-- don't share a single mutable upvalue.
for evt in pairs(INTERACTION_EVENT_DESIRED) do
    EVENT_HANDLERS[evt] = function() _OnInteractionEvent(evt) end
end

local frame = CreateFrame("Frame")
for event in pairs(EVENT_HANDLERS) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, ...)
    local h = EVENT_HANDLERS[event]
    if h then h(event, ...) end
end)

-- Scan ticker. Events flip scanDirty (boolean — primitives can't propagate
-- taint from a tainted writer to a clean reader); we drain the flag here from
-- the native NewTicker scheduler's clean call frame. CheckSessionTransition
-- handles StartSession/EndSession lifecycle; MaybeTriggerScreenshot does the
-- rest (read C_LFGList, build payload, paint QR, trigger Screenshot()).
-- Lockdown short-circuit: skip scheduler-driven C_LFGList reads during
-- ChatMessagingLockdown. BuildPayload still has field-level guards for force
-- paths and future callers, but scheduled snapshots should wait for clean data.
C_Timer.NewTicker(0.25, function()
    if not (scanDirty and ApplicantScoutDB and ApplicantScoutDB.enabled) then
        -- Drain pending throttled shot: data was changed during throttle
        -- window (pendingShotDirty=true), but no new events fired since.
        -- Without this drain: shot never goes out for sustained state.
        if pendingShotDirty and (GetTime() - lastShotTime) >= SHOT_THROTTLE_S then
            if not IsChatMessagingLockdown() then
                MaybeTriggerScreenshot()
            end
        end
        return
    end
    -- Defensive lockdown gate: keep scanDirty=true so the whole pass retries
    -- once Blizzard clears SecretInChatMessagingLockdown.
    if IsChatMessagingLockdown() then
        return  -- scanDirty stays true; processed once lockdown clears
    end
    scanDirty = false
    -- CheckSessionTransition starts/ends session as needed AND returns the
    -- live entry; pass it to MaybeTriggerScreenshot so we don't re-call
    -- C_LFGList.GetActiveEntryInfo a second time in the same tick.
    local entry = CheckSessionTransition()
    MaybeTriggerScreenshot(false, entry)
end)


-- ───────────────────────────────────────────────────────────
-- Settings panel: pinned above PVEFrame (LFG window) with Blizzard tooltip-style
-- chrome. Same backdrop/border textures as GameTooltip (and RaiderIO, Details,
-- BigWigs popups) so the panel reads as a native WoW UI element next to PVEFrame
-- instead of a foreign-styled box. Brand-green title only ("Applicant" in
-- #00ff7f, "Scout" in white); "×" close glyph at top-right.
--
-- Parent=PVEFrame so visibility cascades automatically: open LFG → panel
-- appears, close LFG → panel hides. Anchor BOTTOMLEFT-of-self to TOPLEFT-of-
-- PVEFrame with a small visible gap — right-side anchoring (BOTTOMRIGHT to
-- TOPRIGHT) lands inside PVEFrame's nine-slice chrome and renders nothing
-- visible, so the panel hangs above PVEFrame's left edge instead.
--
-- DIALOG strata (explicit) keeps the panel above HUD elements; Blizzard popups
-- (StaticPopup, ColorPicker — both toplevel=true) auto-lift above it. We do
-- NOT call SetToplevel(true) — it re-raises on every click and would hide
-- UIDropDownMenu / ColorPickerFrame children of any future widgets.
--
-- Close-× path: custom button calls settingsFrame:Hide(). WoW's visibility
-- model treats explicit Hide() as sticky across the parent's hide/show cycle,
-- so subsequent PVEFrame:Show() will NOT bring the panel back automatically —
-- user reopens via /apscout config. No flag bookkeeping needed.

-- Tooltip pattern. SetScript override (not HookScript) is fine for simple
-- widgets like CheckButton whose default OnEnter is empty. For widgets with
-- native hover behavior (Buttons), caller switches to HookScript explicitly.
_SetWidgetTooltip = function(widget, title, body)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if body then
            GameTooltip:AddLine(body, 1, 1, 1, true)  -- white, wrap=true
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function _RunDisabledCleanup()
    local wasSessionActive = isSessionActive
    local restoreSessionGen = nil
    if wasSessionActive then
        EndSession()  -- final clear-shot for companion; restore CVars after it paints.
        restoreSessionGen = sessionGen
    end

    ApplicantScoutDB.enabled = false
    scanDirty = false
    pendingShotDirty = false

    -- Reset before EndSession's deferred Hide closure fires so it respects
    -- "off" semantics even when user had debug visibility/move mode enabled.
    qrAlwaysVisible = false
    qrMoveMode = false
    _RefreshQRMouse()

    -- If no session was active, EndSession didn't schedule deferred Hide; sync
    -- Hide here. Active-session case is handled by EndSession's deferred
    -- _RefreshQRVisibility after the final clear-shot frame.
    if qrFrame and not wasSessionActive then qrFrame:Hide() end

    RestoreScreenshotCVarsWhenSafe(
        wasSessionActive and QR_RENDER_SETTLE_S or 0,
        restoreSessionGen
    )
end

-- Single source of truth for the enabled toggle. All entry points (slash on/off,
-- slash toggle, GUI checkbox click) route here so teardown logic
-- (EndSession + guarded CVar restore + QR cleanup) lives in one place.
-- Idempotent: no-op transitions still re-sync UI and run safety cleanup because
-- stale CVar stashes can survive crashes/reloads.
_SetEnabled = function(flag)
    flag = not not flag  -- coerce 1/nil → strict bool so equality compare is sane
    if flag == ApplicantScoutDB.enabled then
        if enabledCheckbox then enabledCheckbox:SetChecked(flag) end
        if flag then
            EnsureScreenshotCVars()
        else
            _RunDisabledCleanup()
        end
        APSPrint(flag and "already enabled" or "already disabled")
        return
    end
    if flag then
        ApplicantScoutDB.enabled = true
        EnsureScreenshotCVars()
        scanDirty = true  -- next 0.25s tick recovers session if listing active
        APSPrint("enabled — will emit during LFG hosting")
    else
        _RunDisabledCleanup()
        APSPrint("disabled (kill switch — no scans, no emits)")
    end
    -- Sync GUI checkbox if attached. Slash refresh without waiting for OnShow.
    if enabledCheckbox then
        enabledCheckbox:SetChecked(flag)
    end
end

-- Apply ApplicantScoutDB.debug + sync GUI checkbox + emit feedback. Mirror of
-- _SetEnabled for the debug-logging toggle, simpler because debug has no
-- teardown chain — only gates whether MarkDirty + MaybeTriggerScreenshot
-- write [APS-debug] lines to chat.
_SetDebug = function(flag)
    flag = not not flag
    ApplicantScoutDB.debug = flag
    if debugCheckbox then debugCheckbox:SetChecked(flag) end
    APSPrint("debug " .. (flag and "ON — every scan/emit will print" or "OFF"))
end

_SetAutoCompetitivePlaystyle = function(flag)
    flag = not not flag
    ApplicantScoutDB.autoCompetitivePlaystyle = flag
    if autoCompetitiveCheckbox then autoCompetitiveCheckbox:SetChecked(flag) end
    if flag then
        _SetupLFGAutoCompetitive()
        local frame = _G.LFGListFrame
        if frame and frame.EntryCreation then
            _MaybeAutoSelectCompetitive(frame.EntryCreation, "toggle")
        end
    end
    APSPrint("auto-competitive M+ playstyle " .. (flag and "ON" or "OFF"))
end

-- Layout constants for the Blizzard-tooltip-style panel chrome.
local _SETTINGS_FRAME_WIDTH = 240
local _SETTINGS_TOP_PAD = 10        -- clearance under the rope-border top edge
local _SETTINGS_BOTTOM_PAD = 8      -- clearance above rope-border bottom edge
local _SETTINGS_LEFT_PAD = 14
local _SETTINGS_RIGHT_PAD = 12
local _SETTINGS_TITLE_HEIGHT = 16
local _SETTINGS_TITLE_GAP = 6       -- gap between title row and first widget
local _SETTINGS_DEFAULT_ROW_HEIGHT = 22
local _SETTINGS_ROW_GAP = 4         -- gap BETWEEN rows; not added after last row
-- Y offset of first widget row from the frame TOPLEFT.
local _SETTINGS_CONTENT_TOP_OFFSET = _SETTINGS_TOP_PAD
                                     + _SETTINGS_TITLE_HEIGHT
                                     + _SETTINGS_TITLE_GAP

-- Caller convention: widget already has parent=settingsFrame when created.
-- Helper does NOT call SetParent — explicit ownership, less magic.
-- Frame height = top offset + content (rows + interior gaps) + bottom pad.
-- We add ROW_GAP after each row in stackedHeight, then subtract it from the
-- frame size formula so the trailing gap below the last row stays visual zero.
_AddSettingsRow = function(widget, customHeight)
    local h = customHeight or _SETTINGS_DEFAULT_ROW_HEIGHT
    widget:SetPoint(
        "TOPLEFT",
        settingsFrame,
        "TOPLEFT",
        _SETTINGS_LEFT_PAD,
        -(_SETTINGS_CONTENT_TOP_OFFSET + stackedHeight)
    )
    stackedHeight = stackedHeight + h + _SETTINGS_ROW_GAP
    settingsFrame:SetSize(
        _SETTINGS_FRAME_WIDTH,
        _SETTINGS_CONTENT_TOP_OFFSET + (stackedHeight - _SETTINGS_ROW_GAP) + _SETTINGS_BOTTOM_PAD
    )
end

-- Lazily creates the settings panel as a child of PVEFrame, anchored above
-- the LFG title bar. Idempotent (one-shot via settingsFrameAttached flag).
-- Defensive ADDON_LOADED watcher fallback for the unlikely case PVEFrame is
-- loaded on demand (12.x retail compiles it in, but custom clients may differ).
_AttachSettingsPanel = function()
    if settingsFrameAttached then return end
    if not _G.PVEFrame then
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("ADDON_LOADED")
        watcher:SetScript("OnEvent", function(self)
            if _G.PVEFrame then
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
                _AttachSettingsPanel()
                -- Same lazy-init opportunity for movement setup. DRY: don't
                -- spawn a separate watcher.
                _SetupPVEFrameMovement()
            end
        end)
        return
    end

    settingsFrame = CreateFrame(
        "Frame",
        "ApplicantScoutSettingsFrame",
        PVEFrame,
        "BackdropTemplate"
    )
    settingsFrame:SetSize(_SETTINGS_FRAME_WIDTH, 88)  -- placeholder; _AddSettingsRow grows
    -- Anchor BOTTOMLEFT of panel to TOPLEFT of PVEFrame +6 px gap. WHY left
    -- side: BOTTOMRIGHT-to-TOPRIGHT placed the panel inside PVEFrame's nine-
    -- slice chrome / close-button hit zone and rendered nothing visible. Left-
    -- side placement is the known-good anchor — panel hangs cleanly above the
    -- PVEFrame title bar with no chrome interference.
    settingsFrame:SetPoint("BOTTOMLEFT", PVEFrame, "TOPLEFT", 0, 6)
    settingsFrame:SetClampedToScreen(true)
    settingsFrame:SetFrameStrata("DIALOG")

    -- Blizzard tooltip-style chrome: same backdrop+border textures as
    -- GameTooltip and most established WoW addon panels (RaiderIO, Details,
    -- BigWigs popups). Reads as a native WoW UI element next to PVEFrame
    -- instead of a foreign brand-coloured box.
    settingsFrame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 5, right = 5, top = 5, bottom = 5 },
        tile = true,
        tileSize = 16,
    })
    settingsFrame:SetBackdropColor(0.05, 0.07, 0.10, 0.95)        -- near-black, slightly translucent
    settingsFrame:SetBackdropBorderColor(1, 1, 1, 1)              -- tooltip-border texture supplies its own gold rope

    -- Title — branded "Applicant" in green, "Scout" in white. Sits in the top
    -- inset area; GameFontHighlight gives a pure-white reset after |r so
    -- "Scout" reads cleanly against the dark fill instead of GameFontNormal's
    -- yellowy default.
    local title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", _SETTINGS_LEFT_PAD, -_SETTINGS_TOP_PAD)
    title:SetText("|cff00ff7fApplicant|rScout")

    -- Modern checkbox styling: brighter label font + 6 px breathing gap.
    -- Defaults from UICheckButtonTemplate land the label at +1 px with
    -- GameFontNormal — close-set and slightly dim against the dark panel.
    local function _StyleCheckboxLabel(cb, text)
        local label = _G[cb:GetName() .. "Text"]
        label:SetText(text)
        label:SetFontObject("GameFontHighlight")
        label:ClearAllPoints()
        label:SetPoint("LEFT", cb, "RIGHT", 6, 1)
    end

    enabledCheckbox = CreateFrame(
        "CheckButton",
        "ApplicantScoutSettingsEnabledCheckbox",
        settingsFrame,
        "UICheckButtonTemplate"
    )
    _StyleCheckboxLabel(enabledCheckbox, "Enable applicant scouting")
    enabledCheckbox:SetScript("OnClick", function(self)
        _SetEnabled(not not self:GetChecked())
    end)
    enabledCheckbox:SetHitRectInsets(0, -180, 0, 0)
    _SetWidgetTooltip(
        enabledCheckbox,
        "Enable applicant scouting",
        "When on, ApplicantScout captures listing applicants and emits QR codes for the companion to decode. When off, no scans / no QR / no Screenshot() calls — addon stays loaded but idle."
    )
    _AddSettingsRow(enabledCheckbox)

    debugCheckbox = CreateFrame(
        "CheckButton",
        "ApplicantScoutSettingsDebugCheckbox",
        settingsFrame,
        "UICheckButtonTemplate"
    )
    _StyleCheckboxLabel(debugCheckbox, "Debug logging")
    debugCheckbox:SetScript("OnClick", function(self)
        _SetDebug(not not self:GetChecked())
    end)
    debugCheckbox:SetHitRectInsets(0, -180, 0, 0)
    _SetWidgetTooltip(
        debugCheckbox,
        "Debug logging",
        "Prints scan / capture / emit diagnostics to chat ([APS-debug] lines). Off by default — enable only for troubleshooting why an LFG listing isn't captured or to verify QR emit timing. No effect on overlay behavior."
    )
    _AddSettingsRow(debugCheckbox)

    autoCompetitiveCheckbox = CreateFrame(
        "CheckButton",
        "ApplicantScoutSettingsAutoCompetitiveCheckbox",
        settingsFrame,
        "UICheckButtonTemplate"
    )
    _StyleCheckboxLabel(autoCompetitiveCheckbox, "Auto-select Competitive for M+")
    autoCompetitiveCheckbox:SetScript("OnClick", function(self)
        _SetAutoCompetitivePlaystyle(not not self:GetChecked())
    end)
    autoCompetitiveCheckbox:SetHitRectInsets(0, -180, 0, 0)
    _SetWidgetTooltip(
        autoCompetitiveCheckbox,
        "Auto-select Competitive for M+",
        "When on, ApplicantScout defaults new Mythic+ group listings to Competitive in Blizzard's playstyle dropdown. Manual changes in the same form are left alone."
    )
    _AddSettingsRow(autoCompetitiveCheckbox)

    -- Re-sync checkboxes from DB on each show. Handles slash-toggle-while-
    -- panel-was-hidden case: open via /apscout config → checkboxes reflect DB truth.
    settingsFrame:HookScript("OnShow", function()
        enabledCheckbox:SetChecked(ApplicantScoutDB.enabled)
        debugCheckbox:SetChecked(ApplicantScoutDB.debug)
        autoCompetitiveCheckbox:SetChecked(ApplicantScoutDB.autoCompetitivePlaystyle)
    end)

    enabledCheckbox:SetChecked(ApplicantScoutDB.enabled)
    debugCheckbox:SetChecked(ApplicantScoutDB.debug)
    autoCompetitiveCheckbox:SetChecked(ApplicantScoutDB.autoCompetitivePlaystyle)

    settingsFrameAttached = true  -- LAST: any earlier failure leaves false → retry next PLAYER_LOGIN
end


-- ───────────────────────────────────────────────────────────
-- slash commands

local function PrintHelp()
    print("|cff00ff7fApplicantScout v" .. ADDON_VERSION .. "|r (QR transport)")
    print("  /apscout on | off       enable/disable capture")
    print("  /apscout toggle         flip enabled state")
    print("  /apscout config         open/close settings panel")
    print("  /apscout status         show current state + QR diagnostics")
    print("  /apscout reset          clear dedup cache, force fresh full snapshot")
    print("  /apscout shotnow        force snapshot now (debug / manual sync)")
    print("  /apscout qrvisible      toggle QR frame always-visible (debug aid)")
    print("  /apscout qrmove         toggle QR move mode (Alt+drag QR frame)")
    print("  /apscout qrreset        reset QR frame position to top-left")
    print("  /apscout taintcheck     probe C_LFGList field secret-tagging")
    print("  /apscout debug [on|off] toggle debug logging")
    print("  /apscout competitive [on|off] auto-select Competitive for M+ listings")
end

SLASH_APSCOUT1 = "/apscout"
SlashCmdList.APSCOUT = function(msg)
    InitDB()
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "on" then
        _SetEnabled(true)
    elseif msg == "off" then
        _SetEnabled(false)
    elseif msg == "toggle" then
        _SetEnabled(not ApplicantScoutDB.enabled)
    elseif msg == "competitive" or msg == "competitive on" then
        _SetAutoCompetitivePlaystyle(true)
    elseif msg == "competitive off" or msg == "nocompetitive" then
        _SetAutoCompetitivePlaystyle(false)
    elseif msg == "config" or msg == "settings" then
        -- Toggle settings panel visibility. Lazy-attach if PLAYER_LOGIN race
        -- left settingsFrameAttached=false (PVEFrame still loading). Open via
        -- this slash overrides the close-X "stay hidden" sticky semantics.
        if not settingsFrameAttached then _AttachSettingsPanel() end
        if not settingsFrame then
            APSPrint("settings unavailable — PVEFrame not loaded; open LFG window once and retry")
        elseif settingsFrame:IsShown() then
            settingsFrame:Hide()
        else
            settingsFrame:Show()
        end
    elseif msg == "status" then
        print("|cff00ff7fApplicantScout|r status:")
        print("  enabled: " .. tostring(ApplicantScoutDB.enabled))
        print("  auto-competitive M+: " .. tostring(ApplicantScoutDB.autoCompetitivePlaystyle))
        print("  settings panel attached: " .. tostring(settingsFrameAttached))
        print("  session active: " .. tostring(isSessionActive))
        print("  session gen: " .. tostring(sessionGen))
        print("  scanDirty: " .. tostring(scanDirty))
        print("  shot suppressed: " .. (suppressShotsUntil and suppressShotsUntil > 0
              and (GetTime() < suppressShotsUntil
                   and string.format("yes (%.2fs left)", suppressShotsUntil - GetTime())
                   or "no (window expired)")
              or "no"))
        print("  ChatMessagingLockdown: " .. tostring(IsChatMessagingLockdown()))
        -- QR transport diagnostics
        print("|cff00ff7f---|r QR transport:")
        print("  QR library loaded: " .. tostring(_qrencode ~= nil))
        print("  QR frame created: " .. tostring(qrFrameCreated))
        if qrFrame then
            print("  QR frame visible: " .. tostring(qrFrame:IsShown()) ..
                  " (always-visible mode: " .. tostring(qrAlwaysVisible) ..
                  ", move mode: " .. tostring(qrMoveMode) .. ")")
            print("  QR frame size: " .. qrCurrentSize .. "×" .. qrCurrentSize .. " px")
            print("  QR frame position: " .. _CurrentQRPositionText())
            print("  QR mouse enabled: " .. tostring(qrMoveMode and true or false))
        end
        print("  texture pool: " .. #qrTexturePool .. " (used last paint: " .. qrTextureUsed .. ")")
        print("  last snapshot hash: " .. tostring(lastSnapshotHash))
        print("  last shot time: " .. (lastShotTime > 0
              and string.format("%.1fs ago", GetTime() - lastShotTime) or "never"))
        print("  pending throttled shot: " .. tostring(pendingShotDirty))
        print("  last QR encode: " .. tostring(lastQREncodeMode)
              .. " (" .. tostring(lastQREncodeBytes) .. " bytes)")
        print("  last QR error: " .. tostring(lastQREncodeError or "none"))
        print("  screenshotQuality: " .. tostring(GetCVar("screenshotQuality")))
        print("  screenshotFormat: " .. tostring(GetCVar("screenshotFormat")))
        print("  prior screenshotQuality stash: " ..
              tostring(ApplicantScoutDB.priorScreenshotQuality))
        print("  prior screenshotFormat stash: " ..
              tostring(ApplicantScoutDB.priorScreenshotFormat))
        -- raw API diagnostics
        print("|cff00ff7f---|r raw API:")
        print("  HasActiveEntryInfo: " .. tostring(C_LFGList.HasActiveEntryInfo()))
        local entry = SafeTable(C_LFGList.GetActiveEntryInfo())
        if entry then
            local activityIDs = SafeTable(entry.activityIDs)
            local cleanActivityID = math.floor(SafeNumber(activityIDs and activityIDs[1], 0))
            if cleanActivityID <= 0 then
                cleanActivityID = math.floor(SafeNumber(entry.activityID, 0))
            end
            print("  entry.activityIDs[1]: " .. SafeDiag(activityIDs and activityIDs[1]))
            print("  entry.activityID: " .. SafeDiag(entry.activityID))
            if cleanActivityID > 0 then
                local activityInfo = SafeTable(C_LFGList.GetActivityInfoTable(cleanActivityID))
                if activityInfo then
                    print("  activity.categoryID: " .. SafeDiag(activityInfo.categoryID))
                    print("  activity.difficultyID: " .. SafeDiag(activityInfo.difficultyID))
                end
                if C_LFGList.GetKeystoneForActivity then
                    print("  activity.keystoneLevel: "
                          .. SafeDiag(C_LFGList.GetKeystoneForActivity(cleanActivityID)))
                else
                    print("  activity.keystoneLevel: n/a")
                end
            end
            print("  entry.name: " .. SafeDiag(entry.name))
            print("  entry.comment: " .. SafeDiag(entry.comment))
            local statusListingName = SafeStr(entry.name, "?"):gsub("|K[^|]*|k", "")
            local statusListingComment = SafeStr(entry.comment, "?")
            print("  derived keyLevel: "
                  .. tostring(_GetListingKeystoneLevel(
                      cleanActivityID, statusListingName, statusListingComment)))
        else
            print("  entry: nil")
        end
        local applicants = SafeTable(C_LFGList.GetApplicants()) or {}
        print("  GetApplicants count: " .. #applicants)
        for i = 1, math.min(3, #applicants) do
            local rawID = applicants[i]
            local id = math.floor(SafeNumber(rawID, 0))
            local info = (id > 0) and SafeTable(C_LFGList.GetApplicantInfo(id)) or nil
            if info then
                print(string.format("    #%d id=%s status=%s numMembers=%s",
                      i, SafeDiag(rawID), SafeDiag(info.applicantStatus),
                      SafeDiag(info.numMembers)))
            else
                print(string.format("    #%d id=%s status=n/a numMembers=n/a",
                      i, SafeDiag(rawID)))
            end
        end
        -- Phase 1 + 2 diagnostics
        print("|cff00ff7f---|r visibility:")
        print("  QR suppressed by interaction: " .. tostring(_qrSuppressedByInteraction or false))
        local activeKinds = {}
        for kind, active in pairs(_interactionSlots) do
            if active then activeKinds[#activeKinds + 1] = kind end
        end
        print("  active interaction slots: " .. (#activeKinds > 0
              and table.concat(activeKinds, ", ") or "(none)"))
        local hookedCount = 0
        for _ in pairs(_hookedInfoPanels) do hookedCount = hookedCount + 1 end
        print("  info panels hooked: " .. hookedCount .. "/" .. #INFO_PANEL_FRAMES)
        print("|cff00ff7f---|r LFG window:")
        local hasBlizzMove = C_AddOns and C_AddOns.IsAddOnLoaded
                             and C_AddOns.IsAddOnLoaded("BlizzMove") or false
        print("  BlizzMove loaded: " .. tostring(hasBlizzMove))
        print("  movement setup: " .. tostring(PVEFrame
              and PVEFrame.apsMovementSetup or false))
        print("  auto-competitive hooks: " .. tostring(lfgAutoCompetitiveHooksSetup)
              .. (lfgAutoCompetitiveHookError
                  and (" (error: " .. lfgAutoCompetitiveHookError .. ")")
                  or ""))
        if ApplicantScoutDB.pveFramePosition then
            local pos = ApplicantScoutDB.pveFramePosition
            print(string.format("  saved position: %s @ (%.0f, %.0f)",
                  tostring(pos.point), pos.x or 0, pos.y or 0))
        else
            print("  saved position: (default)")
        end
    elseif msg == "taintcheck" then
        -- One-shot diagnostic. Slash-handler frame is hardware-event-rooted
        -- (clean). Reads C_LFGList directly + per-field issecretvalue dump.
        -- No emit, no queue interaction. Useful with active applicants (probe
        -- their fields) or empty listing (probe lockdown / version flags only).
        print("|cff00ff7fApplicantScout|r taintcheck:")
        print("  InChatMessagingLockdown: " .. tostring(IsChatMessagingLockdown()))
        local applicants = SafeTable(C_LFGList.GetApplicants()) or {}
        print("  applicants: " .. #applicants)
        for i = 1, math.min(3, #applicants) do
            local rawID = applicants[i]
            local id = math.floor(SafeNumber(rawID, 0))
            local info = (id > 0) and SafeTable(C_LFGList.GetApplicantInfo(id)) or nil
            local name, class, ilvl, role, score, specID
            if id > 0 then
                name, class, _, _, ilvl, _, _, _, _, role, _, score, _, _, _, specID
                    = C_LFGList.GetApplicantMemberInfo(id, 1)
            end
            print(string.format("  #%d id=%s (id_secret=%s) status=%s",
                  i, SafeDiag(rawID), tostring(IsSecretValue(rawID)),
                  info and SafeDiag(info.applicantStatus) or "n/a"))
            print(string.format("    name=%s(s=%s) class=%s(s=%s) specID=%s(s=%s)",
                  SafeDiag(name), tostring(IsSecretValue(name)),
                  SafeDiag(class), tostring(IsSecretValue(class)),
                  SafeDiag(specID), tostring(IsSecretValue(specID))))
            print(string.format("    ilvl=%s(s=%s) score=%s(s=%s) role=%s(s=%s)",
                  SafeDiag(ilvl), tostring(IsSecretValue(ilvl)),
                  SafeDiag(score), tostring(IsSecretValue(score)),
                  SafeDiag(role), tostring(IsSecretValue(role))))
        end
    elseif msg == "reset" then
        -- Force fresh full snapshot on next scan-tick. Clears dedup state so the
        -- next snapshot is bit-for-bit different from prior cached one → triggers
        -- a screenshot regardless of dedup. VERSION block re-emitted so companion
        -- re-syncs region for WCL.
        lastSnapshotHash = nil
        pendingShotDirty = false
        scanDirty = true
        APSPrint("resync queued — next scan-tick (≤0.25s) emits fresh full snapshot")
    elseif msg == "shotnow" then
        -- Force snapshot bypass dedup + throttle. Use this to verify QR pipeline
        -- end-to-end during dev: builds payload, encodes as QR, paints into frame,
        -- calls Screenshot(). Inspect the resulting JPG in any QR scanner — should
        -- decode to APS1 + length + listing/version/applicants + CRC32.
        MaybeTriggerScreenshot(true)
        APSPrint("forced snapshot — check Screenshots/ folder")
    elseif msg == "qrvisible" then
        -- Toggle debug-visible override. _RefreshQRVisibility resolves all four
        -- corners of the (qrAlwaysVisible × isSessionActive) cross-product
        -- correctly via the (sessionActive AND NOT suppressed) OR alwaysVisible
        -- formula — no nested if needed here. Bonus: qrAlwaysVisible=true now
        -- correctly un-suppresses an interaction-faded QR (debug intent: show
        -- regardless).
        qrAlwaysVisible = not qrAlwaysVisible
        _RefreshQRVisibility()
        APSPrint("QR frame always-visible: " .. tostring(qrAlwaysVisible))
    elseif msg == "qrmove" then
        -- Explicit move/debug mode. Normal visible QR intentionally has mouse
        -- disabled so it doesn't intercept HUD clicks while hosting.
        qrMoveMode = not qrMoveMode
        _RefreshQRMouse()
        _RefreshQRVisibility()
        APSPrint("QR move mode: " .. tostring(qrMoveMode) ..
                 (qrMoveMode and " — Alt+drag the QR frame to reposition" or ""))
    elseif msg == "qrreset" then
        _ResetQRFramePosition()
        APSPrint("QR position reset: " .. _CurrentQRPositionText())
    elseif msg == "debug" or msg == "debug on" then
        _SetDebug(true)
    elseif msg == "debug off" or msg == "nodebug" then
        _SetDebug(false)
    else
        PrintHelp()
    end
end
