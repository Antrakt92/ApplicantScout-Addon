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
-- WHY screenshot transport, not chatlog/SendChatMessage: WoW chatlog delivery
-- is buffered and unsuitable for real-time addon-to-companion transport in
-- Midnight 12.x. Screenshot() is unprotected in 12.x and produces a JPG within
-- ~0.5s synchronously, with no taint propagation, no chat anti-spam, no file
-- buffer.
--
-- WHY QR over custom pixel marker: Reed-Solomon ECC built in (15% recovery at
-- level M); industry-standard finder/alignment patterns survive any DPI scale,
-- rotation, partial occlusion. Custom marker had zero error correction and
-- broke on dark-terrain backgrounds + non-integer DPI scales.

local addonName = ...
local ADDON_VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version") or "?"

local AUTO_MPLUS_PLAYSTYLE_DISABLED = "disabled"
local AUTO_MPLUS_PLAYSTYLE_DEFAULT = "FunSerious"
local AUTO_MPLUS_PLAYSTYLE_OPTIONS = {
    { token = AUTO_MPLUS_PLAYSTYLE_DISABLED, fallback = "Off" },
    { token = "Learning", labelGlobal = "GROUP_FINDER_GENERAL_PLAYSTYLE1", fallback = "Learning" },
    { token = "FunRelaxed", labelGlobal = "GROUP_FINDER_GENERAL_PLAYSTYLE2", fallback = "Relaxed" },
    { token = "FunSerious", labelGlobal = "GROUP_FINDER_GENERAL_PLAYSTYLE3", fallback = "Competitive" },
    { token = "Expert", labelGlobal = "GROUP_FINDER_GENERAL_PLAYSTYLE4", fallback = "Carry Offered" },
}
local AUTO_MPLUS_PLAYSTYLE_ALIASES = {
    off = AUTO_MPLUS_PLAYSTYLE_DISABLED,
    disabled = AUTO_MPLUS_PLAYSTYLE_DISABLED,
    none = AUTO_MPLUS_PLAYSTYLE_DISABLED,
    learning = "Learning",
    relaxed = "FunRelaxed",
    funrelaxed = "FunRelaxed",
    competitive = "FunSerious",
    serious = "FunSerious",
    funserious = "FunSerious",
    carry = "Expert",
    expert = "Expert",
}

local DB_DEFAULTS = {
    enabled = true,
    debug = false,
    autoMPlusPlaystyle = AUTO_MPLUS_PLAYSTYLE_DEFAULT,
    -- Empty string disables auto greeting. User text is normalized on load and
    -- when edited; the addon never sends a default chat message silently.
    autoHiMessage = "",
    -- Opt-in extra greeting for replacements/new joins in 5-player parties.
    -- Raids are intentionally excluded to avoid noisy roster churn greetings.
    autoHiGreetNewPartyMembers = false,
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

-- Session lifecycle. INVARIANT: isSessionActive == true ⇔ the addon has a
-- transport-visible state to publish (active LFG listing OR real group roster).
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
-- textures. Large QR versions with high-entropy byte payloads can still reach
-- several thousand runs, so BuildQRMatrix rejects encode modes whose rendered
-- run count would exceed QR_TEXTURE_HARD_CAP and falls through to raw/lower-EC
-- alternatives instead of painting an incomplete QR.
--
-- WHY transient QR uses a settle lease, not alpha-flicker: Screenshot() in the
-- After(0) callback empirically fired before SetAlpha(1) reached the GPU
-- framebuffer on real-world WoW setups, capturing alpha=0 (= no QR on JPG, no
-- APS1 marker, companion logs "skip — no APS1 marker" forever). The QR is now
-- normally hidden, but a changed snapshot Show()s it, waits
-- QR_RENDER_SETTLE_S, captures, then releases the lease immediately after the
-- screenshot. This keeps the timing guard without leaving the QR over the UI
-- for the whole LFG-hosting duration.
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
      MarkDirty, MaybeTriggerScreenshot,
      -- Settings panel (pinned above PVEFrame). Forward-decl'd so slash handler
      -- + PLAYER_LOGIN handler can reference before bodies are defined.
      _SetEnabled, _SetDebug, _SetAutoMPlusPlaystyle, _AttachSettingsPanel,
      _SetWidgetTooltip, _SyncAutoMPlusPlaystyleDropdown,
      -- Visibility coordinator + interaction-frame tracking. Replaces direct
      -- qrFrame:Show/Hide calls so a single function decides visibility from
      -- three orthogonal axes: isSessionActive (auto), _qrSuppressedByInteraction
      -- (auto, see below), qrAlwaysVisible (manual debug override).
      _RefreshQRVisibility, _RefreshQRMouse, _RecomputeInteractionSuppression,
      _TryHookInfoPanels, _OnInteractionEvent, _IsQRVisibleForScreenshot,
      -- PVEFrame movement (Phase 2). Forward-decl'd so PLAYER_LOGIN handler
      -- and _AttachSettingsPanel's ADDON_LOADED watcher can both reference it
      -- before the body is defined further down.
      _SetupPVEFrameMovement,
      -- Group Finder creation helpers. Kept separate from QR/session state:
      -- this defaults Blizzard's own entry-creation form only.
      _SetupLFGEntryCreationKeyCapture, _SetupLFGDefaultPlaystyle,
      _MaybeAutoSelectDefaultPlaystyle
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
-- qrForceVisibleForShot is a transport-only visibility lease for force shots
-- such as EndSession's final clear while an interaction frame has hidden QR.
local lastSnapshotHash, lastShotTime, pendingShotDirty,
      qrAlwaysVisible, qrMoveMode, suppressShotsUntil,
      _qrSuppressedByInteraction, qrForceVisibleForShot,
      qrForceVisibleShotGen, lastQREncodeMode, lastQREncodeBytes,
      lastQREncodeError

-- Settings panel state. settingsFrame = parent of all widgets; created lazily
-- in _AttachSettingsPanel. settingsFrameAttached = one-shot init guard.
local settingsFrame, enabledCheckbox,
      autoMPlusPlaystyleLabel, autoMPlusPlaystyleDropdown,
      autoMPlusPlaystyleFallbackText
local settingsFrameAttached = false

local lfgDefaultPlaystyleHooksSetup = false
local lfgDefaultPlaystyleApplying = false
local lfgDefaultPlaystyleHookError = nil
local lfgDefaultPlaystyleTouchedPanels = setmetatable({}, { __mode = "k" })
local lfgEntryCreationKeyCaptureState = {
    hooksSetup = false,
    hookError = nil,
}
local lfgEntryCreationKeyCaptureHooked = setmetatable({}, { __mode = "k" })
local entryCreationKeyState = {
    END_SESSION_CLEAR_RETRY_DELAY_S = QR_RENDER_SETTLE_S * 2,
    DISABLE_CVAR_RESTORE_AFTER_CLEAR_DELAY_S = QR_RENDER_SETTLE_S * 3,
    entryCreationKeyLevelCache = nil,
    pendingEntryCreationKeyLevelCache = nil,
    activeListingCacheContext = nil,
    activeListingGeneration = 0,
    activeListingMaybeChanged = false,
    entryCreationKeyLevelCacheDecision = "none",
    lastPayloadApplicantCount = 0,
    lastPayloadRosterIncomplete = false,
    lastEmittedApplicantCount = 0,
    rosterChangedSinceLastPayload = false,
    ROSTER_CHANGE_PREFLIGHT_DEADLINE_S = 2.0,
    rosterChangePreflightDeadline = nil,
    rosterChangePreflightToken = 0,
    pendingTtl = 10,
    TRANSPORT_HEARTBEAT_S = 15.0,
    lastTransportHeartbeatAttemptTime = 0,
    LEADER_KEY_TTL_S = 60,
    LEADER_KEY_REQUEST_THROTTLE_S = 3,
    leaderKeystone = nil,
    leaderKeystoneLastRequestAt = 0,
    leaderKeystoneCallbackRegistered = false,
    leaderKeystoneLib = nil,
    leaderKeystoneCallbackOwner = {},
    libKeystonePrefixRegistered = false,
    libKeystoneShim = nil,
    libKeystoneShimCallbacks = {},
    -- WARNING: keep Auto Hi state on this existing table instead of adding
    -- top-level locals; this file is near Lua 5.1's 200-local chunk limit.
    AUTO_HI_DELAY_S = 5,
    AUTO_HI_NEW_PARTY_MEMBER_DELAY_S = 10,
    autoHiEditBoxSyncing = false,
    autoHiGroupStateKnown = false,
    autoHiWasInGroup = false,
    autoHiWasInSoloGroup = false,
    autoHiGroupGen = 0,
    autoHiKnownPartyGUIDs = {},
    autoHiKnownPartyMembersPrimed = false,
    autoHiNewPartyMemberGen = 0,
    rosterInspectIlvlByGUID = {},
}
local ENTRY_CREATION_KEY_CACHE_TTL = 3600

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
    s = s:gsub("|K[^|]*|k", "")            -- protected player link text
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

local function _NormalizeAutoMPlusPlaystyleToken(token)
    if IsSecretValue(token) or type(token) ~= "string" then
        return AUTO_MPLUS_PLAYSTYLE_DEFAULT
    end
    if token == AUTO_MPLUS_PLAYSTYLE_DISABLED then
        return token
    end
    for _, option in ipairs(AUTO_MPLUS_PLAYSTYLE_OPTIONS) do
        if token == option.token then
            return token
        end
    end
    return AUTO_MPLUS_PLAYSTYLE_DEFAULT
end

local function _NormalizeAutoMPlusPlaystyleCommand(token)
    if IsSecretValue(token) or type(token) ~= "string" then return nil end
    token = token:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if token == "" then return nil end
    return AUTO_MPLUS_PLAYSTYLE_ALIASES[token]
end

local function _GetAutoMPlusPlaystyleLabel(token)
    token = _NormalizeAutoMPlusPlaystyleToken(token)
    for _, option in ipairs(AUTO_MPLUS_PLAYSTYLE_OPTIONS) do
        if token == option.token then
            if option.labelGlobal and _G[option.labelGlobal] then
                return _G[option.labelGlobal]
            end
            return option.fallback
        end
    end
    return "Competitive"
end

local function _GetAutoMPlusPlaystyleStatusText()
    local token = _NormalizeAutoMPlusPlaystyleToken(
        ApplicantScoutDB and ApplicantScoutDB.autoMPlusPlaystyle)
    local label = _GetAutoMPlusPlaystyleLabel(token)
    if token == AUTO_MPLUS_PLAYSTYLE_DISABLED then
        return label
    end
    return label .. " (" .. token .. ")"
end

local function _GetConfiguredMPlusPlaystyleEnum()
    local token = _NormalizeAutoMPlusPlaystyleToken(
        ApplicantScoutDB and ApplicantScoutDB.autoMPlusPlaystyle)
    if token == AUTO_MPLUS_PLAYSTYLE_DISABLED then return nil, token end

    local enum = _G.Enum
    local generalPlaystyleEnum = enum and enum.LFGEntryGeneralPlaystyle
    local value = generalPlaystyleEnum and generalPlaystyleEnum[token]
    if value == nil or IsSecretValue(value) then return nil, token end
    return value, token
end

entryCreationKeyState.NormalizeAutoHiMessage = function(value)
    if type(value) ~= "string" then return "" end
    local text = value:gsub("[%c]", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

InitDB = function()
    if type(ApplicantScoutDB) ~= "table" then ApplicantScoutDB = {} end
    if ApplicantScoutDB.autoMPlusPlaystyle == nil
       and ApplicantScoutDB.autoCompetitivePlaystyle ~= nil then
        ApplicantScoutDB.autoMPlusPlaystyle =
            ApplicantScoutDB.autoCompetitivePlaystyle
            and AUTO_MPLUS_PLAYSTYLE_DEFAULT
            or AUTO_MPLUS_PLAYSTYLE_DISABLED
    end
    for k, v in pairs(DB_DEFAULTS) do
        if ApplicantScoutDB[k] == nil then ApplicantScoutDB[k] = v end
    end
    ApplicantScoutDB.autoMPlusPlaystyle =
        _NormalizeAutoMPlusPlaystyleToken(ApplicantScoutDB.autoMPlusPlaystyle)
    ApplicantScoutDB.autoHiMessage =
        entryCreationKeyState.NormalizeAutoHiMessage(ApplicantScoutDB.autoHiMessage)
    ApplicantScoutDB.autoCompetitivePlaystyle = nil
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
    entryCreationKeyState.lastEmittedApplicantCount = 0
    pendingShotDirty = false
    lastQREncodeMode = "never"
    lastQREncodeBytes = 0
    lastQREncodeError = nil
    entryCreationKeyState.lastQuietFullPartySignature = nil
    entryCreationKeyState.lastPayloadQuietFullPartySignature = nil
    entryCreationKeyState.MarkRosterCompositionChanged()
    entryCreationKeyState.ClearRosterInspectBatchState()
    entryCreationKeyState.ClearRosterLoadRetryState()
    entryCreationKeyState.RequestLeaderKeystone(true)

    -- QR is no longer shown for the entire session. The first changed snapshot
    -- will paint the QR, take a short visibility lease, wait QR_RENDER_SETTLE_S,
    -- capture, and hide it again. Manual debug/move modes still flow through
    -- the same visibility coordinator.
    suppressShotsUntil = 0
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

    -- Final force-shot: terminalClear makes BuildPayload emit has_listing=0,
    -- 0 applicants, and roster_count=0. Companion treats no-listing + roster
    -- as valid Party state, so teardown must explicitly omit roster rows.
    -- Bypasses dedup + throttle (force=true). Retry once so a transient
    -- malformed terminal screenshot does not leave the companion overlay stale.
    entryCreationKeyState.ClearRosterInspectBatchState()
    entryCreationKeyState.ClearRosterLoadRetryState()
    entryCreationKeyState.ClearRosterCompositionChanged()
    MaybeTriggerScreenshot(true, nil, true)
    entryCreationKeyState.lastQuietFullPartySignature = nil
    entryCreationKeyState.lastPayloadQuietFullPartySignature = nil
    local clearRetryGen = sessionGen
    C_Timer.After(entryCreationKeyState.END_SESSION_CLEAR_RETRY_DELAY_S, function()
        if sessionGen == clearRetryGen and not isSessionActive then
            MaybeTriggerScreenshot(true, nil, true)
        end
    end)
    -- Defensive: force-shot path resets pendingShotDirty on success, but if it
    -- early-returned (qrFrame missing, QR encode failure) the flag could persist
    -- across sessions and trigger empty drains in the scan ticker. Clear here.
    pendingShotDirty = false
    entryCreationKeyState.lastEmittedApplicantCount = 0
    entryCreationKeyState.entryCreationKeyLevelCache = nil

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

local function _HasGroupRosterForTransport()
    return math.floor(SafeNumber(GetNumGroupMembers and GetNumGroupMembers(), 0)) > 0
end

entryCreationKeyState.AutoHiGroupMemberCount = function()
    return math.floor(SafeNumber(GetNumGroupMembers and GetNumGroupMembers(), 0))
end

entryCreationKeyState.IsGroupedForAutoHi = function()
    return entryCreationKeyState.AutoHiGroupMemberCount() > 1
end

entryCreationKeyState.AutoHiChatChannel = function()
    local inInstance, instanceType = false, nil
    if IsInInstance then
        inInstance, instanceType = IsInInstance()
    end
    if inInstance and (instanceType == "party" or instanceType == "raid") then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    return "PARTY"
end

entryCreationKeyState.SendAutoHiChatMessage = function(message)
    if IsChatMessagingLockdown() then return false end
    local channel = entryCreationKeyState.AutoHiChatChannel()
    if C_ChatInfo and type(C_ChatInfo.SendChatMessage) == "function" then
        C_ChatInfo.SendChatMessage(message, channel)
        return true
    end
    if type(SendChatMessage) == "function" then
        SendChatMessage(message, channel)
        return true
    end
    return false
end

entryCreationKeyState.IsPartyForAutoHiNewMembers = function()
    if IsInRaid and IsInRaid() then return false end
    return entryCreationKeyState.AutoHiGroupMemberCount() > 1
end

entryCreationKeyState.IsPartyContextForAutoHiNewMembers = function()
    if IsInRaid and IsInRaid() then return false end
    if entryCreationKeyState.AutoHiGroupMemberCount() <= 0 then return false end
    return true
end

entryCreationKeyState.CollectAutoHiPartyMemberGUIDs = function()
    local guids = {}
    if entryCreationKeyState.AutoHiGroupMemberCount() <= 0 then return guids end
    if IsInRaid and IsInRaid() then return guids end
    if not UnitGUID then return guids end
    for i = 1, 4 do
        local guid = UnitGUID("party" .. i)
        if type(guid) == "string" and guid ~= "" then
            guids[guid] = true
        end
    end
    return guids
end

entryCreationKeyState.ResetAutoHiPartyMembers = function()
    entryCreationKeyState.autoHiKnownPartyGUIDs = {}
    entryCreationKeyState.autoHiKnownPartyMembersPrimed = false
    entryCreationKeyState.autoHiNewPartyMemberGen =
        entryCreationKeyState.autoHiNewPartyMemberGen + 1
end

entryCreationKeyState.PrimeAutoHiPartyMembers = function()
    if not entryCreationKeyState.IsPartyContextForAutoHiNewMembers() then
        entryCreationKeyState.ResetAutoHiPartyMembers()
        return
    end
    entryCreationKeyState.autoHiKnownPartyGUIDs =
        entryCreationKeyState.CollectAutoHiPartyMemberGUIDs()
    entryCreationKeyState.autoHiKnownPartyMembersPrimed = true
    entryCreationKeyState.autoHiNewPartyMemberGen =
        entryCreationKeyState.autoHiNewPartyMemberGen + 1
end

entryCreationKeyState.UpdateAutoHiPartyMembers = function(currentGUIDs)
    local previousGUIDs = entryCreationKeyState.autoHiKnownPartyGUIDs or {}
    local changed = false
    local hasNew = false
    for guid in pairs(currentGUIDs) do
        if not previousGUIDs[guid] then
            changed = true
            hasNew = true
        end
    end
    for guid in pairs(previousGUIDs) do
        if not currentGUIDs[guid] then
            changed = true
        end
    end
    entryCreationKeyState.autoHiKnownPartyGUIDs = currentGUIDs
    if changed then
        entryCreationKeyState.autoHiNewPartyMemberGen =
            entryCreationKeyState.autoHiNewPartyMemberGen + 1
    end
    return changed, hasNew
end

entryCreationKeyState.SyncAutoHiInitialGroupState = function()
    local groupMemberCount = entryCreationKeyState.AutoHiGroupMemberCount()
    local isGrouped = groupMemberCount > 1
    local isSoloGroup = groupMemberCount == 1
    if entryCreationKeyState.autoHiGroupStateKnown
       and entryCreationKeyState.autoHiWasInGroup == isGrouped
       and entryCreationKeyState.autoHiWasInSoloGroup == isSoloGroup then
        entryCreationKeyState.PrimeAutoHiPartyMembers()
        return
    end
    entryCreationKeyState.autoHiGroupStateKnown = true
    entryCreationKeyState.autoHiWasInGroup = isGrouped
    entryCreationKeyState.autoHiWasInSoloGroup = isSoloGroup
    entryCreationKeyState.autoHiGroupGen =
        entryCreationKeyState.autoHiGroupGen + 1
    entryCreationKeyState.PrimeAutoHiPartyMembers()
end

entryCreationKeyState.ScheduleAutoHiIfGroupJoined = function()
    local groupMemberCount = entryCreationKeyState.AutoHiGroupMemberCount()
    if groupMemberCount <= 0 then
        if entryCreationKeyState.autoHiWasInGroup
           or entryCreationKeyState.autoHiWasInSoloGroup then
            entryCreationKeyState.autoHiGroupGen =
                entryCreationKeyState.autoHiGroupGen + 1
        end
        entryCreationKeyState.autoHiGroupStateKnown = true
        entryCreationKeyState.autoHiWasInGroup = false
        entryCreationKeyState.autoHiWasInSoloGroup = false
        entryCreationKeyState.ResetAutoHiPartyMembers()
        return
    end
    if groupMemberCount == 1 then
        if entryCreationKeyState.autoHiWasInGroup then
            entryCreationKeyState.autoHiGroupGen =
                entryCreationKeyState.autoHiGroupGen + 1
        end
        entryCreationKeyState.autoHiGroupStateKnown = true
        entryCreationKeyState.autoHiWasInGroup = false
        entryCreationKeyState.autoHiWasInSoloGroup = true
        entryCreationKeyState.PrimeAutoHiPartyMembers()
        return
    end
    if not entryCreationKeyState.autoHiGroupStateKnown then
        entryCreationKeyState.SyncAutoHiInitialGroupState()
        return
    end
    if entryCreationKeyState.autoHiWasInGroup then return end
    if entryCreationKeyState.autoHiWasInSoloGroup then
        entryCreationKeyState.autoHiWasInGroup = true
        entryCreationKeyState.autoHiWasInSoloGroup = false
        entryCreationKeyState.autoHiGroupGen =
            entryCreationKeyState.autoHiGroupGen + 1
        return
    end
    entryCreationKeyState.autoHiWasInGroup = true
    entryCreationKeyState.autoHiWasInSoloGroup = false
    entryCreationKeyState.autoHiGroupGen =
        entryCreationKeyState.autoHiGroupGen + 1
    entryCreationKeyState.PrimeAutoHiPartyMembers()

    if not (ApplicantScoutDB and ApplicantScoutDB.enabled) then return end
    if entryCreationKeyState.NormalizeAutoHiMessage(
        ApplicantScoutDB.autoHiMessage
    ) == "" then return end
    if not (C_Timer and C_Timer.After) then return end

    local groupGen = entryCreationKeyState.autoHiGroupGen
    C_Timer.After(entryCreationKeyState.AUTO_HI_DELAY_S, function()
        if groupGen ~= entryCreationKeyState.autoHiGroupGen then return end
        if not (ApplicantScoutDB and ApplicantScoutDB.enabled) then return end
        if not entryCreationKeyState.IsGroupedForAutoHi() then return end

        local message = entryCreationKeyState.NormalizeAutoHiMessage(
            ApplicantScoutDB.autoHiMessage
        )
        if message == "" then return end
        entryCreationKeyState.SendAutoHiChatMessage(message)
    end)
end

entryCreationKeyState.ScheduleAutoHiForNewPartyMembers = function()
    if not entryCreationKeyState.IsPartyContextForAutoHiNewMembers() then
        entryCreationKeyState.ResetAutoHiPartyMembers()
        return
    end
    local currentGUIDs = entryCreationKeyState.CollectAutoHiPartyMemberGUIDs()
    if not entryCreationKeyState.autoHiKnownPartyMembersPrimed then
        entryCreationKeyState.autoHiKnownPartyGUIDs = currentGUIDs
        entryCreationKeyState.autoHiKnownPartyMembersPrimed = true
        entryCreationKeyState.autoHiNewPartyMemberGen =
            entryCreationKeyState.autoHiNewPartyMemberGen + 1
        return
    end
    local changed, hasNew =
        entryCreationKeyState.UpdateAutoHiPartyMembers(currentGUIDs)
    if not (changed and hasNew) then return end

    if not (ApplicantScoutDB and ApplicantScoutDB.enabled) then return end
    if not ApplicantScoutDB.autoHiGreetNewPartyMembers then return end
    if entryCreationKeyState.NormalizeAutoHiMessage(
        ApplicantScoutDB.autoHiMessage
    ) == "" then return end
    if not (C_Timer and C_Timer.After) then return end

    local groupGen = entryCreationKeyState.autoHiNewPartyMemberGen
    C_Timer.After(entryCreationKeyState.AUTO_HI_NEW_PARTY_MEMBER_DELAY_S, function()
        if groupGen ~= entryCreationKeyState.autoHiNewPartyMemberGen then return end
        if not (ApplicantScoutDB and ApplicantScoutDB.enabled) then return end
        if not ApplicantScoutDB.autoHiGreetNewPartyMembers then return end
        if not entryCreationKeyState.IsPartyForAutoHiNewMembers() then return end

        local message = entryCreationKeyState.NormalizeAutoHiMessage(
            ApplicantScoutDB.autoHiMessage
        )
        if message == "" then return end
        entryCreationKeyState.SendAutoHiChatMessage(message)
    end)
end

CheckSessionTransition = function()
    local hasEntry = C_LFGList.HasActiveEntryInfo()
    local entry = nil
    if hasEntry then
        entry = SafeTable(C_LFGList.GetActiveEntryInfo())
    end
    local hosting = entry ~= nil
    local hasRoster = _HasGroupRosterForTransport()
    local listingContext = entryCreationKeyState.EntryListingCacheContext(entry)
    entryCreationKeyState.ReconcileEntryCreationKeyCache(listingContext)
    local transportActive = hosting or hasRoster

    if transportActive and not isSessionActive then
        StartSession()
    elseif not transportActive and isSessionActive then
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
MarkDirty = function(reason)
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
    -- Hidden by default. Screenshot dispatch takes a temporary visibility
    -- lease only after a changed payload has been painted.
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
--   qrForceVisibleForShot       — auto: changed snapshot is being captured
--   qrAlwaysVisible             — manual: /apscout qrvisible debug override
--   qrMoveMode                  — manual: /apscout qrmove drag/debug mode
-- Debug override/move mode wins over normal hidden state (user explicitly said
-- "show me"). Interaction suppression gates non-force dispatch before a lease
-- is acquired.
_RefreshQRMouse = function()
    if not qrFrame then return end
    qrFrame:EnableMouse(qrMoveMode and true or false)
end

_RefreshQRVisibility = function()
    if not qrFrame then return end
    local wasShown = qrFrame:IsShown()
    local shouldShow = qrAlwaysVisible
                       or qrMoveMode
                       or qrForceVisibleForShot
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

_IsQRVisibleForScreenshot = function()
    return qrFrame and qrFrame:IsShown()
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
    local newlyHookedVisible = false
    for _, name in ipairs(INFO_PANEL_FRAMES) do
        if not _hookedInfoPanels[name] then
            local frame = _G[name]
            if frame and frame.HookScript then
                frame:HookScript("OnShow", _RecomputeInteractionSuppression)
                frame:HookScript("OnHide", _RecomputeInteractionSuppression)
                _hookedInfoPanels[name] = true
                if frame.IsShown and frame:IsShown() then
                    newlyHookedVisible = true
                end
            end
        end
    end
    if newlyHookedVisible then
        _RecomputeInteractionSuppression()
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
local PVE_POSITION_LIMIT = 100000
local PVE_VALID_POINTS = {
    CENTER = true,
    TOP = true,
    BOTTOM = true,
    LEFT = true,
    RIGHT = true,
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
}

local function _IsFinitePVEPositionNumber(v)
    return type(v) == "number" and v == v
           and v > -PVE_POSITION_LIMIT and v < PVE_POSITION_LIMIT
end

local function _NormalizePVEFramePosition(pos)
    if type(pos) ~= "table" then return nil, 0, 0, false end
    local point, x, y = pos.point, pos.x, pos.y
    if type(point) ~= "string" or not PVE_VALID_POINTS[point] then
        return nil, 0, 0, false
    end
    if not (_IsFinitePVEPositionNumber(x) and _IsFinitePVEPositionNumber(y)) then
        return nil, 0, 0, false
    end
    return point, x, y, true
end

local function _ClearInvalidPVEFramePosition()
    if ApplicantScoutDB then
        ApplicantScoutDB.pveFramePosition = nil
    end
end

local function _SavePVEFramePositionFromFrame(frame)
    if not (frame and ApplicantScoutDB) then return end
    -- WARNING: GetPoint() returns nil if no anchor set. Invalid parts should
    -- not clobber a prior valid position or poison the next restore/status.
    local point, _, _, x, y = frame:GetPoint()
    local savedPoint, savedX, savedY, ok =
        _NormalizePVEFramePosition({ point = point, x = x, y = y })
    if not ok then return end
    ApplicantScoutDB.pveFramePosition = {
        point = savedPoint,
        x = savedX,
        y = savedY,
    }
end

local function _OnPVEFrameDragStart()
    if InCombatLockdown() then return end
    if not IsAltKeyDown() then return end
    PVEFrame:StartMoving()
    PVEFrame.apsMoving = true
end

local function _OnPVEFrameDragStop()
    if not PVEFrame.apsMoving then return end
    PVEFrame:StopMovingOrSizing()
    PVEFrame.apsMoving = false
    _SavePVEFramePositionFromFrame(PVEFrame)
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
        if not saved then return end
        local point, x, y, ok = _NormalizePVEFramePosition(saved)
        if not ok then
            _ClearInvalidPVEFramePosition()
            return
        end
        if InCombatLockdown() then return end
        C_Timer.After(0, function()
            if InCombatLockdown() then return end
            if not self:IsShown() then return end
            -- WARNING: SetUserPlaced order is
            -- ClearAllPoints -> SetPoint -> SetUserPlaced(true). Wrong
            -- order leaks WoW's layout-cache restore atop our anchor.
            self:ClearAllPoints()
            self:SetPoint(point, UIParent, point, x, y)
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
--   LeaderKey: has_leader_key byte; if 1: uint8 keyLevel +
--              uint16 challengeMapID + len-prefixed leaderName
--   Apps:      uint16 count; per applicant: uint32 id + uint8 member_idx +
--              uint8 classID + uint16 specID + uint16 ilvl + uint16 score +
--              uint16 mainScore + uint8 rioProfile + uint8 rioBestKey +
--              uint8 rioBestDungeonKey + uint8 rioTimedAtTarget +
--              uint8 rioTimedAtMinus1 + uint8 rioTimedAtMinus2 +
--              uint8 rioCompletedAtMinus1 + uint8 rioDungeonCount +
--              uint8 role + uint8 nameLen + utf8 name (CLAMPED to 255 bytes)
--   Roster:    uint16 count; per current party/raid member: uint8 unitIndex +
--              uint8 flags + uint8 subgroup + same class/spec/score/RIO/role
--              tail as applicant rows, then nameLen + utf8 name.
--   Trailer:   uint32 CRC32 (IEEE 802.3) over [magic..last roster byte]
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
    invited=true, inviteaccepted=true, none=true,
}

local function _GetApplicantApplicationStatus(info)
    -- Current C_LFGList.GetApplicantInfo uses applicationStatus. Keep the older
    -- applicantStatus spelling as a compatibility fallback for stubs/build drift.
    local status = SafeEnumKey(info and info.applicationStatus, nil)
    if status == nil or status == "" then
        status = SafeEnumKey(info and info.applicantStatus, "")
    end
    return status
end

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

local function _ClampUInt16(n)
    n = math.floor(SafeNumber(n, 0))
    if n < 0 then return 0 end
    if n > 65535 then return 65535 end
    return n
end

local function _ClampUInt8(n)
    n = math.floor(SafeNumber(n, 0))
    if n < 0 then return 0 end
    if n > 255 then return 255 end
    return n
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

local function _ExtractKeystoneLevelFromShortKeyText(value)
    local keyLevel = _ExtractKeystoneLevelFromText(value)
    if keyLevel > 0 then return keyLevel end

    local s = SafeStr(value, "")
    if s == "" then return 0 end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    -- Blizzard can render titles like "+10", "+10 Competitive", or with a
    -- plus-like glyph that is not ASCII. Digit-filter only short title/UI
    -- fields; comments still require an explicit ASCII "+N" match.
    if #s > 40 then return 0 end
    local digits = s:gsub("%D+", "")
    if #digits < 1 or #digits > 2 then return 0 end
    return _NormalizeKeystoneLevel(digits)
end

local function _ReadCleanWidgetText(widget)
    if not (widget and type(widget.GetText) == "function") then return "" end
    local ok, text = pcall(widget.GetText, widget)
    if not ok or IsSecretValue(text) then return "" end
    return SafeStr(text, "")
end

entryCreationKeyState.EntryListingCacheContext = function(entry)
    entry = SafeTable(entry)
    if not entry then return nil end
    local activityIDs = SafeTable(entry.activityIDs)
    local activityID = math.floor(SafeNumber(activityIDs and activityIDs[1], 0))
    if activityID <= 0 then
        activityID = math.floor(SafeNumber(entry.activityID, 0))
    end
    if activityID < 0 then activityID = 0 end
    local questID = math.floor(SafeNumber(entry.questID, 0))
    if questID < 0 then questID = 0 end
    return { activityID = activityID, questID = questID }
end

local function _EntryCreationCacheFresh(cache)
    cache = SafeTable(cache)
    if not cache then return false end
    if GetTime and (GetTime() - SafeNumber(cache.at, 0)) > ENTRY_CREATION_KEY_CACHE_TTL then
        return false
    end
    return true
end

local function _EntryCreationCacheMatchesListing(cache, listingContext)
    if not _EntryCreationCacheFresh(cache) then return false end
    listingContext = SafeTable(listingContext)
    if not listingContext then return false end

    local activityID = math.floor(SafeNumber(listingContext.activityID, 0))
    if activityID <= 0 then return false end

    local cacheActivityID = math.floor(SafeNumber(cache.activityID, 0))
    if cacheActivityID <= 0 or cacheActivityID ~= activityID then
        return false
    end

    local questID = math.floor(SafeNumber(listingContext.questID, 0))
    local cacheQuestID = math.floor(SafeNumber(cache.questID, 0))
    if cacheQuestID > 0 and questID > 0 and cacheQuestID ~= questID then
        return false
    end
    return true
end

local function _SameEntryListingCacheContext(a, b)
    a = SafeTable(a)
    b = SafeTable(b)
    if not a or not b then return false end
    return math.floor(SafeNumber(a.activityID, 0)) == math.floor(SafeNumber(b.activityID, 0))
       and math.floor(SafeNumber(a.questID, 0)) == math.floor(SafeNumber(b.questID, 0))
end

local function _ClearEntryCreationKeyLevelCache(reason)
    entryCreationKeyState.entryCreationKeyLevelCache = nil
    entryCreationKeyState.pendingEntryCreationKeyLevelCache = nil
    entryCreationKeyState.entryCreationKeyLevelCacheDecision = reason or "cleared"
end

local function _PublishPendingEntryCreationKeyLevelCache(listingContext)
    if GetTime
       and entryCreationKeyState.pendingEntryCreationKeyLevelCache
       and (GetTime() - SafeNumber(entryCreationKeyState.pendingEntryCreationKeyLevelCache.at, 0))
           > entryCreationKeyState.pendingTtl then
        entryCreationKeyState.pendingEntryCreationKeyLevelCache = nil
        entryCreationKeyState.entryCreationKeyLevelCacheDecision = "ignored: pending submit expired"
        return false
    end
    if not _EntryCreationCacheMatchesListing(entryCreationKeyState.pendingEntryCreationKeyLevelCache, listingContext) then
        entryCreationKeyState.pendingEntryCreationKeyLevelCache = nil
        return false
    end
    entryCreationKeyState.entryCreationKeyLevelCache = entryCreationKeyState.pendingEntryCreationKeyLevelCache
    entryCreationKeyState.pendingEntryCreationKeyLevelCache = nil
    entryCreationKeyState.entryCreationKeyLevelCacheDecision = "promoted pending submit"
    return true
end

entryCreationKeyState.ResolveCachedEntryCreationKeystoneLevel = function(activityID, questID)
    activityID = math.floor(SafeNumber(activityID, 0))
    if activityID <= 0 then
        return 0, "ignored: active activity unknown", false
    end
    local cache = entryCreationKeyState.entryCreationKeyLevelCache
    if not cache then return 0, nil, false end
    if not _EntryCreationCacheFresh(cache) then
        return 0, "ignored: expired", true
    end

    questID = math.floor(SafeNumber(questID, 0))
    if cache.activityID <= 0 or cache.activityID ~= activityID then
        return 0, "ignored: activity mismatch", false
    end
    if cache.questID > 0 and questID > 0 and cache.questID ~= questID then
        return 0, "ignored: quest mismatch", false
    end
    return _NormalizeKeystoneLevel(cache.keyLevel), "used", false
end

entryCreationKeyState.PeekCachedEntryCreationKeystoneLevel = function(activityID, questID)
    local level = entryCreationKeyState.ResolveCachedEntryCreationKeystoneLevel(activityID, questID)
    return level
end

local function _GetCachedEntryCreationKeystoneLevel(activityID, questID)
    local level, decision, clearExpired =
        entryCreationKeyState.ResolveCachedEntryCreationKeystoneLevel(activityID, questID)
    if clearExpired then
        entryCreationKeyState.entryCreationKeyLevelCache = nil
    end
    if decision then
        entryCreationKeyState.entryCreationKeyLevelCacheDecision = decision
    end
    return level
end

local function _ClearEntryCreationKeystoneLevelCache(activityID, questID)
    activityID = math.floor(SafeNumber(activityID, 0))
    questID = math.floor(SafeNumber(questID, 0))
    local listingContext = { activityID = activityID, questID = questID }
    if _EntryCreationCacheMatchesListing(entryCreationKeyState.pendingEntryCreationKeyLevelCache, listingContext) then
        entryCreationKeyState.pendingEntryCreationKeyLevelCache = nil
    end
    if _EntryCreationCacheMatchesListing(entryCreationKeyState.entryCreationKeyLevelCache, listingContext) then
        entryCreationKeyState.entryCreationKeyLevelCache = nil
        entryCreationKeyState.entryCreationKeyLevelCacheDecision = "cleared: form key unreadable"
    end
end

entryCreationKeyState.PrintDiagnostics = function()
    print("  entry key capture hooks: " .. tostring(lfgEntryCreationKeyCaptureState.hooksSetup)
          .. (lfgEntryCreationKeyCaptureState.hookError
              and (" (error: " .. lfgEntryCreationKeyCaptureState.hookError .. ")")
              or ""))
    local pendingCache = SafeTable(entryCreationKeyState.pendingEntryCreationKeyLevelCache)
    local publishedCache = SafeTable(entryCreationKeyState.entryCreationKeyLevelCache)
    print("  pendingEntryCreationCache.keyLevel: "
          .. tostring(pendingCache and pendingCache.keyLevel or 0))
    print("  pendingEntryCreationCache.activityID: "
          .. tostring(pendingCache and pendingCache.activityID or 0))
    print("  pendingEntryCreationCache.questID: "
          .. tostring(pendingCache and pendingCache.questID or 0))
    print("  publishedEntryCreationCache.keyLevel: "
          .. tostring(publishedCache and publishedCache.keyLevel or 0))
    print("  publishedEntryCreationCache.activityID: "
          .. tostring(publishedCache and publishedCache.activityID or 0))
    print("  publishedEntryCreationCache.questID: "
          .. tostring(publishedCache and publishedCache.questID or 0))
    print("  activeListingCache.generation: "
          .. tostring(entryCreationKeyState.activeListingGeneration))
    print("  activeListingCache.activityID: "
          .. tostring(entryCreationKeyState.activeListingCacheContext
                     and entryCreationKeyState.activeListingCacheContext.activityID or 0))
    print("  activeListingCache.questID: "
          .. tostring(entryCreationKeyState.activeListingCacheContext
                     and entryCreationKeyState.activeListingCacheContext.questID or 0))
    print("  listing cache decision: "
          .. tostring(entryCreationKeyState.entryCreationKeyLevelCacheDecision))
end

entryCreationKeyState.ReconcileEntryCreationKeyCache = function(listingContext)
    listingContext = SafeTable(listingContext)
    if not listingContext then
        if entryCreationKeyState.activeListingCacheContext then
            entryCreationKeyState.activeListingGeneration = entryCreationKeyState.activeListingGeneration + 1
            _ClearEntryCreationKeyLevelCache("listing-ended")
        else
            entryCreationKeyState.entryCreationKeyLevelCache = nil
            entryCreationKeyState.entryCreationKeyLevelCacheDecision = "idle"
        end
        entryCreationKeyState.activeListingCacheContext = nil
        entryCreationKeyState.activeListingMaybeChanged = false
        return
    end

    if math.floor(SafeNumber(listingContext.activityID, 0)) <= 0 then
        entryCreationKeyState.activeListingCacheContext = listingContext
        entryCreationKeyState.activeListingGeneration = entryCreationKeyState.activeListingGeneration + 1
        entryCreationKeyState.activeListingMaybeChanged = false
        _ClearEntryCreationKeyLevelCache("ignored: active activity unknown")
        return
    end

    local listingChanged = entryCreationKeyState.activeListingMaybeChanged
       or not _SameEntryListingCacheContext(entryCreationKeyState.activeListingCacheContext, listingContext)
    if listingChanged then
        entryCreationKeyState.activeListingGeneration = entryCreationKeyState.activeListingGeneration + 1
        entryCreationKeyState.activeListingCacheContext = listingContext
        if not _PublishPendingEntryCreationKeyLevelCache(listingContext) then
            _ClearEntryCreationKeyLevelCache("stale-after-entry-update")
        end
        entryCreationKeyState.activeListingMaybeChanged = false
        return
    end

    entryCreationKeyState.activeListingCacheContext = listingContext
    if entryCreationKeyState.pendingEntryCreationKeyLevelCache then
        _PublishPendingEntryCreationKeyLevelCache(listingContext)
    end
    entryCreationKeyState.activeListingMaybeChanged = false
end

local function _RememberEntryCreationKeystoneLevel(panel, reason)
    if not panel then return false end

    local activityID = panel.selectedActivity
    if IsSecretValue(activityID) then return false end
    activityID = math.floor(SafeNumber(activityID, 0))
    if activityID <= 0 then return false end

    local activityInfo = nil
    if C_LFGList and C_LFGList.GetActivityInfoTable then
        activityInfo = SafeTable(C_LFGList.GetActivityInfoTable(activityID))
    end
    if not activityInfo then return false end
    local isMythicPlusActivity = activityInfo.isMythicPlusActivity
    if IsSecretValue(isMythicPlusActivity)
       or IsSecretValue(activityInfo.categoryID) then
        return false
    end
    if isMythicPlusActivity ~= true
       and math.floor(SafeNumber(activityInfo.categoryID, 0)) ~= 2 then
        return false
    end

    local nameText = _ReadCleanWidgetText(panel.Name)
    local commentText = _ReadCleanWidgetText(panel.Description)
    local keyLevel = _ExtractKeystoneLevelFromShortKeyText(nameText)
    if keyLevel == 0 then
        keyLevel = _ExtractKeystoneLevelFromText(commentText)
    end
    local questID = math.floor(SafeNumber(panel.questID, 0))
    if keyLevel == 0 then
        _ClearEntryCreationKeystoneLevelCache(activityID, questID)
        return false
    end

    entryCreationKeyState.pendingEntryCreationKeyLevelCache = {
        activityID = activityID,
        questID = questID,
        keyLevel = keyLevel,
        at = GetTime and GetTime() or 0,
    }
    if ApplicantScoutDB and ApplicantScoutDB.debug then
        print("|cff999999[APS-debug]|r LFG posted key cached: +"
              .. tostring(keyLevel)
              .. (reason and (" (" .. reason .. ")") or ""))
    end
    return true
end

local function _HookEntryCreationKeyCapture(panel)
    if not panel or lfgEntryCreationKeyCaptureHooked[panel] then return end
    lfgEntryCreationKeyCaptureHooked[panel] = true

    local button = panel.ListGroupButton
    if button and type(button.HookScript) == "function" then
        button:HookScript("OnClick", function()
            _RememberEntryCreationKeystoneLevel(panel, "button")
        end)
    end

    local nameBox = panel.Name
    if nameBox and type(nameBox.HookScript) == "function" then
        nameBox:HookScript("OnEnterPressed", function()
            _RememberEntryCreationKeystoneLevel(panel, "enter")
        end)
    end
end

local function _GetVisibleApplicationViewerKeystoneLevel()
    local lfgFrame = _G.LFGListFrame
    local viewer = lfgFrame and lfgFrame.ApplicationViewer
    if not viewer then return 0 end
    if type(viewer.IsShown) == "function" and not viewer:IsShown() then return 0 end

    local candidates = {
        { label = "EntryName", fontString = viewer.EntryName },
        {
            label = "DescriptionFrame.Text",
            fontString = viewer.DescriptionFrame and viewer.DescriptionFrame.Text,
        },
    }
    for _, candidate in ipairs(candidates) do
        local fontString = candidate.fontString
        if fontString and type(fontString.GetText) == "function" then
            local ok, text = pcall(fontString.GetText, fontString)
            if ok and not IsSecretValue(text) then
                local keyLevel = _ExtractKeystoneLevelFromShortKeyText(text)
                if keyLevel > 0 then
                    return keyLevel
                end
            end
        end
    end
    return 0
end

local function _GetVisibleApplicationViewerKeystoneDiagnostics()
    local lines = {}
    local lfgFrame = _G.LFGListFrame
    local viewer = lfgFrame and lfgFrame.ApplicationViewer
    lines[#lines + 1] = "  visibleFrame.viewer: " .. tostring(viewer ~= nil)
    if not viewer then return lines end

    local shown = "n/a"
    if type(viewer.IsShown) == "function" then
        local ok, result = pcall(viewer.IsShown, viewer)
        shown = ok and tostring(result) or "<error>"
    end
    lines[#lines + 1] = "  visibleFrame.viewerShown: " .. shown

    local candidates = {
        { label = "EntryName", fontString = viewer.EntryName },
        {
            label = "DescriptionFrame.Text",
            fontString = viewer.DescriptionFrame and viewer.DescriptionFrame.Text,
        },
    }
    for _, candidate in ipairs(candidates) do
        local label = candidate.label
        local fontString = candidate.fontString
        if fontString and type(fontString.GetText) == "function" then
            local ok, text = pcall(fontString.GetText, fontString)
            if ok then
                local isSecret = IsSecretValue(text)
                local keyLevel = isSecret and 0 or _ExtractKeystoneLevelFromShortKeyText(text)
                lines[#lines + 1] = "  visibleFrame." .. label
                    .. ": " .. SafeDiag(text)
                    .. " secret=" .. tostring(isSecret)
                    .. " key=" .. tostring(keyLevel)
            else
                lines[#lines + 1] = "  visibleFrame." .. label .. ": <error>"
            end
        else
            lines[#lines + 1] = "  visibleFrame." .. label .. ": nil"
        end
    end
    return lines
end
_G.ApplicantScout_VisibleApplicationViewerKeystoneDiagnostics =
    _GetVisibleApplicationViewerKeystoneDiagnostics
_G.ApplicantScout_VisibleApplicationViewerKeystoneLevel =
    _GetVisibleApplicationViewerKeystoneLevel

local function _GetActivityInfoForListing(activityID, questID)
    if not (C_LFGList and C_LFGList.GetActivityInfoTable) then return nil end
    activityID = math.floor(SafeNumber(activityID, 0))
    if activityID <= 0 then return nil end
    questID = math.floor(SafeNumber(questID, 0))
    if questID > 0 then
        local info = SafeTable(C_LFGList.GetActivityInfoTable(activityID, questID))
        if info then return info end
    end
    return SafeTable(C_LFGList.GetActivityInfoTable(activityID))
end

local function _ActivityInfoListingName(activityInfo)
    activityInfo = SafeTable(activityInfo)
    if not activityInfo then return "?" end
    local shortName = SafeStr(activityInfo.shortName, "?")
    if shortName ~= "" and shortName ~= "?" then
        return shortName
    end
    local fullName = SafeStr(activityInfo.fullName, "?")
    return (fullName ~= "" and fullName) or "?"
end

local function _GetOwnedKeystoneListingInfo()
    if not (C_LFGList and C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel) then
        return 0, 0, 0, nil
    end
    local ok, ownedActivityID, ownedGroupID, ownedLevel = pcall(
        C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel
    )
    if not ok then return 0, 0, 0, nil end
    ownedActivityID = math.floor(SafeNumber(ownedActivityID, 0))
    ownedGroupID = math.floor(SafeNumber(ownedGroupID, 0))
    ownedLevel = _NormalizeKeystoneLevel(ownedLevel)
    local ownedInfo = nil
    if ownedActivityID > 0 then
        ownedInfo = _GetActivityInfoForListing(ownedActivityID, 0)
    end
    return ownedActivityID, ownedGroupID, ownedLevel, ownedInfo
end

entryCreationKeyState.CanUseOwnedKeystoneForListingFallback = function()
    if not (IsInGroup and IsInGroup()) then return true end
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
    return false
end

local function _GetListingKeystoneLevel(activityID, questID, listingName, listingComment, activityInfo)
    -- WARNING: C_LFGList.GetKeystoneForActivity can report the host's owned
    -- key for this dungeon instead of the active posted listing level.
    local keyLevel = _ExtractKeystoneLevelFromShortKeyText(listingName)
    if keyLevel == 0 then
        keyLevel = _ExtractKeystoneLevelFromText(listingComment)
    end
    if keyLevel == 0 then
        keyLevel = _GetVisibleApplicationViewerKeystoneLevel()
    end
    if keyLevel == 0 then
        keyLevel = _GetCachedEntryCreationKeystoneLevel(activityID, questID)
    end
    activityInfo = SafeTable(activityInfo)
    if keyLevel == 0 and activityInfo then
        local activityShortName = SafeStr(activityInfo.shortName, "")
        keyLevel = _ExtractKeystoneLevelFromText(activityShortName)
    end
    if keyLevel == 0 and activityInfo then
        local activityFullName = SafeStr(activityInfo.fullName, "")
        keyLevel = _ExtractKeystoneLevelFromText(activityFullName)
    end
    return keyLevel
end
_G.ApplicantScout_GetListingKeystoneLevel = _GetListingKeystoneLevel
_G.ApplicantScout_CachedEntryCreationKeystoneLevel =
    _GetCachedEntryCreationKeystoneLevel

local function _RaiderIODungeonMatchesActivity(dungeon, listingActivityID)
    dungeon = SafeTable(dungeon)
    listingActivityID = math.floor(SafeNumber(listingActivityID, 0))
    if not dungeon or listingActivityID <= 0 then return false end

    local lfdActivityIDs = SafeTable(dungeon.lfd_activity_ids)
    if lfdActivityIDs then
        for _, rawActivityID in ipairs(lfdActivityIDs) do
            if math.floor(SafeNumber(rawActivityID, 0)) == listingActivityID then
                return true
            end
        end
    end

    return math.floor(SafeNumber(dungeon.keystone_instance, 0)) == listingActivityID
end

local function _EmptyRaiderIOMPlusSummary(currentScore, mainScore)
    return {
        currentScore = _ClampUInt16(currentScore),
        mainScore = _ClampUInt16(mainScore),
        hasProfile = false,
        bestKey = 0,
        bestDungeonKey = 0,
        timedAtOrAbove = 0,
        timedAtOrAboveMinus1 = 0,
        timedAtOrAboveMinus2 = 0,
        completedAtOrAboveMinus1 = 0,
        dungeonCount = 0,
    }
end

local function _RaiderIOProfileLookupName(memberName)
    memberName = SafeStr(memberName, "")
    if memberName == "" or memberName == "?" or memberName:find("-", 1, true) then
        return memberName
    end
    local _playerName, playerRealm = UnitFullName("player")
    playerRealm = SafeStr(playerRealm, "")
    if playerRealm == "" then return memberName end
    -- WHY: LFG may emit same-realm applicants as bare "Name"; RaiderIO profile
    -- lookups need the realm-qualified key to expose per-dungeon history.
    return memberName .. "-" .. playerRealm
end

local function _GetRaiderIOMPlusSummary(memberName, listingActivityID, targetKey)
    -- RaiderIO is optional. Query only with the SafeStr-cleaned applicant name:
    -- the raw LFG name can be secret-tagged, and RaiderIO's public API performs
    -- string parsing internally.
    if memberName == "" or memberName == "?" then
        return _EmptyRaiderIOMPlusSummary(0, 0)
    end
    local rio = SafeTable(_G.RaiderIO)
    if not rio or type(rio.GetProfile) ~= "function" then
        return _EmptyRaiderIOMPlusSummary(0, 0)
    end

    local ok, profile = pcall(rio.GetProfile, memberName)
    if not ok then return _EmptyRaiderIOMPlusSummary(0, 0) end
    profile = SafeTable(profile)
    if not profile then return _EmptyRaiderIOMPlusSummary(0, 0) end

    local keystoneProfile = SafeTable(profile.mythicKeystoneProfile)
    if not keystoneProfile then return _EmptyRaiderIOMPlusSummary(0, 0) end
    if IsSecretValue(keystoneProfile.blocked) or keystoneProfile.blocked then
        return _EmptyRaiderIOMPlusSummary(0, 0)
    end

    local current = SafeTable(keystoneProfile.mplusCurrent)
    local currentScore = keystoneProfile.currentScore
    if current then
        currentScore = current.score
    end
    local mainCurrent = SafeTable(keystoneProfile.mplusMainCurrent)
    local mainScore = keystoneProfile.mainCurrentScore
    if mainCurrent then
        mainScore = mainCurrent.score
    end
    local summary = _EmptyRaiderIOMPlusSummary(currentScore, mainScore)

    local sortedDungeons = SafeTable(keystoneProfile.sortedDungeons)
    if not sortedDungeons then return summary end

    targetKey = _NormalizeKeystoneLevel(targetKey)
    local targetMinus1 = targetKey > 0 and math.max(2, targetKey - 1) or 0
    local targetMinus2 = targetKey > 0 and math.max(2, targetKey - 2) or 0
    summary.hasProfile = true

    for _, sortedDungeon in ipairs(sortedDungeons) do
        local entry = SafeTable(sortedDungeon)
        if entry then
            local keyLevel = _NormalizeKeystoneLevel(entry.level)
            if keyLevel > 0 then
                local chests = math.floor(SafeNumber(entry.chests, 0))
                local timed = chests > 0
                local dungeon = SafeTable(entry.dungeon)
                summary.dungeonCount = summary.dungeonCount + 1
                if timed and keyLevel > summary.bestKey then
                    summary.bestKey = keyLevel
                end
                if timed
                   and _RaiderIODungeonMatchesActivity(dungeon, listingActivityID)
                   and keyLevel > summary.bestDungeonKey then
                    summary.bestDungeonKey = keyLevel
                end
                if targetKey > 0 and timed and keyLevel >= targetKey then
                    summary.timedAtOrAbove = summary.timedAtOrAbove + 1
                end
                if targetMinus1 > 0 then
                    if timed and keyLevel >= targetMinus1 then
                        summary.timedAtOrAboveMinus1 =
                            summary.timedAtOrAboveMinus1 + 1
                    end
                    if keyLevel >= targetMinus1 then
                        summary.completedAtOrAboveMinus1 =
                            summary.completedAtOrAboveMinus1 + 1
                    end
                end
                if targetMinus2 > 0 and timed and keyLevel >= targetMinus2 then
                    summary.timedAtOrAboveMinus2 =
                        summary.timedAtOrAboveMinus2 + 1
                end
            end
        end
    end

    summary.bestKey = _ClampUInt8(summary.bestKey)
    summary.bestDungeonKey = _ClampUInt8(summary.bestDungeonKey)
    summary.timedAtOrAbove = _ClampUInt8(summary.timedAtOrAbove)
    summary.timedAtOrAboveMinus1 = _ClampUInt8(summary.timedAtOrAboveMinus1)
    summary.timedAtOrAboveMinus2 = _ClampUInt8(summary.timedAtOrAboveMinus2)
    summary.completedAtOrAboveMinus1 =
        _ClampUInt8(summary.completedAtOrAboveMinus1)
    summary.dungeonCount = _ClampUInt8(summary.dungeonCount)
    return summary
end

local function _UnitFullNameForTransport(unit)
    local name, realm = "", ""
    if UnitFullName then
        local ok, unitName, unitRealm = pcall(UnitFullName, unit)
        if ok then
            name = SafeStr(unitName, "")
            realm = SafeStr(unitRealm, "")
        end
    end
    if name == "" and GetUnitName then
        local ok, unitName = pcall(GetUnitName, unit, true)
        if ok then name = SafeStr(unitName, "") end
    end
    name = SafeStr(name, "")
    if name == "" then return "" end
    if name:find("-", 1, true) then return name end
    if realm == "" and UnitFullName then
        local okPlayer, _playerName, playerRealm = pcall(UnitFullName, "player")
        if okPlayer then realm = SafeStr(playerRealm, "") end
    end
    if realm ~= "" then return name .. "-" .. realm end
    return name
end

local function _UnitClassIDForRoster(unit)
    if not UnitClass then return 0 end
    local ok, _localized, classToken, classID = pcall(UnitClass, unit)
    if not ok then return 0 end
    classID = math.floor(SafeNumber(classID, 0))
    if classID > 0 then return classID end
    classToken = SafeEnumKey(classToken, "")
    return CLASS_NAME_TO_ID[classToken] or 0
end

local rosterInspectSpecByGUID = {}
local rosterInspectPendingGUID = nil
local rosterInspectLastRequestTime = 0
local ROSTER_INSPECT_THROTTLE_S = 1.0
local ROSTER_INSPECT_TIMEOUT_S = 4.0

local function _UnitGUIDForRoster(unit)
    if not UnitGUID then return "" end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok then return "" end
    return SafeStr(guid, "")
end

local function _UnitExistsForRoster(unit)
    return UnitExists and UnitExists(unit) or false
end

local function _ForEachRosterUnit(callback)
    if type(callback) ~= "function" then return end
    local groupCount = math.floor(SafeNumber(GetNumGroupMembers and GetNumGroupMembers(), 0))
    if groupCount <= 0 then return end

    if IsInRaid and IsInRaid() then
        if groupCount > 40 then groupCount = 40 end
        for i = 1, groupCount do
            if callback("raid" .. i) then return end
        end
        return
    end

    if callback("player") then return end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists and UnitExists(unit) and callback(unit) then return end
    end
end

local function _FindRosterUnitByGUID(guid)
    guid = SafeStr(guid, "")
    if guid == "" then return nil end
    local found = nil
    _ForEachRosterUnit(function(unit)
        if _UnitGUIDForRoster(unit) == guid then
            found = unit
            return true
        end
        return false
    end)
    return found
end

local function _InvalidateRosterSpecCacheForUnit(unit)
    local guid = _UnitGUIDForRoster(unit)
    if guid ~= "" then
        rosterInspectSpecByGUID[guid] = nil
        entryCreationKeyState.rosterInspectIlvlByGUID[guid] = nil
        if rosterInspectPendingGUID == guid then
            rosterInspectPendingGUID = nil
        end
        return
    end
    rosterInspectSpecByGUID = {}
    entryCreationKeyState.rosterInspectIlvlByGUID = {}
    rosterInspectPendingGUID = nil
end

local function _MaybeRequestRosterInspect(unit, guid)
    if not (NotifyInspect and CanInspect) then return false, "api" end
    if UnitIsUnit and UnitIsUnit(unit, "player") then return false, "self" end
    guid = SafeStr(guid, "")
    if guid == "" then return false, "guid" end
    if entryCreationKeyState.RosterUnitHasResolvedInspectData(unit, guid) then
        return false, "cached"
    end

    local now = GetTime and GetTime() or 0
    if rosterInspectPendingGUID == guid
       and (now - rosterInspectLastRequestTime) < ROSTER_INSPECT_TIMEOUT_S then
        return false, "pending"
    end
    if rosterInspectPendingGUID
       and rosterInspectPendingGUID ~= guid
       and (now - rosterInspectLastRequestTime) < ROSTER_INSPECT_TIMEOUT_S then
        return false, "pending"
    end
    if (now - rosterInspectLastRequestTime) < ROSTER_INSPECT_THROTTLE_S then
        return false, "throttle"
    end
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end

    local okCan, canInspect = pcall(CanInspect, unit)
    if not (okCan and canInspect) then return false, "uninspectable" end
    local ok = pcall(NotifyInspect, unit)
    if ok then
        rosterInspectPendingGUID = guid
        rosterInspectLastRequestTime = now
        return true, "requested"
    end
    return false, "notify"
end

-- WARNING: keep these as entryCreationKeyState fields instead of new top-level
-- locals; this large Lua 5.1 file is already at local/upvalue limits.
entryCreationKeyState.rosterInspectBatchDirtyPending = false
entryCreationKeyState.rosterInspectBatchSkippedGUIDs = nil
entryCreationKeyState.rosterInspectBatchRetryToken = 0
entryCreationKeyState.rosterInspectBatchRetryDeadline = nil
entryCreationKeyState.rosterInspectBatchRetrySessionGen = nil
entryCreationKeyState.rosterInspectBatchCombatDeferred = false
entryCreationKeyState.rosterInspectBatchLastBlockReason = nil
entryCreationKeyState.CachedRosterInspectItemLevel = function(guid)
    guid = SafeStr(guid, "")
    if guid == "" then return 0 end
    return _ClampUInt16(SafeRoundedNumber(entryCreationKeyState.rosterInspectIlvlByGUID[guid], 0))
end
entryCreationKeyState.ReadRosterInspectItemLevel = function(unit)
    if not (C_PaperDollInfo and type(C_PaperDollInfo.GetInspectItemLevel) == "function") then
        return 0
    end
    local ok, ilvl = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
    if not ok or IsSecretValue(ilvl) then return 0 end
    return _ClampUInt16(SafeRoundedNumber(ilvl, 0))
end
entryCreationKeyState.RosterUnitHasResolvedInspectData = function(unit, guid)
    if UnitIsUnit and UnitIsUnit(unit, "player") then return true end
    guid = SafeStr(guid, "")
    if guid == "" then return false end

    local hasSpec = false
    local cachedSpecID = _ClampUInt16(SafeNumber(rosterInspectSpecByGUID[guid], 0))
    if cachedSpecID > 0 then
        hasSpec = true
    elseif GetInspectSpecialization then
        local ok, specID = pcall(GetInspectSpecialization, unit)
        specID = ok and _ClampUInt16(SafeNumber(specID, 0)) or 0
        if specID > 0 then
            rosterInspectSpecByGUID[guid] = specID
            hasSpec = true
        end
    end

    local hasIlvl = true
    if C_PaperDollInfo and type(C_PaperDollInfo.GetInspectItemLevel) == "function" then
        hasIlvl = entryCreationKeyState.CachedRosterInspectItemLevel(guid) > 0
        if not hasIlvl then
            local ilvl = entryCreationKeyState.ReadRosterInspectItemLevel(unit)
            if ilvl > 0 then
                entryCreationKeyState.rosterInspectIlvlByGUID[guid] = ilvl
                hasIlvl = true
            end
        end
    end

    return hasSpec and hasIlvl
end
entryCreationKeyState.ClearRosterInspectBatchState = function()
    entryCreationKeyState.rosterInspectBatchDirtyPending = false
    entryCreationKeyState.rosterInspectBatchSkippedGUIDs = nil
    entryCreationKeyState.rosterInspectBatchCombatDeferred = false
    entryCreationKeyState.rosterInspectBatchLastBlockReason = nil
    entryCreationKeyState.rosterInspectBatchRetryDeadline = nil
    entryCreationKeyState.rosterInspectBatchRetrySessionGen = nil
    entryCreationKeyState.rosterInspectBatchRetryToken =
        (entryCreationKeyState.rosterInspectBatchRetryToken or 0) + 1
    rosterInspectPendingGUID = nil
end
entryCreationKeyState.ClearRosterLoadRetryState = function()
    entryCreationKeyState.rosterLoadRetryDeadline = nil
    entryCreationKeyState.rosterLoadRetrySessionGen = nil
    entryCreationKeyState.rosterLoadRetryToken =
        (entryCreationKeyState.rosterLoadRetryToken or 0) + 1
end
entryCreationKeyState.ClearRosterCompositionChanged = function()
    entryCreationKeyState.rosterChangedSinceLastPayload = false
    entryCreationKeyState.rosterChangePreflightDeadline = nil
    entryCreationKeyState.rosterChangePreflightToken =
        (entryCreationKeyState.rosterChangePreflightToken or 0) + 1
end
entryCreationKeyState.MarkRosterCompositionChanged = function()
    entryCreationKeyState.rosterChangedSinceLastPayload = true
    local now = GetTime and GetTime() or 0
    local delay = entryCreationKeyState.ROSTER_CHANGE_PREFLIGHT_DEADLINE_S
    entryCreationKeyState.rosterChangePreflightDeadline = now + delay
    entryCreationKeyState.rosterChangePreflightToken =
        (entryCreationKeyState.rosterChangePreflightToken or 0) + 1
    local retryToken = entryCreationKeyState.rosterChangePreflightToken
    local retrySessionGen = sessionGen
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            if retryToken ~= entryCreationKeyState.rosterChangePreflightToken then
                return
            end
            if retrySessionGen ~= sessionGen then return end
            if not entryCreationKeyState.rosterChangedSinceLastPayload then return end
            if not (ApplicantScoutDB and ApplicantScoutDB.enabled) then return end
            if not isSessionActive then return end
            pendingShotDirty = true
            MarkDirty("rosterdeadline")
        end)
    end
end
entryCreationKeyState.ShouldDeferRosterChangeForPreflight = function()
    if not entryCreationKeyState.rosterChangedSinceLastPayload then return true end
    local deadline = entryCreationKeyState.rosterChangePreflightDeadline
    if not deadline then return false end
    local now = GetTime and GetTime() or 0
    return now < deadline
end
entryCreationKeyState.PrintRosterInspectBatchDiagnostics = function()
    local skippedInspectCount = 0
    if entryCreationKeyState.rosterInspectBatchSkippedGUIDs then
        for _ in pairs(entryCreationKeyState.rosterInspectBatchSkippedGUIDs) do
            skippedInspectCount = skippedInspectCount + 1
        end
    end
    local pendingInspectAge = "n/a"
    if rosterInspectPendingGUID and rosterInspectLastRequestTime > 0 then
        pendingInspectAge = string.format("%.1fs", GetTime() - rosterInspectLastRequestTime)
    end
    local retryText = "no"
    if entryCreationKeyState.rosterInspectBatchRetryDeadline then
        retryText = string.format(
            "yes (%.2fs)",
            math.max(0, entryCreationKeyState.rosterInspectBatchRetryDeadline - GetTime())
        )
    end
    local loadRetryText = "no"
    if entryCreationKeyState.rosterLoadRetryDeadline then
        loadRetryText = string.format(
            "yes (%.2fs)",
            math.max(0, entryCreationKeyState.rosterLoadRetryDeadline - GetTime())
        )
    end
    print("  roster inspect batch:")
    print("    batch pending: "
          .. tostring(entryCreationKeyState.rosterInspectBatchDirtyPending))
    print("    pending inspect: " .. tostring(rosterInspectPendingGUID ~= nil)
          .. " (age: " .. pendingInspectAge .. ")")
    print("    retry scheduled: " .. retryText)
    print("    combat deferred: "
          .. tostring(entryCreationKeyState.rosterInspectBatchCombatDeferred))
    print("    last block reason: "
          .. tostring(entryCreationKeyState.rosterInspectBatchLastBlockReason or "none"))
    print("    skipped count: " .. tostring(skippedInspectCount))
    print("    quiet full-party suppression: cached="
          .. tostring(entryCreationKeyState.lastQuietFullPartySignature ~= nil)
          .. ", payload="
          .. tostring(entryCreationKeyState.lastPayloadQuietFullPartySignature ~= nil))
    print("  roster load retry: " .. loadRetryText
          .. ", incomplete payload: "
          .. tostring(entryCreationKeyState.lastPayloadRosterIncomplete))
end
entryCreationKeyState.ScheduleRosterInspectBatchRetry = function(delay)
    if not (C_Timer and C_Timer.After) then return false end
    local now = GetTime and GetTime() or 0
    delay = SafeNumber(delay, 0)
    if delay < 0 then delay = 0 end
    local due = now + delay
    local existingDeadline = entryCreationKeyState.rosterInspectBatchRetryDeadline
    if existingDeadline
       and entryCreationKeyState.rosterInspectBatchRetrySessionGen == sessionGen
       and existingDeadline <= due then
        return true
    end
    entryCreationKeyState.rosterInspectBatchRetryToken =
        (entryCreationKeyState.rosterInspectBatchRetryToken or 0) + 1
    local retryToken = entryCreationKeyState.rosterInspectBatchRetryToken
    local retrySessionGen = sessionGen
    entryCreationKeyState.rosterInspectBatchRetryDeadline = due
    entryCreationKeyState.rosterInspectBatchRetrySessionGen = retrySessionGen
    C_Timer.After(delay, function()
        if retryToken ~= entryCreationKeyState.rosterInspectBatchRetryToken then
            return
        end
        if retrySessionGen ~= sessionGen then return end
        entryCreationKeyState.rosterInspectBatchRetryDeadline = nil
        entryCreationKeyState.rosterInspectBatchRetrySessionGen = nil
        if not (ApplicantScoutDB and ApplicantScoutDB.enabled) then return end
        if not isSessionActive then return end
        if entryCreationKeyState.rosterInspectBatchDirtyPending
           and not entryCreationKeyState.FlushOrContinueRosterInspectBatch() then
            MarkDirty("inspect")
        end
    end)
    return true
end
entryCreationKeyState.ScheduleRosterLoadRetry = function(delay)
    if not (C_Timer and C_Timer.After) then return false end
    local now = GetTime and GetTime() or 0
    delay = SafeNumber(delay, 0)
    if delay < 0 then delay = 0 end
    local due = now + delay
    local existingDeadline = entryCreationKeyState.rosterLoadRetryDeadline
    if existingDeadline
       and entryCreationKeyState.rosterLoadRetrySessionGen == sessionGen
       and existingDeadline <= due then
        return true
    end
    entryCreationKeyState.rosterLoadRetryToken =
        (entryCreationKeyState.rosterLoadRetryToken or 0) + 1
    local retryToken = entryCreationKeyState.rosterLoadRetryToken
    local retrySessionGen = sessionGen
    entryCreationKeyState.rosterLoadRetryDeadline = due
    entryCreationKeyState.rosterLoadRetrySessionGen = retrySessionGen
    C_Timer.After(delay, function()
        if retryToken ~= entryCreationKeyState.rosterLoadRetryToken then
            return
        end
        if retrySessionGen ~= sessionGen then return end
        entryCreationKeyState.rosterLoadRetryDeadline = nil
        entryCreationKeyState.rosterLoadRetrySessionGen = nil
        if not (ApplicantScoutDB and ApplicantScoutDB.enabled) then return end
        if not isSessionActive then return end
        pendingShotDirty = true
        MarkDirty("rosterload")
    end)
    return true
end

entryCreationKeyState.RosterUnitHasResolvedSpec = function(unit, guid)
    if UnitIsUnit and UnitIsUnit(unit, "player") then return true end
    if guid ~= "" then
        local cachedSpecID = _ClampUInt16(SafeNumber(rosterInspectSpecByGUID[guid], 0))
        if cachedSpecID > 0 then return true end
    end
    if GetInspectSpecialization then
        local ok, specID = pcall(GetInspectSpecialization, unit)
        specID = ok and _ClampUInt16(SafeNumber(specID, 0)) or 0
        if specID > 0 then
            if guid ~= "" then rosterInspectSpecByGUID[guid] = specID end
            return true
        end
    end
    return false
end

entryCreationKeyState.FlushOrContinueRosterInspectBatch = function()
    if not entryCreationKeyState.rosterInspectBatchDirtyPending then return true end

    local now = GetTime and GetTime() or 0
    if rosterInspectPendingGUID then
        if not _FindRosterUnitByGUID(rosterInspectPendingGUID) then
            local missingGUID = rosterInspectPendingGUID
            rosterInspectPendingGUID = nil
            entryCreationKeyState.rosterInspectBatchSkippedGUIDs =
                entryCreationKeyState.rosterInspectBatchSkippedGUIDs or {}
            entryCreationKeyState.rosterInspectBatchSkippedGUIDs[missingGUID] = true
        end
    end
    if rosterInspectPendingGUID then
        local timeoutLeft = ROSTER_INSPECT_TIMEOUT_S - (now - rosterInspectLastRequestTime)
        if timeoutLeft > 0 then
            return entryCreationKeyState.ScheduleRosterInspectBatchRetry(timeoutLeft)
        end
        local timedOutGUID = rosterInspectPendingGUID
        rosterInspectPendingGUID = nil
        entryCreationKeyState.rosterInspectBatchSkippedGUIDs =
            entryCreationKeyState.rosterInspectBatchSkippedGUIDs or {}
        entryCreationKeyState.rosterInspectBatchSkippedGUIDs[timedOutGUID] = true
    end

    local throttleLeft = ROSTER_INSPECT_THROTTLE_S - (now - rosterInspectLastRequestTime)
    if throttleLeft > 0 and rosterInspectLastRequestTime > 0 then
        if entryCreationKeyState.ScheduleRosterInspectBatchRetry(throttleLeft) then
            return true
        end
    end

    local requested = false
    local requestReason = nil
    _ForEachRosterUnit(function(unit)
        if not _UnitExistsForRoster(unit) then return false end
        local guid = _UnitGUIDForRoster(unit)
        if guid == ""
           or (entryCreationKeyState.rosterInspectBatchSkippedGUIDs
               and entryCreationKeyState.rosterInspectBatchSkippedGUIDs[guid])
           or entryCreationKeyState.RosterUnitHasResolvedInspectData(unit, guid) then
            return false
        end
        requested, requestReason = _MaybeRequestRosterInspect(unit, guid)
        return requested or requestReason == "combat"
    end)
    if requestReason == "combat" then
        entryCreationKeyState.rosterInspectBatchDirtyPending = true
        entryCreationKeyState.rosterInspectBatchCombatDeferred = true
        entryCreationKeyState.rosterInspectBatchLastBlockReason = "combat"
        return true
    end
    if requested then
        entryCreationKeyState.rosterInspectBatchCombatDeferred = false
        entryCreationKeyState.rosterInspectBatchLastBlockReason = nil
        entryCreationKeyState.ScheduleRosterInspectBatchRetry(ROSTER_INSPECT_TIMEOUT_S)
        return true
    end

    entryCreationKeyState.ClearRosterInspectBatchState()
    return false
end

entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot = function()
    local groupCount = math.floor(SafeNumber(GetNumGroupMembers and GetNumGroupMembers(), 0))
    if groupCount <= 0 or groupCount > 5 then return false end
    if IsInRaid and IsInRaid() then return false end
    if not entryCreationKeyState.rosterInspectBatchDirtyPending then
        local seeded = false
        _ForEachRosterUnit(function(unit)
            if not _UnitExistsForRoster(unit) then return false end
            local guid = _UnitGUIDForRoster(unit)
            if guid ~= ""
               and not entryCreationKeyState.RosterUnitHasResolvedInspectData(unit, guid) then
                entryCreationKeyState.rosterInspectBatchDirtyPending = true
                entryCreationKeyState.rosterInspectBatchSkippedGUIDs = nil
                entryCreationKeyState.rosterInspectBatchLastBlockReason = "preflight"
                seeded = true
                return true
            end
            return false
        end)
        if not seeded then return false end
    end
    return entryCreationKeyState.FlushOrContinueRosterInspectBatch()
end

local function _OnRosterInspectReady(guid)
    guid = SafeStr(guid, "")
    if guid == "" then
        guid = SafeStr(rosterInspectPendingGUID, "")
    end
    if guid == "" then return end

    local unit = _FindRosterUnitByGUID(guid)
    if not unit then
        if rosterInspectPendingGUID == guid then
            rosterInspectPendingGUID = nil
        end
        if entryCreationKeyState.rosterInspectBatchDirtyPending then
            if entryCreationKeyState.FlushOrContinueRosterInspectBatch() then
                return
            end
            MarkDirty("inspect")
        end
        return
    end
    if not GetInspectSpecialization then return end
    local ok, specID = pcall(GetInspectSpecialization, unit)
    specID = ok and _ClampUInt16(SafeNumber(specID, 0)) or 0
    local ilvl = entryCreationKeyState.ReadRosterInspectItemLevel(unit)
    local resolved = false
    if specID > 0 then
        rosterInspectSpecByGUID[guid] = specID
        resolved = true
    end
    if ilvl > 0 then
        entryCreationKeyState.rosterInspectIlvlByGUID[guid] = ilvl
        resolved = true
    end
    if resolved then
        if rosterInspectPendingGUID == guid then
            rosterInspectPendingGUID = nil
        end
        if ClearInspectPlayer then pcall(ClearInspectPlayer) end
        -- WHY: a freshly assembled group can resolve one inspected spec per
        -- callback. Batch follow-up inspect requests so the user sees one final
        -- QR refresh instead of a visible flash for every party member.
        entryCreationKeyState.rosterInspectBatchDirtyPending = true
        entryCreationKeyState.rosterInspectBatchSkippedGUIDs = nil
        if entryCreationKeyState.FlushOrContinueRosterInspectBatch() then
            return
        end
        MarkDirty("inspect")
    end
end

local function _UnitSpecIDForRoster(unit)
    local guid = _UnitGUIDForRoster(unit)
    if guid ~= "" then
        local cachedSpecID = _ClampUInt16(SafeNumber(rosterInspectSpecByGUID[guid], 0))
        if cachedSpecID > 0 then return cachedSpecID end
    end

    if UnitIsUnit and UnitIsUnit(unit, "player") then
        if GetSpecialization and GetSpecializationInfo then
            local okSpec, specIndex = pcall(GetSpecialization)
            specIndex = okSpec and math.floor(SafeNumber(specIndex, 0)) or 0
            if specIndex > 0 then
                local okInfo, specID = pcall(GetSpecializationInfo, specIndex)
                if okInfo then return _ClampUInt16(SafeNumber(specID, 0)) end
            end
        end
    end
    if GetInspectSpecialization then
        local ok, specID = pcall(GetInspectSpecialization, unit)
        specID = ok and _ClampUInt16(SafeNumber(specID, 0)) or 0
        if specID > 0 then
            if guid ~= "" then rosterInspectSpecByGUID[guid] = specID end
            return specID
        end
    end
    _MaybeRequestRosterInspect(unit, guid)
    return 0
end

local function _UnitItemLevelForRoster(unit)
    if not (UnitIsUnit and UnitIsUnit(unit, "player")) then
        local guid = _UnitGUIDForRoster(unit)
        if guid ~= "" then
            local cachedIlvl = entryCreationKeyState.CachedRosterInspectItemLevel(guid)
            if cachedIlvl > 0 then return cachedIlvl end

            local ilvl = entryCreationKeyState.ReadRosterInspectItemLevel(unit)
            if ilvl > 0 then
                entryCreationKeyState.rosterInspectIlvlByGUID[guid] = ilvl
                return ilvl
            end
            _MaybeRequestRosterInspect(unit, guid)
        end
        return 0
    end
    if not GetAverageItemLevel then return 0 end
    local ok, overall, equipped = pcall(GetAverageItemLevel)
    if not ok then return 0 end
    local ilvl = SafeNumber(equipped, 0)
    if ilvl <= 0 then ilvl = SafeNumber(overall, 0) end
    return _ClampUInt16(SafeRoundedNumber(ilvl, 0))
end

local function _UnitRoleTokenForRoster(unit, specID)
    local roleToken = ""
    if UnitGroupRolesAssigned then
        local ok, assigned = pcall(UnitGroupRolesAssigned, unit)
        if ok then roleToken = SafeEnumKey(assigned, "") end
    end
    if (roleToken == "" or roleToken == "NONE")
       and specID > 0 and GetSpecializationRoleByID then
        local ok, specRole = pcall(GetSpecializationRoleByID, specID)
        if ok then roleToken = SafeEnumKey(specRole, "") end
    end
    if roleToken == "TANK" or roleToken == "HEALER" or roleToken == "DAMAGER" then
        return roleToken
    end
    return "DAMAGER"
end

local function _UnitIsSelfForRoster(unit)
    return UnitIsUnit and UnitIsUnit(unit, "player") or false
end

local function _BuildRosterRow(unit, unitIndex, subgroup, isRaid)
    if not _UnitExistsForRoster(unit) then return nil end
    local name = _UnitFullNameForTransport(unit)
    if name == "" then return nil end
    local specID = _UnitSpecIDForRoster(unit)
    local roleToken = _UnitRoleTokenForRoster(unit, specID)
    local flags = 0
    if _UnitIsSelfForRoster(unit) then flags = flags + 1 end
    if isRaid then flags = flags + 2 end
    return {
        unitIndex = unitIndex,
        flags = flags,
        subgroup = subgroup,
        classID = _UnitClassIDForRoster(unit),
        specID = specID,
        ilvl = _UnitItemLevelForRoster(unit),
        role = ROLE_NAME_TO_BYTE[roleToken] or 2,
        name = name,
    }
end

entryCreationKeyState.GetLibKeystone = function()
    local libStub = _G and _G.LibStub
    if type(libStub) == "function" then
        local ok, lib = pcall(libStub, "LibKeystone", true)
        if ok
           and type(lib) == "table"
           and type(lib.Register) == "function"
           and type(lib.Request) == "function" then
            return lib
        end
    end
    return entryCreationKeyState.GetLibKeystoneShim()
end

entryCreationKeyState.RegisterLibKeystonePrefix = function()
    if entryCreationKeyState.libKeystonePrefixRegistered then return true end
    if not (C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function") then
        return false
    end
    local ok, result = pcall(function()
        return C_ChatInfo.RegisterAddonMessagePrefix("LibKS")
    end)
    if not ok then return false end
    if type(result) == "number" and result > 1 then return false end
    entryCreationKeyState.libKeystonePrefixRegistered = true
    return true
end

entryCreationKeyState.ReadOwnLibKeystoneInfo = function()
    local keyLevel, challengeMapID, playerRating = 0, 0, 0
    if C_MythicPlus then
        if type(C_MythicPlus.GetOwnedKeystoneLevel) == "function" then
            local ok, value = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
            if ok then keyLevel = math.floor(SafeNumber(value, 0)) end
        end
        if type(C_MythicPlus.GetOwnedKeystoneChallengeMapID) == "function" then
            local ok, value = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
            if ok then challengeMapID = math.floor(SafeNumber(value, 0)) end
        end
    end
    if C_PlayerInfo and type(C_PlayerInfo.GetPlayerMythicPlusRatingSummary) == "function" then
        local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
        summary = ok and SafeTable(summary) or nil
        playerRating = math.floor(SafeNumber(summary and summary.currentSeasonScore, 0))
    end
    return keyLevel, challengeMapID, playerRating
end

entryCreationKeyState.NotifyLibKeystoneShimCallbacks = function(keyLevel, challengeMapID, playerRating, playerName, channel)
    for _, callback in pairs(entryCreationKeyState.libKeystoneShimCallbacks) do
        if type(callback) == "function" then
            pcall(callback, keyLevel, challengeMapID, playerRating, playerName, channel)
        end
    end
end

entryCreationKeyState.SendLibKeystoneShimInfo = function(channel)
    if channel ~= "PARTY" then return false end
    if not (IsInGroup and IsInGroup()) then return false end
    if IsChatMessagingLockdown() then return false end
    if not entryCreationKeyState.RegisterLibKeystonePrefix() then return false end
    if not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then return false end
    local keyLevel, challengeMapID, playerRating = entryCreationKeyState.ReadOwnLibKeystoneInfo()
    local payload = string.format("%d,%d,%d", keyLevel, challengeMapID, playerRating)
    local ok, result = pcall(function()
        return C_ChatInfo.SendAddonMessage("LibKS", payload, channel)
    end)
    return ok and (result == nil or result == 0)
end

entryCreationKeyState.GetLibKeystoneShim = function()
    if entryCreationKeyState.libKeystoneShim then return entryCreationKeyState.libKeystoneShim end
    if not entryCreationKeyState.RegisterLibKeystonePrefix() then return nil end
    entryCreationKeyState.libKeystoneShim = {
        Register = function(owner, callback)
            if type(owner) ~= "table" or type(callback) ~= "function" then return end
            entryCreationKeyState.libKeystoneShimCallbacks[owner] = callback
        end,
        Request = function(channel)
            if channel ~= "PARTY" then return end
            local keyLevel, challengeMapID, playerRating =
                entryCreationKeyState.ReadOwnLibKeystoneInfo()
            local playerName = SafeStr(UnitNameUnmodified and UnitNameUnmodified("player"), "")
            entryCreationKeyState.NotifyLibKeystoneShimCallbacks(
                keyLevel,
                challengeMapID,
                playerRating,
                playerName,
                channel
            )
            if IsInGroup and IsInGroup() and not IsChatMessagingLockdown() then
                C_ChatInfo.SendAddonMessage("LibKS", "R", channel)
            end
        end,
    }
    return entryCreationKeyState.libKeystoneShim
end

entryCreationKeyState.LibKeystoneShimHandleAddonMessage = function(prefix, msg, channel, sender)
    if prefix ~= "LibKS" or channel ~= "PARTY" then return end
    if IsSecretValue(msg) or type(msg) ~= "string" then return end
    if msg == "R" then
        entryCreationKeyState.SendLibKeystoneShimInfo(channel)
        return
    end
    local keyLevelStr, challengeMapIDStr, playerRatingStr =
        msg:match("^(%d+),(%d+),(%d+)$")
    if not keyLevelStr then return end
    local playerName = SafeStr(Ambiguate and Ambiguate(sender, "none") or sender, "")
    entryCreationKeyState.NotifyLibKeystoneShimCallbacks(
        math.floor(SafeNumber(keyLevelStr, 0)),
        math.floor(SafeNumber(challengeMapIDStr, 0)),
        math.floor(SafeNumber(playerRatingStr, 0)),
        playerName,
        channel
    )
end

entryCreationKeyState.CanonicalPlayerName = function(name)
    name = SafeStr(name, "")
    if name == "" then return "", "" end
    local full = name
    local short = name:gsub("%-.+$", "")
    return full, short
end

entryCreationKeyState.PlayerNamesMatch = function(leftName, rightName)
    local leftFull, leftShort = entryCreationKeyState.CanonicalPlayerName(leftName)
    local rightFull, rightShort = entryCreationKeyState.CanonicalPlayerName(rightName)
    if leftFull == "" or rightFull == "" then return false end
    if leftFull == rightFull then return true end
    if not leftFull:find("-", 1, true) or not rightFull:find("-", 1, true) then
        return leftShort ~= "" and leftShort == rightShort
    end
    return false
end

entryCreationKeyState.CurrentPartyLeaderName = function()
    if not (UnitIsGroupLeader and _UnitExistsForRoster("player")) then return "" end
    if UnitIsGroupLeader("player") then return _UnitFullNameForTransport("player") end
    for i = 1, 4 do
        local unit = "party" .. i
        if _UnitExistsForRoster(unit) and UnitIsGroupLeader(unit) then
            return _UnitFullNameForTransport(unit)
        end
    end
    return ""
end

entryCreationKeyState.ClearLeaderKeystone = function()
    entryCreationKeyState.leaderKeystone = nil
end

entryCreationKeyState.OnLeaderKeystoneData = function(keyLevel, challengeMapID, _rating, playerName, channel)
    if channel ~= "PARTY" then return end
    local leaderName = entryCreationKeyState.CurrentPartyLeaderName()
    if leaderName == "" then return end
    if not entryCreationKeyState.PlayerNamesMatch(playerName, leaderName) then return end
    keyLevel = math.floor(SafeNumber(keyLevel, 0))
    challengeMapID = math.floor(SafeNumber(challengeMapID, 0))
    if keyLevel <= 0 then
        entryCreationKeyState.ClearLeaderKeystone()
        MarkDirty("leaderkey")
        return
    end
    entryCreationKeyState.leaderKeystone = {
        level = _ClampUInt8(keyLevel),
        challengeMapID = _ClampUInt16(challengeMapID),
        playerName = leaderName,
        at = GetTime and GetTime() or 0,
    }
    MarkDirty("leaderkey")
end

entryCreationKeyState.RegisterLeaderKeystoneCallback = function()
    if entryCreationKeyState.leaderKeystoneCallbackRegistered then
        return entryCreationKeyState.leaderKeystoneLib or entryCreationKeyState.GetLibKeystone()
    end
    local lib = entryCreationKeyState.GetLibKeystone()
    if not lib then return nil end
    local ok = pcall(function()
        lib.Register(
            entryCreationKeyState.leaderKeystoneCallbackOwner,
            entryCreationKeyState.OnLeaderKeystoneData
        )
    end)
    if not ok then return nil end
    entryCreationKeyState.leaderKeystoneCallbackRegistered = true
    entryCreationKeyState.leaderKeystoneLib = lib
    return lib
end

entryCreationKeyState.RequestLeaderKeystone = function(force)
    local lib = entryCreationKeyState.RegisterLeaderKeystoneCallback()
    if not lib or not (IsInGroup and IsInGroup()) then return end
    local now = GetTime and GetTime() or 0
    if not force
       and (now - SafeNumber(entryCreationKeyState.leaderKeystoneLastRequestAt, 0))
           < entryCreationKeyState.LEADER_KEY_REQUEST_THROTTLE_S then
        return
    end
    entryCreationKeyState.leaderKeystoneLastRequestAt = now
    pcall(function() lib.Request("PARTY") end)
end

entryCreationKeyState.ResolveLeaderKeystoneContext = function()
    local leaderKeystone = entryCreationKeyState.leaderKeystone
    if type(leaderKeystone) ~= "table" then return nil end
    local leaderName = entryCreationKeyState.CurrentPartyLeaderName()
    if leaderName == ""
       or not entryCreationKeyState.PlayerNamesMatch(leaderKeystone.playerName, leaderName) then
        entryCreationKeyState.ClearLeaderKeystone()
        return nil
    end
    local now = GetTime and GetTime() or 0
    if now > 0
       and (now - SafeNumber(leaderKeystone.at, 0)) > entryCreationKeyState.LEADER_KEY_TTL_S then
        entryCreationKeyState.ClearLeaderKeystone()
        return nil
    end
    return leaderKeystone
end

local function _RaidSubgroupForRoster(index)
    if not GetRaidRosterInfo then return 1 end
    local ok, _name, _rank, subgroup = pcall(GetRaidRosterInfo, index)
    if not ok then return 1 end
    return _ClampUInt8(SafeNumber(subgroup, 1))
end

local function BuildRosterPayloadRows(listingActivityIDForRio, listingKeyLevelForRio)
    local rosterOut = {}
    local emittedCount = 0
    local rows = {}
    local rosterQuietOut = {}
    local rosterQuietHasUnknownSpec = false
    local groupCount = math.floor(SafeNumber(GetNumGroupMembers and GetNumGroupMembers(), 0))
    local inRaid = IsInRaid and IsInRaid() or false
    local expectedRosterCount = 0
    if groupCount <= 0 then
        return rosterOut, emittedCount, "", false, inRaid, false
    end

    if inRaid then
        if groupCount > 40 then groupCount = 40 end
        expectedRosterCount = groupCount
        for i = 1, groupCount do
            local row = _BuildRosterRow(
                "raid" .. i,
                i,
                _RaidSubgroupForRoster(i),
                true
            )
            if row then table.insert(rows, row) end
        end
    else
        expectedRosterCount = groupCount
        if expectedRosterCount > 5 then expectedRosterCount = 5 end
        local playerRow = _BuildRosterRow("player", 1, 1, false)
        if playerRow then table.insert(rows, playerRow) end
        for i = 1, 4 do
            local unit = "party" .. i
            local row = _BuildRosterRow(unit, i + 1, 1, false)
            if row then table.insert(rows, row) end
        end
    end

    table.sort(rows, function(a, b)
        if a.subgroup ~= b.subgroup then return a.subgroup < b.subgroup end
        return a.unitIndex < b.unitIndex
    end)

    for _, row in ipairs(rows) do
        local rioSummary = _GetRaiderIOMPlusSummary(
            _RaiderIOProfileLookupName(row.name),
            listingActivityIDForRio,
            listingKeyLevelForRio
        )
        local currentScoreBytes = _Uint16BE(rioSummary.currentScore)
        local mainScoreBytes = _Uint16BE(rioSummary.mainScore)
        table.insert(rosterOut, string.char(_ClampUInt8(row.unitIndex)))
        table.insert(rosterOut, string.char(_ClampUInt8(row.flags)))
        table.insert(rosterOut, string.char(_ClampUInt8(row.subgroup)))
        table.insert(rosterOut, string.char(_ClampUInt8(row.classID)))
        table.insert(rosterOut, _Uint16BE(row.specID))
        table.insert(rosterOut, _Uint16BE(row.ilvl))
        table.insert(rosterOut, currentScoreBytes)
        table.insert(rosterOut, mainScoreBytes)
        table.insert(rosterOut, string.char(rioSummary.hasProfile and 1 or 0))
        table.insert(rosterOut, string.char(rioSummary.bestKey))
        table.insert(rosterOut, string.char(rioSummary.bestDungeonKey))
        table.insert(rosterOut, string.char(rioSummary.timedAtOrAbove))
        table.insert(rosterOut, string.char(rioSummary.timedAtOrAboveMinus1))
        table.insert(rosterOut, string.char(rioSummary.timedAtOrAboveMinus2))
        table.insert(rosterOut, string.char(rioSummary.completedAtOrAboveMinus1))
        table.insert(rosterOut, string.char(rioSummary.dungeonCount))
        table.insert(rosterOut, string.char(_ClampUInt8(row.role)))
        _PackLenStr(rosterOut, row.name)
        emittedCount = emittedCount + 1
        if row.specID <= 0 then rosterQuietHasUnknownSpec = true end
        table.insert(rosterQuietOut, string.char(_ClampUInt8(row.unitIndex)))
        table.insert(rosterQuietOut, string.char(_ClampUInt8(row.flags)))
        table.insert(rosterQuietOut, string.char(_ClampUInt8(row.subgroup)))
        table.insert(rosterQuietOut, string.char(_ClampUInt8(row.classID)))
        table.insert(rosterQuietOut, _Uint16BE(row.specID))
        table.insert(rosterQuietOut, _Uint16BE(row.ilvl))
        table.insert(rosterQuietOut, currentScoreBytes)
        table.insert(rosterQuietOut, mainScoreBytes)
        table.insert(rosterQuietOut, string.char(rioSummary.hasProfile and 1 or 0))
        table.insert(rosterQuietOut, string.char(rioSummary.bestKey))
        table.insert(rosterQuietOut, string.char(rioSummary.bestDungeonKey))
        table.insert(rosterQuietOut, string.char(rioSummary.timedAtOrAbove))
        table.insert(rosterQuietOut, string.char(rioSummary.timedAtOrAboveMinus1))
        table.insert(rosterQuietOut, string.char(rioSummary.timedAtOrAboveMinus2))
        table.insert(rosterQuietOut, string.char(rioSummary.completedAtOrAboveMinus1))
        table.insert(rosterQuietOut, string.char(rioSummary.dungeonCount))
        table.insert(rosterQuietOut, string.char(_ClampUInt8(row.role)))
        _PackLenStr(rosterQuietOut, row.name)
    end

    local rosterIncomplete = emittedCount < expectedRosterCount
        or (not inRaid and rosterQuietHasUnknownSpec)
    return rosterOut, emittedCount, table.concat(rosterQuietOut),
           rosterQuietHasUnknownSpec, inRaid, rosterIncomplete
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
local function BuildPayload(entry, applicantIDs, terminalClear)
    local out = {}
    entryCreationKeyState.lastPayloadQuietFullPartySignature = nil
    entryCreationKeyState.lastPayloadApplicantCount = 0
    entryCreationKeyState.lastPayloadRosterIncomplete = false

    -- Header (length patched after we know body size)
    table.insert(out, "APS1")
    table.insert(out, string.char(0x07))    -- protocol version (v7: leader key block)
    table.insert(out, "\0\0")                -- length placeholder (uint16 BE)
    table.insert(out, "\0\0")                -- reserved

    -- Listing block
    local cleanEntry = SafeTable(entry)
    local leaderKeystone = entryCreationKeyState.ResolveLeaderKeystoneContext()
    local listingActivityIDForRio = 0
    local listingKeyLevelForRio = 0
    local listingQuietSignature = nil
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

        local questID = math.floor(SafeNumber(cleanEntry.questID, 0))
        if questID < 0 then questID = 0 end

        local activityInfo = _GetActivityInfoForListing(activityID, questID)

        local dungeonName = "?"
        local categoryID = 0
        local difficultyID = 0
        if activityInfo then
            dungeonName = _ActivityInfoListingName(activityInfo)
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
            keyLevel = _GetListingKeystoneLevel(
                activityID,
                questID,
                listingName,
                listingComment,
                activityInfo
            )
            local ownedActivityID, _ownedGroupID, ownedLevel, ownedInfo =
                _GetOwnedKeystoneListingInfo()
            local shouldUseOwnedKeystone = ownedLevel > 0
                and ownedActivityID > 0
                and ownedInfo
                and entryCreationKeyState.CanUseOwnedKeystoneForListingFallback()
                and (ownedActivityID == activityID
                    or dungeonName == "Mythic+"
                    or dungeonName == "?")
            if keyLevel == 0 and shouldUseOwnedKeystone then
                keyLevel = ownedLevel
            end
            if shouldUseOwnedKeystone then
                activityID = ownedActivityID
                activityInfo = ownedInfo
                dungeonName = _ActivityInfoListingName(activityInfo)
                categoryID = math.floor(SafeNumber(activityInfo.categoryID, categoryID))
                difficultyID = math.floor(SafeNumber(activityInfo.difficultyID, difficultyID))
            end
            if leaderKeystone and leaderKeystone.level > 0 then
                keyLevel = leaderKeystone.level
            end
        end
        listingActivityIDForRio = activityID
        listingKeyLevelForRio = keyLevel
        local listingQuietOut = {}
        table.insert(listingQuietOut, _Uint32BE(activityID))
        table.insert(listingQuietOut, _Uint32BE(questID))
        table.insert(listingQuietOut, _Uint16BE(categoryID))
        table.insert(listingQuietOut, _Uint16BE(difficultyID))
        table.insert(listingQuietOut, string.char(math.min(keyLevel, 255)))
        _PackLenStr(listingQuietOut, dungeonName)
        _PackLenStr(listingQuietOut, listingName)
        _PackLenStr(listingQuietOut, listingComment)
        listingQuietSignature = table.concat(listingQuietOut)

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

    if leaderKeystone and leaderKeystone.level > 0 then
        if listingKeyLevelForRio <= 0 then
            listingKeyLevelForRio = leaderKeystone.level
        end
        table.insert(out, string.char(1))
        table.insert(out, string.char(_ClampUInt8(leaderKeystone.level)))
        table.insert(out, _Uint16BE(leaderKeystone.challengeMapID))
        _PackLenStr(out, leaderKeystone.playerName)
    else
        table.insert(out, string.char(0))
    end

    -- Applicants — filter out DEAD_STATUSES + sort by ID for hash stability
    local validApps = {}
    local cleanApplicantIDs = SafeTable(applicantIDs) or {}
    for _, rawID in ipairs(cleanApplicantIDs) do
        local id = math.floor(SafeNumber(rawID, 0))
        if id > 0 then
            local info = C_LFGList.GetApplicantInfo(id)
            info = SafeTable(info)
            if info then
                local status = _GetApplicantApplicationStatus(info)
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
    -- Per-block byte layout (v5):
    --   uint32 applicant_id, u8 member_idx (1-based), u8 class_id,
    --   u16 spec_id, u16 ilvl, u16 score, u16 main_score,
    --   u8 rio_profile, u8 rio_best_key, u8 rio_best_dungeon_key,
    --   u8 rio_timed_at_or_above, u8 rio_timed_at_or_above_minus1,
    --   u8 rio_timed_at_or_above_minus2, u8 rio_completed_at_or_above_minus1,
    --   u8 rio_dungeon_count, u8 role, len-prefixed name.
    local memberOut = {}
    local emittedCount = 0
    for _, app in ipairs(validApps) do
        for m = 1, app.members do
            local name, class, _, _, ilvl, _, _, _, _, role, _, score, _, _, _, specID
                = C_LFGList.GetApplicantMemberInfo(app.id, m)
            local memberName = SafeStr(name, "")
            if memberName ~= "" and memberName ~= "?" then
                local classToken = SafeEnumKey(class, "")
                local roleToken = SafeEnumKey(role, "DAMAGER")
                table.insert(memberOut, _Uint32BE(app.id))
                table.insert(memberOut, string.char(m))
                table.insert(memberOut, string.char(CLASS_NAME_TO_ID[classToken] or 0))
                table.insert(memberOut, _Uint16BE(SafeNumber(specID, 0)))
                table.insert(memberOut, _Uint16BE(SafeRoundedNumber(ilvl, 0)))
                table.insert(memberOut, _Uint16BE(_ClampUInt16(SafeRoundedNumber(score, 0))))
                local rioSummary = _GetRaiderIOMPlusSummary(
                    _RaiderIOProfileLookupName(memberName),
                    listingActivityIDForRio,
                    listingKeyLevelForRio
                )
                table.insert(memberOut, _Uint16BE(rioSummary.mainScore))
                table.insert(memberOut, string.char(rioSummary.hasProfile and 1 or 0))
                table.insert(memberOut, string.char(rioSummary.bestKey))
                table.insert(memberOut, string.char(rioSummary.bestDungeonKey))
                table.insert(memberOut, string.char(rioSummary.timedAtOrAbove))
                table.insert(memberOut, string.char(rioSummary.timedAtOrAboveMinus1))
                table.insert(memberOut, string.char(rioSummary.timedAtOrAboveMinus2))
                table.insert(memberOut, string.char(rioSummary.completedAtOrAboveMinus1))
                table.insert(memberOut, string.char(rioSummary.dungeonCount))
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
    entryCreationKeyState.lastPayloadApplicantCount = emittedCount

    local rosterOut, rosterCount = {}, 0
    local rosterIncomplete = false
    local rosterQuietSignature, rosterQuietHasUnknownSpec, rosterQuietInRaid =
        nil, false, false
    if not terminalClear then
        rosterOut, rosterCount, rosterQuietSignature,
        rosterQuietHasUnknownSpec, rosterQuietInRaid, rosterIncomplete =
            BuildRosterPayloadRows(
                listingActivityIDForRio,
                listingKeyLevelForRio
            )
    end
    entryCreationKeyState.lastPayloadRosterIncomplete = rosterIncomplete
    if cleanEntry and #validApps == 0
       and rosterCount == 5
       and rosterQuietSignature
       and not rosterQuietInRaid
       and not rosterQuietHasUnknownSpec then
        local quietOut = {}
        local listingSig = listingQuietSignature or ""
        table.insert(quietOut, _Uint16BE(#listingSig))
        table.insert(quietOut, listingSig)
        table.insert(quietOut, _Uint16BE(#rosterQuietSignature))
        table.insert(quietOut, rosterQuietSignature)
        entryCreationKeyState.lastPayloadQuietFullPartySignature = table.concat(quietOut)
    end
    table.insert(out, _Uint16BE(rosterCount))
    for _, chunk in ipairs(rosterOut) do
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

if type(_G.ApplicantScoutFixtureHarness) == "table" then
    _G.ApplicantScoutFixtureHarness.BuildPayload = BuildPayload
    _G.ApplicantScoutFixtureHarness.HashSnapshot = HashSnapshot
end

-- Resolve QR encoder reference (set by libs/qrencode.lua via addon namespace).
-- Nil-safe so BuildQRMatrix can show its missing-library diagnostic instead of
-- crashing at file load if the embedded QR library failed to populate ns.QR.
local _, _addonNS = ...
local _qrencode = _addonNS.QR and _addonNS.QR.qrcode

-- Acquire (or reuse from pool) a black-rectangle texture and position+size it.
-- Returns the texture or nil if pool exhausted (caller logs warning).
-- Pool grows as needed; never shrinks. Excess textures from prior larger QRs
-- are hidden, not destroyed (cheap reuse on next render).
local QR_TEXTURE_HARD_CAP = 10000  -- safety against runaway texture creation
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

local function _CountQRBlackRuns(matrix)
    local runs = 0
    for y = 1, #matrix do
        local row = matrix[y]
        local inRun = false
        for x = 1, #row do
            local isBlack = (row[x] or 0) > 0
            if isBlack then
                if not inRun then
                    runs = runs + 1
                    inRun = true
                end
            else
                inRun = false
            end
        end
    end
    return runs
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
-- transport ladder keeps the historical hex/M path first so already-working
-- payloads keep backward compatibility with legacy companions. Once hex/M
-- fails, prefer raw byte-mode before hex/L: raw usually produces a smaller QR
-- and fewer row-RLE textures, while current companions understand embedded NUL
-- bytes. Hex/L stays as a last fallback for edge cases where raw encode fails.
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
        { kind = "raw", data = payload, ec_level = QR_EC_LEVEL, size = #payload, unit = "bytes" },
    }
    if QR_EC_LEVEL ~= 1 then
        table.insert(attempts, { kind = "raw", data = payload, ec_level = 1, size = #payload, unit = "bytes" })
        table.insert(attempts, { kind = "hex", data = hex, ec_level = 1, size = #hex, unit = "hex" })
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
            local renderRuns = _CountQRBlackRuns(matrix)
            if renderRuns > QR_TEXTURE_HARD_CAP then
                failure_parts[#failure_parts + 1] = label .. ": render needs " ..
                    renderRuns .. " textures > cap " .. QR_TEXTURE_HARD_CAP
            else
                _SetLastQREncodeDiag(label, #payload, nil)
                if APSPrint and ApplicantScoutDB and ApplicantScoutDB.debug and label ~= first_label then
                    APSPrint(string.format(
                        "[APS-debug] QR fallback %s (%d %s) -> %s (%d bytes payload, %d textures)",
                        first_label, first_size, first_unit, label, #payload, renderRuns))
                end
                return matrix
            end
        else
            failure_parts[#failure_parts + 1] = label .. ": " .. tostring(err)
        end
    end

    -- All strategies failed. Caller (MaybeTriggerScreenshot) gets nil → skips
    -- paint + screenshot for this snapshot. Next scan will rebuild a (hopefully
    -- smaller) payload and retry. Logged once per failure (not per scan-tick —
    -- caller dedupes via lastSnapshotHash unless force=true).
    local err = table.concat(failure_parts, " | ")
    _SetLastQREncodeDiag("failed", #payload, err)
    if APSPrint then
        APSPrint("QR build failed (payload too large or too dense to render): "
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
qrForceVisibleForShot = false
qrForceVisibleShotGen = 0
local SHOT_THROTTLE_S = 0.5
local TRANSPORT_POLL_S = 2.0
local lastTransportPollTime = 0

local function _ReleaseForceVisibleShotLease(forceVisibleShotGen)
    if forceVisibleShotGen and qrForceVisibleShotGen == forceVisibleShotGen then
        qrForceVisibleForShot = false
        _RefreshQRVisibility()
    end
end

local function _AcquireQRShotLease()
    local wasVisible = _IsQRVisibleForScreenshot()
    if qrAlwaysVisible or qrMoveMode then
        _RefreshQRVisibility()
        return nil, wasVisible and 0 or QR_RENDER_SETTLE_S
    end
    qrForceVisibleForShot = true
    qrForceVisibleShotGen = (qrForceVisibleShotGen or 0) + 1
    local forceVisibleShotGen = qrForceVisibleShotGen
    _RefreshQRVisibility()
    return forceVisibleShotGen, wasVisible and 0 or QR_RENDER_SETTLE_S
end

-- Build payload, dedup vs last hash, throttle, paint QR, trigger Screenshot.
-- force=true bypasses dedup AND throttle (used by EndSession + /apscout shotnow).
-- entryHint: optional pre-fetched C_LFGList.GetActiveEntryInfo() result from
-- the scan-tick caller — avoids a second API call per scan. nil falls back
-- to fetching here (force-shot from EndSession / /apscout shotnow).
-- QR paints for a short visibility lease, then Screenshot runs after the render
-- settle window; manual debug/move modes can keep the frame visible outside it.
MaybeTriggerScreenshot = function(force, entryHint, terminalClear)
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

    -- Interaction-hidden QR should not produce or dedupe a payload. Keep the
    -- latest state pending and let the scan ticker emit once the interaction
    -- frame closes; force shots still bypass for EndSession cleanup and
    -- explicit support commands.
    if not force and _qrSuppressedByInteraction then
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
    if not force
       and #applicantIDs == 0
       and entryCreationKeyState.lastEmittedApplicantCount == 0
       and entryCreationKeyState.ShouldDeferRosterChangeForPreflight()
       and entryCreationKeyState.EnsureRosterInspectBatchBeforeSnapshot()
       and not entryCreationKeyState.rosterInspectBatchCombatDeferred then
        pendingShotDirty = true
        return
    end

    local payload = BuildPayload(entry, applicantIDs, terminalClear)

    local h = HashSnapshot(payload)
    if not force and h == lastSnapshotHash then
        if entryCreationKeyState.lastPayloadRosterIncomplete then
            if entryCreationKeyState.ScheduleRosterLoadRetry(SHOT_THROTTLE_S) then
                pendingShotDirty = false
            else
                pendingShotDirty = true
            end
        else
            pendingShotDirty = false  -- nothing new to render for same hash
            entryCreationKeyState.ClearRosterLoadRetryState()
        end
        entryCreationKeyState.ClearRosterCompositionChanged()
        return
    end

    local now = GetTime()
    if not force and now - lastShotTime < SHOT_THROTTLE_S then
        pendingShotDirty = true
        return
    end
    local quietSignature = entryCreationKeyState.lastPayloadQuietFullPartySignature
    if not force and quietSignature then
        if entryCreationKeyState.lastQuietFullPartySignature == quietSignature then
            lastSnapshotHash = h
            pendingShotDirty = false
            entryCreationKeyState.ClearRosterLoadRetryState()
            entryCreationKeyState.ClearRosterCompositionChanged()
            return
        end
    else
        entryCreationKeyState.lastQuietFullPartySignature = nil
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

    if not force and quietSignature then
        entryCreationKeyState.lastQuietFullPartySignature = quietSignature
    end
    local forceVisibleShotGen, forceVisibleShotDelay = _AcquireQRShotLease()

    entryCreationKeyState.lastEmittedApplicantCount =
        entryCreationKeyState.lastPayloadApplicantCount
    entryCreationKeyState.ClearRosterCompositionChanged()
    lastSnapshotHash = h
    lastShotTime = now
    pendingShotDirty = false
    if not force and entryCreationKeyState.lastPayloadRosterIncomplete then
        if entryCreationKeyState.ScheduleRosterLoadRetry(SHOT_THROTTLE_S) then
            pendingShotDirty = false
        else
            pendingShotDirty = true
        end
    else
        entryCreationKeyState.ClearRosterLoadRetryState()
    end

    -- PaintQR above just updated the textures. If the frame was hidden, the
    -- visibility lease waits QR_RENDER_SETTLE_S so Show()+texture updates reach
    -- the GPU framebuffer before capture. If it was already visible (debug/move
    -- mode or overlapping shot lease), C_Timer.After(0) still gives the fresh
    -- texture set one render pass before Screenshot().
    C_Timer.After(forceVisibleShotDelay, function()
        if ApplicantScoutDB and ApplicantScoutDB.debug then
            print(string.format("|cff999999[APS-debug]|r CAP qr_size=%dpx hash=%x t=%.2f",
                  qrCurrentSize, h, GetTime()))
        end
        Screenshot()
        if forceVisibleShotGen then
            C_Timer.After(0.05, function()
                _ReleaseForceVisibleShotLease(forceVisibleShotGen)
            end)
        end
    end)

    if ApplicantScoutDB and ApplicantScoutDB.debug then
        print(string.format("|cff999999[APS-debug]|r SHOT bytes=%d apps=%d hash=%x",
              #payload, #applicantIDs, h))
    end
end

-- ───────────────────────────────────────────────────────────
-- LFG entry creation: default Mythic+ playstyle
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

_MaybeAutoSelectDefaultPlaystyle = function(panel, reason)
    if not (ApplicantScoutDB and ApplicantScoutDB.enabled) then
        return false
    end

    local configuredPlaystyle, token = _GetConfiguredMPlusPlaystyleEnum()
    if configuredPlaystyle == nil then return false end

    if not panel or lfgDefaultPlaystyleTouchedPanels[panel] then return false end

    local isEditMode = _G.LFGListEntryCreation_IsEditMode
    if type(isEditMode) ~= "function" or isEditMode(panel) then return false end

    local activityID = panel.selectedActivity
    if IsSecretValue(activityID) or activityID == nil then return false end
    if not (C_LFGList and C_LFGList.GetActivityInfoTable) then return false end

    local activityInfo = SafeTable(C_LFGList.GetActivityInfoTable(activityID))
    if not activityInfo then return false end
    if IsSecretValue(activityInfo.isMythicPlusActivity)
       or activityInfo.isMythicPlusActivity ~= true then
        return false
    end

    local currentPlaystyle = panel.generalPlaystyle
    if IsSecretValue(currentPlaystyle) then return false end
    if currentPlaystyle == configuredPlaystyle then return true end

    lfgDefaultPlaystyleApplying = true
    local ok, err = pcall(function()
        panel.generalPlaystyle = configuredPlaystyle

        local updateValidState = _G.LFGListEntryCreation_UpdateValidState
        if type(updateValidState) == "function" then
            updateValidState(panel)
        end

        local dropdown = panel.PlayStyleDropdown
        if dropdown and type(dropdown.GenerateMenu) == "function" then
            dropdown:GenerateMenu()
        end
    end)
    lfgDefaultPlaystyleApplying = false
    if not ok then
        if ApplicantScoutDB.debug then
            print("|cff999999[APS-debug]|r LFG default playstyle failed: "
                  .. tostring(err))
        end
        return false
    end

    if ApplicantScoutDB.debug then
        print("|cff999999[APS-debug]|r LFG default playstyle applied: "
              .. _GetAutoMPlusPlaystyleLabel(token)
              .. (reason and (" (" .. reason .. ")") or ""))
    end
    return true
end

_SetupLFGEntryCreationKeyCapture = function()
    if lfgEntryCreationKeyCaptureState.hooksSetup or lfgEntryCreationKeyCaptureState.hookError then
        return lfgEntryCreationKeyCaptureState.hooksSetup
    end

    local hook = _G.hooksecurefunc
    local selectFn = _G.LFGListEntryCreation_Select
    local showFn = _G.LFGListEntryCreation_Show
    local setEditModeFn = _G.LFGListEntryCreation_SetEditMode
    if type(hook) ~= "function"
       or type(selectFn) ~= "function"
       or type(showFn) ~= "function"
       or type(setEditModeFn) ~= "function" then
        return false
    end

    local ok, err = pcall(function()
        hook("LFGListEntryCreation_Select", function(panel)
            _HookEntryCreationKeyCapture(panel)
        end)
        hook("LFGListEntryCreation_Show", function(panel)
            _HookEntryCreationKeyCapture(panel)
        end)
        hook("LFGListEntryCreation_SetEditMode", function(panel)
            _HookEntryCreationKeyCapture(panel)
        end)
    end)

    if not ok then
        lfgEntryCreationKeyCaptureState.hookError = tostring(err)
        if ApplicantScoutDB and ApplicantScoutDB.debug then
            print("|cff999999[APS-debug]|r LFG key capture hook failed: "
                  .. lfgEntryCreationKeyCaptureState.hookError)
        end
        return false
    end

    lfgEntryCreationKeyCaptureState.hooksSetup = true
    local frame = _G.LFGListFrame
    if frame and frame.EntryCreation then
        _HookEntryCreationKeyCapture(frame.EntryCreation)
    end
    return true
end

_SetupLFGDefaultPlaystyle = function()
    if lfgDefaultPlaystyleHooksSetup or lfgDefaultPlaystyleHookError then
        return lfgDefaultPlaystyleHooksSetup
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
            _MaybeAutoSelectDefaultPlaystyle(panel, "select")
        end)
        hook("LFGListEntryCreation_Show", function(panel)
            if panel then lfgDefaultPlaystyleTouchedPanels[panel] = nil end
            _MaybeAutoSelectDefaultPlaystyle(panel, "show")
        end)
        hook("LFGListEntryCreation_SetEditMode", function(panel, editMode)
            if not editMode then
                _MaybeAutoSelectDefaultPlaystyle(panel, "create-mode")
            end
        end)
        hook("LFGListEntryCreation_OnPlayStyleSelectedInternal", function(panel)
            if panel and not lfgDefaultPlaystyleApplying then
                lfgDefaultPlaystyleTouchedPanels[panel] = true
            end
        end)
    end)

    if not ok then
        lfgDefaultPlaystyleHookError = tostring(err)
        if ApplicantScoutDB and ApplicantScoutDB.debug then
            print("|cff999999[APS-debug]|r LFG default playstyle hook failed: "
                  .. lfgDefaultPlaystyleHookError)
        end
        return false
    end

    lfgDefaultPlaystyleHooksSetup = true
    local frame = _G.LFGListFrame
    if frame and frame.EntryCreation then
        _MaybeAutoSelectDefaultPlaystyle(frame.EntryCreation, "setup")
    end
    return true
end

local EVENT_HANDLERS = {
    PLAYER_LOGIN                     = function()
        InitDB()
        entryCreationKeyState.SyncAutoHiInitialGroupState()
        MarkDirty("login")
        _AttachSettingsPanel()
        _SetupPVEFrameMovement()  -- no-ops if BlizzMove loaded OR PVEFrame missing
        _SetupLFGEntryCreationKeyCapture() -- no-ops until Blizzard LFG globals exist
        _SetupLFGDefaultPlaystyle() -- no-ops until Blizzard LFG globals exist
        _TryHookInfoPanels()      -- initial scan; ADDON_LOADED catches LoD frames later
    end,
    PLAYER_ENTERING_WORLD            = function()
        CreateQRFrame()
        entryCreationKeyState.SyncAutoHiInitialGroupState()
        entryCreationKeyState.RequestLeaderKeystone(true)
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
        _SetupLFGEntryCreationKeyCapture()
        _SetupLFGDefaultPlaystyle()
        _TryHookInfoPanels()
        entryCreationKeyState.RequestLeaderKeystone(false)
    end,
    -- WHY persist on logout (Phase 2): PLAYER_LOGOUT fires after UI teardown
    -- begins but BEFORE SavedVariables flush. Drag-stop covers obvious paths;
    -- this catches positions changed via slash macros / scripted moves /
    -- third-party UI that bypasses our drag handlers.
    PLAYER_LOGOUT                    = function()
        if PVEFrame and PVEFrame:IsUserPlaced() and ApplicantScoutDB then
            _SavePVEFramePositionFromFrame(PVEFrame)
        end
    end,
    LFG_LIST_APPLICANT_LIST_UPDATED  = function() MarkDirty("listupd") end,
    LFG_LIST_APPLICANT_UPDATED       = function() MarkDirty("appupd") end,
    LFG_LIST_ACTIVE_ENTRY_UPDATE     = function()
        entryCreationKeyState.activeListingMaybeChanged = true
        MarkDirty("entryupd")
    end,
    PARTY_LEADER_CHANGED             = function()
        entryCreationKeyState.ClearLeaderKeystone()
        entryCreationKeyState.RequestLeaderKeystone(true)
        MarkDirty("ldrchg")
    end,
    GROUP_ROSTER_UPDATE              = function()
        entryCreationKeyState.MarkRosterCompositionChanged()
        MarkDirty("roster")
        entryCreationKeyState.RequestLeaderKeystone(false)
        entryCreationKeyState.ScheduleAutoHiIfGroupJoined()
        entryCreationKeyState.ScheduleAutoHiForNewPartyMembers()
    end,
    GROUP_LEFT                       = function()
        entryCreationKeyState.ClearLeaderKeystone()
        entryCreationKeyState.MarkRosterCompositionChanged()
        MarkDirty("groupleft")
        entryCreationKeyState.ScheduleAutoHiIfGroupJoined()
        entryCreationKeyState.ScheduleAutoHiForNewPartyMembers()
    end,
    CHAT_MSG_ADDON                  = function(_, prefix, msg, channel, sender)
        entryCreationKeyState.LibKeystoneShimHandleAddonMessage(prefix, msg, channel, sender)
    end,
    PLAYER_SPECIALIZATION_CHANGED      = function(_, unit)
        _InvalidateRosterSpecCacheForUnit(unit)
        MarkDirty("spec")
    end,
    PLAYER_REGEN_ENABLED              = function()
        if entryCreationKeyState.rosterInspectBatchCombatDeferred then
            entryCreationKeyState.rosterInspectBatchCombatDeferred = false
            if not entryCreationKeyState.FlushOrContinueRosterInspectBatch() then
                MarkDirty("inspect")
            end
        end
    end,
    INSPECT_READY                    = function(_, guid)
        _OnRosterInspectReady(guid)
    end,
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
    local now = GetTime()
    if not (scanDirty and ApplicantScoutDB and ApplicantScoutDB.enabled) then
        -- Drain pending throttled shot: data was changed during throttle
        -- window (pendingShotDirty=true), but no new events fired since.
        -- Without this drain: shot never goes out for sustained state.
        if pendingShotDirty and (now - lastShotTime) >= SHOT_THROTTLE_S then
            if not IsChatMessagingLockdown() then
                MaybeTriggerScreenshot()
            end
        end
        if ApplicantScoutDB and ApplicantScoutDB.enabled
           and (now - lastTransportPollTime) >= TRANSPORT_POLL_S
           and not IsChatMessagingLockdown() then
            lastTransportPollTime = now
            local entry = CheckSessionTransition()
            if isSessionActive then
                -- WHY: QR screenshots can be missed by the companion, and a
                -- hash-identical active party/listing would otherwise never
                -- resend until the next roster/applicant event.
                if (now - entryCreationKeyState.lastTransportHeartbeatAttemptTime)
                       >= entryCreationKeyState.TRANSPORT_HEARTBEAT_S
                   and (lastShotTime <= 0
                        or (now - lastShotTime) >= entryCreationKeyState.TRANSPORT_HEARTBEAT_S) then
                    lastSnapshotHash = nil
                    entryCreationKeyState.lastTransportHeartbeatAttemptTime = now
                end
                MaybeTriggerScreenshot(false, entry)
            end
        end
        return
    end
    -- Defensive lockdown gate: keep scanDirty=true so the whole pass retries
    -- once Blizzard clears SecretInChatMessagingLockdown.
    if IsChatMessagingLockdown() then
        return  -- scanDirty stays true; processed once lockdown clears
    end
    lastTransportPollTime = now
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
        wasSessionActive
            and entryCreationKeyState.DISABLE_CVAR_RESTORE_AFTER_CLEAR_DELAY_S
            or 0,
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

-- Apply ApplicantScoutDB.debug + emit feedback. Debug is intentionally a
-- slash-command troubleshooting control, not a normal settings-panel option.
_SetDebug = function(flag)
    flag = not not flag
    ApplicantScoutDB.debug = flag
    APSPrint("debug " .. (flag and "ON — every scan/emit will print" or "OFF"))
end

_SyncAutoMPlusPlaystyleDropdown = function()
    local label = _GetAutoMPlusPlaystyleLabel(
        ApplicantScoutDB and ApplicantScoutDB.autoMPlusPlaystyle)
    if autoMPlusPlaystyleDropdown then
        if type(autoMPlusPlaystyleDropdown.SetDefaultText) == "function" then
            autoMPlusPlaystyleDropdown:SetDefaultText(label)
        end
        if type(autoMPlusPlaystyleDropdown.GenerateMenu) == "function" then
            pcall(autoMPlusPlaystyleDropdown.GenerateMenu, autoMPlusPlaystyleDropdown)
        end
    end
    if autoMPlusPlaystyleFallbackText then
        autoMPlusPlaystyleFallbackText:SetText(label .. " (/apscout playstyle)")
    end
end

_SetAutoMPlusPlaystyle = function(token, quiet)
    token = _NormalizeAutoMPlusPlaystyleToken(token)
    ApplicantScoutDB.autoMPlusPlaystyle = token
    _SyncAutoMPlusPlaystyleDropdown()
    if token ~= AUTO_MPLUS_PLAYSTYLE_DISABLED then
        _SetupLFGEntryCreationKeyCapture()
        _SetupLFGDefaultPlaystyle()
        local frame = _G.LFGListFrame
        if frame and frame.EntryCreation then
            _MaybeAutoSelectDefaultPlaystyle(frame.EntryCreation, "toggle")
        end
    end
    if not quiet then
        APSPrint("M+ default playstyle: " .. _GetAutoMPlusPlaystyleStatusText())
    end
end

entryCreationKeyState.SyncAutoHiEditBox = function()
    local autoHiEditBox = settingsFrame and settingsFrame.autoHiEditBox
    if not autoHiEditBox then return end
    entryCreationKeyState.autoHiEditBoxSyncing = true
    autoHiEditBox:SetText(ApplicantScoutDB and ApplicantScoutDB.autoHiMessage or "")
    autoHiEditBox:SetCursorPosition(0)
    entryCreationKeyState.autoHiEditBoxSyncing = false
end

entryCreationKeyState.SetAutoHiMessage = function(text, quiet)
    ApplicantScoutDB.autoHiMessage =
        entryCreationKeyState.NormalizeAutoHiMessage(text)
    entryCreationKeyState.SyncAutoHiEditBox()
    if not quiet then
        if ApplicantScoutDB.autoHiMessage == "" then
            APSPrint("Auto Hi on invite: off")
        else
            APSPrint("Auto Hi on invite: " .. ApplicantScoutDB.autoHiMessage)
        end
    end
end

-- Layout constants for the Blizzard-tooltip-style panel chrome.
local _SETTINGS_FRAME_WIDTH = 420
local _SETTINGS_FRAME_HEIGHT = 112
local _SETTINGS_ANCHOR_X = 0
local _SETTINGS_ANCHOR_Y = 6
local _SETTINGS_TOP_PAD = 10        -- clearance under the rope-border top edge
local _SETTINGS_LEFT_PAD = 14
local _SETTINGS_RIGHT_COL_X = 238
local _SETTINGS_DROPDOWN_WIDTH = 170

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
    settingsFrame:SetSize(_SETTINGS_FRAME_WIDTH, _SETTINGS_FRAME_HEIGHT)
    -- Keep the panel visually attached to PVEFrame's left edge; the two-column
    -- layout happens inside the panel rather than floating the whole frame away.
    settingsFrame:SetPoint(
        "BOTTOMLEFT",
        PVEFrame,
        "TOPLEFT",
        _SETTINGS_ANCHOR_X,
        _SETTINGS_ANCHOR_Y
    )
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

    -- Compact brand label: present, but subordinate to the actual controls.
    local title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    enabledCheckbox:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", _SETTINGS_LEFT_PAD, -28)
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

    autoMPlusPlaystyleLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoMPlusPlaystyleLabel:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", _SETTINGS_RIGHT_COL_X, -14)
    autoMPlusPlaystyleLabel:SetText("M+ default playstyle")

    local dropdownOK, dropdown = pcall(
        CreateFrame,
        "DropdownButton",
        "ApplicantScoutSettingsMPlusPlaystyleDropdown",
        settingsFrame,
        "WowStyle1DropdownTemplate"
    )
    if dropdownOK and dropdown and type(dropdown.SetupMenu) == "function" then
        autoMPlusPlaystyleDropdown = dropdown
        autoMPlusPlaystyleDropdown:SetPoint(
            "TOPLEFT",
            settingsFrame,
            "TOPLEFT",
            _SETTINGS_RIGHT_COL_X,
            -32
        )
        autoMPlusPlaystyleDropdown:SetWidth(_SETTINGS_DROPDOWN_WIDTH)
        if type(autoMPlusPlaystyleDropdown.SetDefaultText) == "function" then
            autoMPlusPlaystyleDropdown:SetDefaultText(
                _GetAutoMPlusPlaystyleLabel(ApplicantScoutDB.autoMPlusPlaystyle)
            )
        end
        autoMPlusPlaystyleDropdown:SetupMenu(function(_, rootDescription)
            if not rootDescription or type(rootDescription.CreateRadio) ~= "function" then return end
            if type(rootDescription.SetTag) == "function" then
                rootDescription:SetTag("MENU_APPLICANTSCOUT_MPLUS_PLAYSTYLE")
            end

            local function IsSelected(token)
                return ApplicantScoutDB
                       and ApplicantScoutDB.autoMPlusPlaystyle == token
            end

            local function SetSelected(token)
                _SetAutoMPlusPlaystyle(token)
            end

            for _, option in ipairs(AUTO_MPLUS_PLAYSTYLE_OPTIONS) do
                rootDescription:CreateRadio(
                    _GetAutoMPlusPlaystyleLabel(option.token),
                    IsSelected,
                    SetSelected,
                    option.token
                )
            end
        end)
        _SetWidgetTooltip(
            autoMPlusPlaystyleDropdown,
            "M+ default playstyle",
            "Defaults new Mythic+ group listings to the selected playstyle. Off leaves Blizzard's field alone. Manual changes in the same form are left alone."
        )
    else
        autoMPlusPlaystyleFallbackText = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        autoMPlusPlaystyleFallbackText:SetPoint(
            "TOPLEFT",
            settingsFrame,
            "TOPLEFT",
            _SETTINGS_RIGHT_COL_X,
            -37
        )
        autoMPlusPlaystyleFallbackText:SetWidth(_SETTINGS_DROPDOWN_WIDTH)
        autoMPlusPlaystyleFallbackText:SetJustifyH("LEFT")
    end

    local autoHiDivider = settingsFrame:CreateTexture(nil, "ARTWORK")
    autoHiDivider:SetColorTexture(1, 1, 1, 0.14)
    autoHiDivider:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", _SETTINGS_LEFT_PAD, -63)
    autoHiDivider:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", -_SETTINGS_LEFT_PAD, -63)
    autoHiDivider:SetHeight(1)

    local autoHiLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoHiLabel:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", _SETTINGS_LEFT_PAD, -77)
    autoHiLabel:SetText("Auto Hi")

    local autoHiEditBox = CreateFrame(
        "EditBox",
        "ApplicantScoutSettingsAutoHiEditBox",
        settingsFrame,
        "InputBoxTemplate"
    )
    settingsFrame.autoHiEditBox = autoHiEditBox
    autoHiEditBox:SetPoint("LEFT", autoHiLabel, "RIGHT", 8, 0)
    autoHiEditBox:SetSize(190, 22)
    autoHiEditBox:SetAutoFocus(false)
    autoHiEditBox:SetMaxLetters(160)
    autoHiEditBox:SetScript("OnTextChanged", function(self, userInput)
        if entryCreationKeyState.autoHiEditBoxSyncing or not userInput then return end
        ApplicantScoutDB.autoHiMessage =
            entryCreationKeyState.NormalizeAutoHiMessage(self:GetText())
    end)
    autoHiEditBox:SetScript("OnEnterPressed", function(self)
        entryCreationKeyState.SetAutoHiMessage(self:GetText(), true)
        self:ClearFocus()
    end)
    autoHiEditBox:SetScript("OnEscapePressed", function(self)
        entryCreationKeyState.SyncAutoHiEditBox()
        self:ClearFocus()
    end)
    autoHiEditBox:SetScript("OnEditFocusLost", function(self)
        entryCreationKeyState.SetAutoHiMessage(self:GetText(), true)
    end)
    _SetWidgetTooltip(
        autoHiEditBox,
        "Auto Hi on invite",
        "Optional greeting sent once, 5 seconds after you join a group. Leave blank to disable."
    )

    local autoHiNewPartyMembersCheckbox = CreateFrame(
        "CheckButton",
        "ApplicantScoutSettingsAutoHiNewPartyMembersCheckbox",
        settingsFrame,
        "UICheckButtonTemplate"
    )
    settingsFrame.autoHiNewPartyMembersCheckbox = autoHiNewPartyMembersCheckbox
    autoHiNewPartyMembersCheckbox:SetScale(0.82)
    autoHiNewPartyMembersCheckbox:SetPoint("LEFT", autoHiEditBox, "RIGHT", 10, 0)
    autoHiNewPartyMembersCheckbox:SetScript("OnClick", function(self)
        ApplicantScoutDB.autoHiGreetNewPartyMembers = not not self:GetChecked()
    end)
    autoHiNewPartyMembersCheckbox:SetHitRectInsets(0, -130, 0, 0)
    local autoHiNewPartyMembersLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoHiNewPartyMembersLabel:SetPoint("LEFT", autoHiNewPartyMembersCheckbox, "RIGHT", 4, 1)
    autoHiNewPartyMembersLabel:SetText("new party joins")
    _SetWidgetTooltip(
        autoHiNewPartyMembersCheckbox,
        "Greet new party members",
        "Also send this greeting 10 seconds after a new player joins your party. Disabled in raids."
    )

    -- Re-sync checkboxes from DB on each show. Handles slash-toggle-while-
    -- panel-was-hidden case: open via /apscout config → checkboxes reflect DB truth.
    settingsFrame:HookScript("OnShow", function()
        enabledCheckbox:SetChecked(ApplicantScoutDB.enabled)
        settingsFrame.autoHiNewPartyMembersCheckbox:SetChecked(
            ApplicantScoutDB.autoHiGreetNewPartyMembers)
        _SyncAutoMPlusPlaystyleDropdown()
        entryCreationKeyState.SyncAutoHiEditBox()
    end)

    enabledCheckbox:SetChecked(ApplicantScoutDB.enabled)
    _SyncAutoMPlusPlaystyleDropdown()
    entryCreationKeyState.SyncAutoHiEditBox()

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
    print("  /apscout playstyle [off|learning|relaxed|competitive|carry] set M+ default playstyle")
    print("  /apscout reset          clear transport cache, queue fresh snapshot")
    print("  /apscout shotnow        force snapshot now while enabled (debug / manual sync)")
    print("  /apscout qrvisible      toggle QR frame always-visible (debug aid)")
    print("  /apscout qrmove         toggle QR move mode (Alt+drag QR frame)")
    print("  /apscout qrreset        reset QR frame position to top-left")
    print("  /apscout taintcheck     probe C_LFGList field secret-tagging")
    print("  /apscout debug [on|off] toggle debug logging")
    print("  /apscout competitive [on|off] legacy alias for Competitive / Off")
end

local function PrintPlaystyleHelp()
    APSPrint("M+ default playstyle: " .. _GetAutoMPlusPlaystyleStatusText())
    print("  /apscout playstyle off")
    print("  /apscout playstyle learning")
    print("  /apscout playstyle relaxed")
    print("  /apscout playstyle competitive")
    print("  /apscout playstyle carry")
end

SLASH_APSCOUT1 = "/apscout"
SlashCmdList.APSCOUT = function(msg)
    InitDB()
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local command, arg = msg:match("^(%S+)%s*(.-)$")
    if msg == "on" then
        _SetEnabled(true)
    elseif msg == "off" then
        _SetEnabled(false)
    elseif msg == "toggle" then
        _SetEnabled(not ApplicantScoutDB.enabled)
    elseif command == "playstyle" then
        local token = _NormalizeAutoMPlusPlaystyleCommand(arg)
        if token then
            _SetAutoMPlusPlaystyle(token)
        else
            PrintPlaystyleHelp()
        end
    elseif msg == "competitive" or msg == "competitive on" then
        _SetAutoMPlusPlaystyle(AUTO_MPLUS_PLAYSTYLE_DEFAULT)
    elseif msg == "competitive off" or msg == "nocompetitive" then
        _SetAutoMPlusPlaystyle(AUTO_MPLUS_PLAYSTYLE_DISABLED)
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
        print("  M+ default playstyle: " .. _GetAutoMPlusPlaystyleStatusText())
        print("  settings panel attached: " .. tostring(settingsFrameAttached))
        print("  session active: " .. tostring(isSessionActive))
        print("  session gen: " .. tostring(sessionGen))
        print("  scanDirty: " .. tostring(scanDirty))
        print("  group members: "
              .. tostring(math.floor(SafeNumber(GetNumGroupMembers and GetNumGroupMembers(), 0))))
        print("  transport poll age: "
              .. (lastTransportPollTime > 0
                   and string.format("%.1fs", GetTime() - lastTransportPollTime)
                   or "never"))
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
        print("  QR force-visible shot lease: " .. tostring(qrForceVisibleForShot or false))
        print("  texture pool: " .. #qrTexturePool .. " (used last paint: " .. qrTextureUsed .. ")")
        print("  last snapshot hash: " .. tostring(lastSnapshotHash))
        print("  last shot time: " .. (lastShotTime > 0
              and string.format("%.1fs ago", GetTime() - lastShotTime) or "never"))
        print("  pending throttled shot: " .. tostring(pendingShotDirty))
        entryCreationKeyState.PrintRosterInspectBatchDiagnostics()
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
            local cleanQuestID = math.floor(SafeNumber(entry.questID, 0))
            local statusActivityInfo =
                _GetActivityInfoForListing(cleanActivityID, cleanQuestID)
            local statusDungeonName = _ActivityInfoListingName(statusActivityInfo)
            print("  entry.activityIDs[1]: " .. SafeDiag(activityIDs and activityIDs[1]))
            print("  entry.activityID: " .. SafeDiag(entry.activityID))
            print("  entry.questID: " .. SafeDiag(entry.questID))
            if cleanActivityID > 0 then
                if statusActivityInfo then
                    print("  activity.name: " .. statusDungeonName)
                    print("  activity.shortName: " .. SafeDiag(statusActivityInfo.shortName))
                    print("  activity.fullName: " .. SafeDiag(statusActivityInfo.fullName))
                    print("  activity.categoryID: " .. SafeDiag(statusActivityInfo.categoryID))
                    print("  activity.difficultyID: " .. SafeDiag(statusActivityInfo.difficultyID))
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
            local visibleKeyLevel =
                _G.ApplicantScout_VisibleApplicationViewerKeystoneLevel
            print("  visibleFrame.keyLevel: "
                  .. tostring(visibleKeyLevel and visibleKeyLevel() or 0))
            local visibleDiagnostics =
                _G.ApplicantScout_VisibleApplicationViewerKeystoneDiagnostics
            visibleDiagnostics = visibleDiagnostics and visibleDiagnostics() or {}
            for _, line in ipairs(visibleDiagnostics) do
                print(line)
            end
            local cachedKeyLevel =
                entryCreationKeyState.PeekCachedEntryCreationKeystoneLevel(
                    cleanActivityID, cleanQuestID)
            print("  entryCreationCache.keyLevel: " .. tostring(cachedKeyLevel))
            local statusListingName = SafeStr(entry.name, "?"):gsub("|K[^|]*|k", "")
            local statusListingComment = SafeStr(entry.comment, "?")
            local ownedActivityID, ownedGroupID, ownedLevel, ownedInfo =
                _GetOwnedKeystoneListingInfo()
            print("  ownedKeystone.activityID: " .. tostring(ownedActivityID))
            print("  ownedKeystone.groupID: " .. tostring(ownedGroupID))
            print("  ownedKeystone.level: " .. tostring(ownedLevel))
            print("  ownedKeystone.activityName: " .. _ActivityInfoListingName(ownedInfo))
            local statusUseOwned = ownedLevel > 0
                and ownedActivityID > 0
                and ownedInfo
                and entryCreationKeyState.CanUseOwnedKeystoneForListingFallback()
                and (ownedActivityID == cleanActivityID
                    or statusDungeonName == "Mythic+"
                    or statusDungeonName == "?")
            print("  ownedKeystone.usedForListing: " .. tostring(statusUseOwned))
            local listingKeyLevel =
                _G.ApplicantScout_GetListingKeystoneLevel
            local statusDerivedKeyLevel = listingKeyLevel and listingKeyLevel(
                cleanActivityID,
                cleanQuestID,
                statusListingName,
                statusListingComment,
                statusActivityInfo) or 0
            if statusDerivedKeyLevel == 0 and statusUseOwned then
                statusDerivedKeyLevel = ownedLevel
            end
            print("  derived keyLevel: "
                  .. tostring(statusDerivedKeyLevel))
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
                      i, SafeDiag(rawID), SafeDiag(_GetApplicantApplicationStatus(info)),
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
        entryCreationKeyState.PrintDiagnostics()
        print("  default playstyle hooks: " .. tostring(lfgDefaultPlaystyleHooksSetup)
              .. (lfgDefaultPlaystyleHookError
                  and (" (error: " .. lfgDefaultPlaystyleHookError .. ")")
                  or ""))
        if ApplicantScoutDB.pveFramePosition then
            local point, x, y, ok =
                _NormalizePVEFramePosition(ApplicantScoutDB.pveFramePosition)
            if ok then
                print(string.format("  saved position: %s @ (%.0f, %.0f)",
                      point, x, y))
            else
                _ClearInvalidPVEFramePosition()
                print("  saved position: (default; invalid saved position cleared)")
            end
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
                  info and SafeDiag(_GetApplicantApplicationStatus(info)) or "n/a"))
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
        -- Queue a fresh snapshot on the next eligible scan-tick. Clears dedup
        -- and in-flight inspect batch state, but preserves known spec cache so
        -- support recovery does not create unnecessary inspect churn.
        lastSnapshotHash = nil
        pendingShotDirty = false
        entryCreationKeyState.lastQuietFullPartySignature = nil
        entryCreationKeyState.lastPayloadQuietFullPartySignature = nil
        entryCreationKeyState.MarkRosterCompositionChanged()
        entryCreationKeyState.ClearRosterInspectBatchState()
        entryCreationKeyState.ClearRosterLoadRetryState()
        scanDirty = true
        APSPrint("resync queued — emits when transport is active and QR is available")
    elseif msg == "shotnow" then
        -- Force snapshot bypass dedup + throttle. Use this to verify QR pipeline
        -- end-to-end during dev: builds payload, encodes as QR, paints into frame,
        -- calls Screenshot(). Inspect the resulting JPG in any QR scanner — should
        -- decode to APS1 + length + listing/version/applicants + CRC32.
        if not (ApplicantScoutDB and ApplicantScoutDB.enabled) then
            APSPrint("shotnow skipped — enable ApplicantScout first")
            return
        end
        local entry = CheckSessionTransition()
        MaybeTriggerScreenshot(true, entry)
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
