-- ApplicantScout — encodes M+ applicant snapshots as a QR code rendered into a
-- TOPLEFT-anchored frame and triggers Screenshot() so the companion (external
-- Python tool) can decode the resulting JPG via pyzbar and show WCL N/H/M/M+
-- percentiles for each applicant.
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
    -- One-shot migration sentinel. Existing installs may have `debug=true`
    -- stuck from a prior `/apscout debug on` (default flipped from "on-stuck"
    -- to "off after explicit toggle" in this version). When the key is
    -- absent we force `debug=false` exactly once, then mark migrated so
    -- subsequent user toggles persist normally.
    debugDefaultMigrated = false,
    -- Pre-escalation screenshotQuality value, captured on the first session
    -- where we bumped CVar to 8. Restored on /apscout off so users who run
    -- the addon once and never host LFG don't get stuck with larger manual
    -- screenshots forever. nil = never bumped (no restore needed).
    priorScreenshotQuality = nil,
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
-- Trade-off: user sees the QR on TOPLEFT (covers minimap area) for the whole
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
      _SetEnabled, _SetDebug, _AttachSettingsPanel, _AddSettingsRow, _SetWidgetTooltip
-- Forward-decl mutable state used by StartSession/EndSession/reset. WHY: those
-- functions assign via bare `x = ...`; without forward-decl, the `local` keyword
-- on declarations later in this file would shadow them and the bare assignments
-- silently target globals.
-- qrAlwaysVisible is forward-decl'd here so EndSession (above the slash handler
-- that owns the toggle) can preserve the user's debug visibility setting when
-- session ends.
local versionEmittedThisSession, lastSnapshotHash, lastShotTime, pendingShotDirty,
      qrAlwaysVisible, suppressShotsUntil

-- Settings panel state. settingsFrame = parent of all widgets; created lazily
-- in _AttachSettingsPanel. settingsFrameAttached = one-shot init guard.
-- stackedHeight = current content height (Inset-relative), used by
-- _AddSettingsRow to position next widget + resize frame.
local settingsFrame, enabledCheckbox, debugCheckbox
local settingsFrameAttached = false
local stackedHeight = 0

-- ───────────────────────────────────────────────────────────
-- helpers

SafeStr = function(v)
    if v == nil then return "" end
    -- Boundary cleanse for C_LFGList field reads. Two distinct hazards:
    -- (1) Midnight 12.0 SecretInChatMessagingLockdown predicate tags certain
    --     applicant fields as secret values; tostring(secret) returns a SECRET
    --     STRING that contaminates downstream string ops. Substitute "?"
    --     placeholder at the boundary so payload bytes stay clean.
    -- (2) UI-color escapes (|c, |r, |T, |H, etc.) embedded in listing comments
    --     and player names would render as garbage in companion overlay or
    --     break QR alphanumeric encoding. Strip them.
    -- issecretvalue is whitelisted to read the taint flag without propagating.
    local issv = _G.issecretvalue
    if issv and issv(v) then return "?" end
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
    -- versionEmittedThisSession is now a diag flag only — BuildPayload emits
    -- VERSION on every shot, not just the first, to handle the
    -- companion-launched-mid-session case (companion needs realm/region info
    -- from the freshest backlog snapshot, which previously lacked the version
    -- block once `emittedThisSession` had latched true).
    versionEmittedThisSession = false
    lastSnapshotHash = nil
    pendingShotDirty = false

    -- Show QR frame fully visible (alpha=1) for the entire active session.
    -- Reasoning at top of file: alpha-flicker captured alpha=0 framebuffers
    -- in real-world WoW setups (Screenshot() outraces SetAlpha propagation),
    -- so the frame stays painted at alpha=1 from session start to
    -- EndSession's deferred Hide. Visible cost: covers TOPLEFT minimap region
    -- while user hosts. /apscout qrvisible toggle still overrides (forces
    -- visible even outside session, debug aid).
    if qrFrame then
        qrFrame:SetAlpha(1)
        qrFrame:Show()
    end

    -- 0.3s grace before first snapshot. The frame just transitioned from
    -- Hide()'d to Show()+alpha=1 — on some setups (high refresh rate, deferred
    -- compositors, non-integer DPI) the GPU framebuffer needs multiple render
    -- passes before the painted QR textures are visible to Screenshot(). Without
    -- this gate, the very first snapshot after listing creation can capture an
    -- empty-or-half-painted frame → no APS1 marker → companion logs "skip" and
    -- overlay never appears. MaybeTriggerScreenshot honours this via
    -- suppressShotsUntil; pendingShotDirty=true ensures the scan-tick drain
    -- retries once the window expires (within ~0.55s of session start).
    suppressShotsUntil = GetTime() + 0.3
end

EndSession = function()
    if not isSessionActive then return end
    isSessionActive = false  -- claim the transition; further scans early-return

    scanDirty = false
    -- Force-shot path bypasses suppressShotsUntil via force=true, but clear
    -- the gate explicitly so a fresh StartSession that happens before the
    -- old gate would have expired starts with a clean 0.3s window.
    suppressShotsUntil = 0

    -- Final force-shot: BuildPayload now sees isSessionActive=false → entry=nil
    -- → emits has_listing=0 + 0 applicants. Companion's apply_snapshot diff:
    -- removes all applicants, clears listing → overlay hides. Bypasses dedup +
    -- throttle (force=true) since this is one-shot terminal event.
    MaybeTriggerScreenshot(true)
    versionEmittedThisSession = false  -- diag flag only (BuildPayload now emits VERSION every shot)
    -- Defensive: force-shot path resets pendingShotDirty on success, but if it
    -- early-returned (qrFrame missing, QR encode failure) the flag could persist
    -- across sessions and trigger empty drains in the scan ticker. Clear here.
    pendingShotDirty = false

    -- Schedule deferred Hide AFTER the final clear-shot has had a chance to
    -- fire. The screenshot path inside MaybeTriggerScreenshot is
    -- C_Timer.After(0, Screenshot()), so the actual capture happens NEXT
    -- frame. Hiding synchronously here would make the screenshot capture an
    -- empty screen (no QR), companion never sees the clear signal, overlay
    -- stuck showing pre-end applicants. 0.3s lets the Screenshot() fire first.
    -- All gating (qrAlwaysVisible, new-session-started) re-checked at fire
    -- time so the deferred Hide respects the latest toggle state — important
    -- for /apscout off which resets qrAlwaysVisible right after EndSession.
    if qrFrame then
        local genAtSchedule = sessionGen
        C_Timer.After(0.3, function()
            if not isSessionActive
               and not qrAlwaysVisible
               and sessionGen == genAtSchedule
               and qrFrame then
                qrFrame:Hide()
            end
        end)
    end
end

CheckSessionTransition = function()
    local hasEntry = C_LFGList.HasActiveEntryInfo()
    local entry = hasEntry and C_LFGList.GetActiveEntryInfo() or nil
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
-- One containing frame in upper-left, sized to whatever QR version we just
-- generated (adaptive). White background covers the entire frame; row-RLE
-- pool of black-rectangle textures draws the QR data.
local function CreateQRFrame()
    if qrFrameCreated then return end
    qrFrame = CreateFrame("Frame", "ApplicantScoutQRFrame", UIParent)
    qrFrame:SetIgnoreParentScale(true)
    -- DIALOG strata: above gameplay HUD but below modal popups (StaticPopup,
    -- ColorPicker, dropdowns). Avoids FULLSCREEN_DIALOG which has been
    -- empirically observed to interfere with input chain on heavy renders.
    qrFrame:SetFrameStrata("DIALOG")
    qrFrame:SetSize(64, 64)  -- placeholder; PaintQR resizes per-snapshot
    qrFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)

    -- White background — single texture covering the whole frame, BACKGROUND
    -- layer. Black module textures (BORDER layer above) overlay it. pyzbar's
    -- QR detector relies on black-on-white contrast — this gives it the
    -- canonical look.
    qrBackground = qrFrame:CreateTexture(nil, "BACKGROUND")
    qrBackground:SetColorTexture(1, 1, 1, 1)
    qrBackground:SetAllPoints(qrFrame)

    qrFrameCreated = true
    -- Hidden by default. StartSession does Show()+SetAlpha(1); EndSession
    -- defers Hide() 0.3s after final clear-shot fires.
    qrFrame:Hide()
end

-- /apscout qrvisible state — forces frame to stay visible regardless of session
-- state (debug aid for visual inspection). Forward-declared at top so EndSession
-- can respect the toggle when hiding the frame.
qrAlwaysVisible = false

-- Set screenshot format. Reed-Solomon ECC handles JPG quantization noise on
-- 3-px QR modules but tolerance shrinks vs 4 px — bump quality floor to 8
-- (~75% JPG quality) for safety with the smaller modules. Idempotent across
-- /reloads. SetCVar persists in Config.wtf — user's own manual screenshots
-- also get this quality (acceptable side-effect, undone on /apscout off via
-- RestoreScreenshotCVars).
local function EnsureScreenshotCVars()
    if not SetCVar then return end
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
    SetCVar("screenshotFormat", "jpg")
end

-- Restore the user's pre-addon screenshotQuality on /apscout off. Only acts
-- if we actually bumped CVar at some point (priorScreenshotQuality non-nil).
-- Clears the stash after restore so a fresh enable+escalate cycle records
-- the THEN-current value (which would be 8 if user re-enables).
local function RestoreScreenshotCVars()
    if not SetCVar then return end
    if not (ApplicantScoutDB and ApplicantScoutDB.priorScreenshotQuality) then
        return
    end
    local prior = tonumber(ApplicantScoutDB.priorScreenshotQuality) or 0
    if prior >= 0 and prior <= 10 then
        SetCVar("screenshotQuality", tostring(prior))
        if APSPrint then
            APSPrint("restored screenshotQuality=" .. prior .. " (pre-ApplicantScout value)")
        end
    end
    ApplicantScoutDB.priorScreenshotQuality = nil
end

-- ───────────────────────────────────────────────────────────
-- Payload encoder + QR painter
--
-- Wire format (binary, big-endian; unchanged from prior pixel transport — QR
-- is purely a transport upgrade, the same bytes flow end-to-end):
--   Header:    "APS1" magic + version byte + uint16 length + 2 reserved bytes
--   Listing:   has_listing byte; if 1: uint32 activityID + key_level byte +
--              len-prefixed dungeonName/listingName/comment (uint8 len + utf8)
--   Version:   has_version byte; if 1: len-prefixed addonVer/gameVer +
--              region_id byte + len-prefixed playerName
--   Apps:      uint16 count; per applicant: uint32 id + uint8 classID +
--              uint16 specID + uint16 ilvl + uint16 score + uint8 role +
--              uint8 nameLen + utf8 name (CLAMPED to 255 bytes)
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
    n = math.floor(n or 0) % 4294967296
    return string.char(
        math.floor(n / 16777216) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 256) % 256,
        n % 256
    )
end
local function _Uint16BE(n)
    n = math.floor(n or 0) % 65536
    return string.char(math.floor(n / 256), n % 256)
end

-- Append len-byte + utf-8 bytes to output table. CLAMPS to 255 bytes (safety).
local function _PackLenStr(out, str)
    str = str or ""
    if #str > 255 then str = str:sub(1, 255) end
    table.insert(out, string.char(#str))
    table.insert(out, str)
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
    table.insert(out, string.char(0x02))    -- protocol version (v2: multi-member group apps)
    table.insert(out, "\0\0")                -- length placeholder (uint16 BE)
    table.insert(out, "\0\0")                -- reserved

    -- Listing block
    if entry then
        -- Midnight 12.0 returns activityIDs (table) on the primary listing —
        -- legacy entry.activityID is nil. Fall back to legacy field for
        -- forward-compat with future API renames.
        local activityID = (entry.activityIDs and entry.activityIDs[1])
                            or entry.activityID
                            or 0
        local activityInfo = (activityID > 0)
                              and C_LFGList.GetActivityInfoTable(activityID)
                              or nil
        local dungeonName = (activityInfo and (activityInfo.shortName or activityInfo.fullName)) or "?"
        local categoryID = (activityInfo and activityInfo.categoryID) or 0
        local isMythicPlus = (categoryID == 2)

        -- Strip player-link |Kxxx|k from listing name (SafeStr handles |c etc but
        -- |K is its own escape WoW redacts char names with on cross-realm)
        local listingName = (entry.name or ""):gsub("|K[^|]*|k", "")

        -- Keystone level extraction. WHY NOT C_MythicPlus.GetOwnedKeystoneLevel():
        -- that's the host's BAG keystone, not the listing's target level. Host
        -- can list a +10 group with a +14 keystone in their bag → wrong number.
        -- Blizzard does NOT expose a numeric key_level on activityInfoTable
        -- (minLevel/maxLevel are character level, e.g. 80). The level lives in
        -- the listing TITLE (auto-named "+N <Dungeon>") or COMMENT (host-typed).
        -- Parse "+N" from both, take first valid hit. Sane M+ range 2..50.
        local function _ExtractKeyLevel(s)
            if type(s) ~= "string" or s == "" then return 0 end
            local m = s:match("%+(%d+)")
            if not m then return 0 end
            local n = tonumber(m)
            if n and n >= 2 and n <= 50 then return n end
            return 0
        end
        local keyLevel = 0
        if isMythicPlus then
            keyLevel = _ExtractKeyLevel(SafeStr(listingName))
            if keyLevel == 0 then
                keyLevel = _ExtractKeyLevel(SafeStr(entry.comment))
            end
        end

        table.insert(out, string.char(1))
        table.insert(out, _Uint32BE(activityID))
        table.insert(out, string.char(math.min(keyLevel, 255)))
        _PackLenStr(out, SafeStr(dungeonName))
        _PackLenStr(out, SafeStr(listingName))
        _PackLenStr(out, SafeStr(entry.comment))
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
    -- versionEmittedThisSession stays as a flag for status diagnostics
    -- but is no longer load-bearing for emission.
    table.insert(out, string.char(1))
    _PackLenStr(out, ADDON_VERSION)
    local gameVer = (GetBuildInfo and select(1, GetBuildInfo())) or "?"
    _PackLenStr(out, gameVer)
    table.insert(out, string.char((GetCurrentRegion and GetCurrentRegion()) or 0))
    local pname, prealm = UnitFullName("player")
    local fullName = (pname or "?") ..
                     ((prealm and prealm ~= "") and ("-" .. prealm) or "")
    _PackLenStr(out, fullName)
    versionEmittedThisSession = true

    -- Applicants — filter out DEAD_STATUSES + sort by ID for hash stability
    local validIDs = {}
    for _, id in ipairs(applicantIDs or {}) do
        local info = C_LFGList.GetApplicantInfo(id)
        if info and not APP_DEAD_STATUSES[info.applicantStatus or ""]
           and info.numMembers and info.numMembers > 0 then
            table.insert(validIDs, id)
        end
    end
    table.sort(validIDs)

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
    for _, id in ipairs(validIDs) do
        local info = C_LFGList.GetApplicantInfo(id)
        local n = (info and info.numMembers) or 0
        for m = 1, n do
            local name, class, _, _, ilvl, _, _, _, _, role, _, score, _, _, _, specID
                = C_LFGList.GetApplicantMemberInfo(id, m)
            if name then
                table.insert(memberOut, _Uint32BE(id))
                table.insert(memberOut, string.char(m))
                table.insert(memberOut, string.char(CLASS_NAME_TO_ID[class or ""] or 0))
                table.insert(memberOut, _Uint16BE(specID or 0))
                table.insert(memberOut, _Uint16BE(math.floor((ilvl or 0) + 0.5)))
                table.insert(memberOut, _Uint16BE(math.floor((score or 0) + 0.5)))
                table.insert(memberOut, string.char(ROLE_NAME_TO_BYTE[role or "DAMAGER"] or 2))
                _PackLenStr(memberOut, SafeStr(name) or "?")
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

-- Hex-encode bytes as uppercase ASCII. WHY: opencv's QRCodeDetector (and
-- pyzbar, every QR mobile reader) interpret QR payload as a TEXT STRING and
-- truncate at the first NUL byte. Our binary format is 0x00-rich (length
-- placeholder, has_listing=0, reserved bytes, uint16 high bytes, etc.) → raw
-- bytes get cut off after a few chars. Hex sidesteps this completely: every
-- byte is two ASCII hex chars, never NUL. Bonus: uppercase hex falls into QR's
-- alphanumeric mode (denser than byte mode), so the QR ends up SMALLER than
-- if we'd used base64 in byte mode (e.g. 1024-byte payload: hex+alphanumeric
-- needs Version 30, base64+byte needs Version 28 — but the alphanumeric
-- module count vs byte count tradeoff favors hex by a few px in frame size).
-- Decoder mirror: `bytes.fromhex(text)` in Python.
local function _HexEncode(data)
    local out = {}
    for i = 1, #data do
        out[i] = string.format("%02X", string.byte(data, i))
    end
    return table.concat(out)
end

-- Builds QR matrix from binary payload via embedded lua-qrcode library.
-- Hex-encodes payload first (see _HexEncode above for rationale). Returns
-- matrix or nil on encoding failure (payload too large for max QR Version 40,
-- or library bug).
local function BuildQRMatrix(payload)
    if not _qrencode then
        if APSPrint then
            APSPrint("CRITICAL: QR library not loaded — check libs/qrencode.lua")
        end
        return nil
    end
    local hex = _HexEncode(payload)
    -- ec_level 2 = M (medium, ~15% recovery). Plenty for JPG quantization noise.
    local ok, result = _qrencode(hex, QR_EC_LEVEL)
    if not ok then
        if APSPrint then
            APSPrint("QR encode failed: " .. tostring(result))
        end
        return nil
    end
    return result
end

-- State for trigger throttling + dedup
-- (forward-declared at top — no `local` here. Without forward-decl, StartSession's
-- bare assignments would silently target globals instead of resetting these locals.)
lastSnapshotHash = nil
lastShotTime = 0
pendingShotDirty = false
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
        entry = entryHint or C_LFGList.GetActiveEntryInfo()
    end
    local applicantIDs = (entry and (C_LFGList.GetApplicants() or {})) or {}

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

local EVENT_HANDLERS = {
    PLAYER_LOGIN                     = function()
        InitDB()
        MarkDirty("login")
        _AttachSettingsPanel()
    end,
    PLAYER_ENTERING_WORLD            = function()
        EnsureScreenshotCVars()
        CreateQRFrame()
        MarkDirty("pew")
    end,
    LFG_LIST_APPLICANT_LIST_UPDATED  = function() MarkDirty("listupd") end,
    LFG_LIST_APPLICANT_UPDATED       = function() MarkDirty("appupd") end,
    LFG_LIST_ACTIVE_ENTRY_UPDATE     = function() MarkDirty("entryupd") end,
    PARTY_LEADER_CHANGED             = function() MarkDirty("ldrchg") end,
    GROUP_ROSTER_UPDATE              = function() MarkDirty("roster") end,
    GROUP_LEFT                       = function() MarkDirty("groupleft") end,
}

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
-- Lockdown short-circuit: skip the whole pass during ChatMessagingLockdown
-- so SecretInChatMessagingLockdown-tagged C_LFGList fields don't get encoded
-- as "?" placeholders that would garble the companion overlay.
C_Timer.NewTicker(0.25, function()
    if not (scanDirty and ApplicantScoutDB and ApplicantScoutDB.enabled) then
        -- Drain pending throttled shot: data was changed during throttle
        -- window (pendingShotDirty=true), but no new events fired since.
        -- Without this drain: shot never goes out for sustained state.
        if pendingShotDirty and (GetTime() - lastShotTime) >= SHOT_THROTTLE_S then
            MaybeTriggerScreenshot()
        end
        return
    end
    -- Defensive lockdown gate: C_LFGList fields go secret in lockdown
    -- (SecretInChatMessagingLockdown). SafeStr handles per-field substitution
    -- ("?") so encoder still produces valid bytes — but skipping entirely
    -- avoids painting "?" placeholders that companion would show as garbage.
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
       and C_ChatInfo.InChatMessagingLockdown() then
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
-- Settings panel: pinned above PVEFrame (LFG window) with custom modern chrome.
--
-- Visual language: 1 px brand-green (#00ff7f) border at low alpha, near-black
-- translucent fill, header strip carrying a brand-tinted gradient + title text
-- + minimal "×" close glyph. Pattern mirrors RaiderIO / BigWigs / DBM tooltips
-- (clean, content-first, no "carved stone" Blizzard chrome). Cheaper visually
-- than BasicFrameTemplateWithInset and matches the addon's brand identity.
--
-- Parent=PVEFrame so visibility cascades automatically: open LFG → panel
-- appears, close LFG → panel hides. Anchor BOTTOMLEFT-of-self to TOPLEFT-of-
-- PVEFrame with a small visible gap.
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

-- Single source of truth for the enabled toggle. All entry points (slash on/off,
-- slash toggle, GUI checkbox click) route here so teardown logic
-- (EndSession + RestoreScreenshotCVars + qrFrame Hide) lives in one place.
-- Idempotent: silent on no-op transitions, but still re-syncs UI checkbox AND
-- prints "already X" so user sees their slash command was received.
_SetEnabled = function(flag)
    flag = not not flag  -- coerce 1/nil → strict bool so equality compare is sane
    if flag == ApplicantScoutDB.enabled then
        if enabledCheckbox then enabledCheckbox:SetChecked(flag) end
        APSPrint(flag and "already enabled" or "already disabled")
        return
    end
    if flag then
        ApplicantScoutDB.enabled = true
        scanDirty = true  -- next 0.25s tick recovers session if listing active
        APSPrint("enabled — will emit during LFG hosting")
    else
        local wasSessionActive = isSessionActive
        if wasSessionActive then EndSession() end  -- final clear-shot for companion
        ApplicantScoutDB.enabled = false
        -- Reset before EndSession's deferred 0.3s Hide closure fires so it
        -- respects "off" semantics even when user had debug toggle on.
        qrAlwaysVisible = false
        -- If no session was active, EndSession didn't schedule deferred Hide;
        -- sync Hide here. Active-session case handled by EndSession.
        if qrFrame and not wasSessionActive then qrFrame:Hide() end
        RestoreScreenshotCVars()
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

-- Layout constants for the modern custom-chrome panel.
local _SETTINGS_HEADER_HEIGHT = 26       -- top strip (title text + close glyph)
local _SETTINGS_TITLE_BOTTOM_GAP = 8     -- breathing room below header separator
local _SETTINGS_CONTENT_BOTTOM_PAD = 10  -- breathing room below last row
local _SETTINGS_DEFAULT_ROW_HEIGHT = 22
local _SETTINGS_ROW_GAP = 6              -- airier gaps for modern feel
local _SETTINGS_FRAME_WIDTH = 260
local _SETTINGS_LEFT_PAD = 14
-- Y offset of first widget row from the frame TOPLEFT (= header + gap below).
local _SETTINGS_CONTENT_TOP_OFFSET = _SETTINGS_HEADER_HEIGHT
                                     + _SETTINGS_TITLE_BOTTOM_GAP

-- Brand colour: #00ff7f — the same green that wraps "ApplicantScout" in chat
-- prints (`|cff00ff7f...|r`). Surfacing it in the panel chrome ties the addon
-- visually to its own brand identity and stops the panel from looking like a
-- generic Blizzard menu.
local _BRAND_R, _BRAND_G, _BRAND_B = 0.00, 1.00, 0.498

-- Caller convention: widget already has parent=settingsFrame when created.
-- Helper does NOT call SetParent — explicit ownership, less magic.
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
        _SETTINGS_CONTENT_TOP_OFFSET + stackedHeight + _SETTINGS_CONTENT_BOTTOM_PAD
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
    settingsFrame:SetSize(_SETTINGS_FRAME_WIDTH, 100)  -- placeholder; _AddSettingsRow grows
    settingsFrame:SetPoint("BOTTOMLEFT", PVEFrame, "TOPLEFT", 0, 6)
    settingsFrame:SetClampedToScreen(true)
    settingsFrame:SetFrameStrata("DIALOG")

    -- Modern flat backdrop: 1 px solid border + dark translucent fill.
    -- Both files reuse the universal 8×8 white texture; tinting via
    -- SetBackdropColor / SetBackdropBorderColor controls the look.
    settingsFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    settingsFrame:SetBackdropColor(0.05, 0.05, 0.07, 0.94)         -- near-black, slightly translucent
    settingsFrame:SetBackdropBorderColor(_BRAND_R, _BRAND_G, _BRAND_B, 0.55)  -- brand-green hairline

    -- Header strip: brand-tinted band carrying title + close glyph. Subtle
    -- horizontal gradient (brand → near-transparent) gives the panel a touch
    -- of directional flair without the heavy "carved stone" Blizzard look.
    local header = settingsFrame:CreateTexture(nil, "ARTWORK")
    header:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", -1, -1)
    header:SetHeight(_SETTINGS_HEADER_HEIGHT)
    header:SetColorTexture(1, 1, 1, 1)  -- placeholder; SetGradient overrides
    if header.SetGradient then
        header:SetGradient("HORIZONTAL",
            CreateColor(_BRAND_R, _BRAND_G, _BRAND_B, 0.22),
            CreateColor(_BRAND_R, _BRAND_G, _BRAND_B, 0.05))
    else
        -- Pre-10.x clients (or stripped custom clients) fall back to a flat tint.
        header:SetColorTexture(_BRAND_R, _BRAND_G, _BRAND_B, 0.12)
    end

    -- Hairline separator under the header — same brand colour, slightly
    -- stronger alpha so the header reads as a distinct strip.
    local sep = settingsFrame:CreateTexture(nil, "ARTWORK", nil, 1)
    sep:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)
    sep:SetColorTexture(_BRAND_R, _BRAND_G, _BRAND_B, 0.40)

    -- Title — branded "Applicant" in green, "Scout" in white. GameFontHighlight
    -- (vs GameFontNormal) gives a pure-white reset color after the |r escape so
    -- "Scout" reads cleanly against the dark panel instead of the yellowy
    -- header-text default.
    local title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", header, "LEFT", _SETTINGS_LEFT_PAD - 4, 0)
    title:SetText("|cff00ff7fApplicant|rScout")

    -- Close glyph "×" — minimal, hover lights up red. Mirrors modern web-style
    -- modal close buttons; way lighter than Blizzard's Interface\Buttons texture.
    local closeBtn = CreateFrame("Button", nil, settingsFrame)
    closeBtn:SetSize(_SETTINGS_HEADER_HEIGHT, _SETTINGS_HEADER_HEIGHT)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 1)  -- +1 visually centres the glyph
    closeText:SetText("×")
    closeText:SetTextColor(0.75, 0.75, 0.78, 1)
    closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(1.00, 0.40, 0.40, 1) end)
    closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(0.75, 0.75, 0.78, 1) end)
    closeBtn:SetScript("OnClick", function() settingsFrame:Hide() end)
    _SetWidgetTooltip(closeBtn, "Close",
        "Hide the settings panel. Reopen via |cff00ff7f/apscout config|r — closing here keeps the panel hidden across LFG show/hide cycles in this session.")

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

    -- Re-sync checkboxes from DB on each show. Handles slash-toggle-while-
    -- panel-was-hidden case: open via /apscout config → checkboxes reflect DB truth.
    settingsFrame:HookScript("OnShow", function()
        enabledCheckbox:SetChecked(ApplicantScoutDB.enabled)
        debugCheckbox:SetChecked(ApplicantScoutDB.debug)
    end)

    enabledCheckbox:SetChecked(ApplicantScoutDB.enabled)
    debugCheckbox:SetChecked(ApplicantScoutDB.debug)

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
    print("  /apscout taintcheck     probe C_LFGList field secret-tagging")
    print("  /apscout debug [on|off] toggle debug logging")
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
        print("  settings panel attached: " .. tostring(settingsFrameAttached))
        print("  session active: " .. tostring(isSessionActive))
        print("  session gen: " .. tostring(sessionGen))
        print("  scanDirty: " .. tostring(scanDirty))
        print("  shot suppressed: " .. (suppressShotsUntil and suppressShotsUntil > 0
              and (GetTime() < suppressShotsUntil
                   and string.format("yes (%.2fs left)", suppressShotsUntil - GetTime())
                   or "no (window expired)")
              or "no"))
        print("  ChatMessagingLockdown: " .. tostring(
              C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
              and C_ChatInfo.InChatMessagingLockdown()))
        -- QR transport diagnostics
        print("|cff00ff7f---|r QR transport:")
        print("  QR library loaded: " .. tostring(_qrencode ~= nil))
        print("  QR frame created: " .. tostring(qrFrameCreated))
        if qrFrame then
            print("  QR frame visible: " .. tostring(qrFrame:IsShown()) ..
                  " (always-visible mode: " .. tostring(qrAlwaysVisible) .. ")")
            print("  QR frame size: " .. qrCurrentSize .. "×" .. qrCurrentSize .. " px")
        end
        print("  texture pool: " .. #qrTexturePool .. " (used last paint: " .. qrTextureUsed .. ")")
        print("  last snapshot hash: " .. tostring(lastSnapshotHash))
        print("  last shot time: " .. (lastShotTime > 0
              and string.format("%.1fs ago", GetTime() - lastShotTime) or "never"))
        print("  pending throttled shot: " .. tostring(pendingShotDirty))
        print("  versionEmittedThisSession: " .. tostring(versionEmittedThisSession))
        print("  screenshotQuality: " .. tostring(GetCVar("screenshotQuality")))
        print("  screenshotFormat: " .. tostring(GetCVar("screenshotFormat")))
        -- raw API diagnostics
        print("|cff00ff7f---|r raw API:")
        print("  HasActiveEntryInfo: " .. tostring(C_LFGList.HasActiveEntryInfo()))
        local entry = C_LFGList.GetActiveEntryInfo()
        if entry then
            local aid = (entry.activityIDs and entry.activityIDs[1])
                         or entry.activityID
            print("  entry.activityIDs[1]: " .. tostring(aid))
            print("  entry.name: " .. tostring(entry.name))
            print("  entry.comment: " .. tostring(entry.comment))
        else
            print("  entry: nil")
        end
        local applicants = C_LFGList.GetApplicants() or {}
        print("  GetApplicants count: " .. #applicants)
        for i = 1, math.min(3, #applicants) do
            local info = C_LFGList.GetApplicantInfo(applicants[i])
            if info then
                print(string.format("    #%d id=%d status=%s numMembers=%s",
                      i, applicants[i], tostring(info.applicantStatus), tostring(info.numMembers)))
            end
        end
    elseif msg == "taintcheck" then
        -- One-shot diagnostic. Slash-handler frame is hardware-event-rooted
        -- (clean). Reads C_LFGList directly + per-field issecretvalue dump.
        -- No emit, no queue interaction. Useful with active applicants (probe
        -- their fields) or empty listing (probe lockdown / version flags only).
        local issv = _G.issecretvalue or function() return false end
        print("|cff00ff7fApplicantScout|r taintcheck:")
        print("  InChatMessagingLockdown: " .. tostring(
              C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
              and C_ChatInfo.InChatMessagingLockdown()))
        local applicants = C_LFGList.GetApplicants() or {}
        print("  applicants: " .. #applicants)
        for i = 1, math.min(3, #applicants) do
            local id = applicants[i]
            local info = C_LFGList.GetApplicantInfo(id)
            local name, class, _, _, ilvl, _, _, _, _, role, _, score, _, _, _, specID
                = C_LFGList.GetApplicantMemberInfo(id, 1)
            print(string.format("  #%d id=%d (id_secret=%s) status=%s",
                  i, id, tostring(issv(id)),
                  tostring(info and info.applicantStatus or "n/a")))
            print(string.format("    name=%s(s=%s) class=%s(s=%s) specID=%s(s=%s)",
                  tostring(name), tostring(issv(name)),
                  tostring(class), tostring(issv(class)),
                  tostring(specID), tostring(issv(specID))))
            print(string.format("    ilvl=%s(s=%s) score=%s(s=%s) role=%s(s=%s)",
                  tostring(ilvl), tostring(issv(ilvl)),
                  tostring(score), tostring(issv(score)),
                  tostring(role), tostring(issv(role))))
        end
    elseif msg == "reset" then
        -- Force fresh full snapshot on next scan-tick. Clears dedup state so the
        -- next snapshot is bit-for-bit different from prior cached one → triggers
        -- a screenshot regardless of dedup. VERSION block re-emitted so companion
        -- re-syncs region for WCL.
        lastSnapshotHash = nil
        versionEmittedThisSession = false
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
        -- Toggle frame visibility OUTSIDE active session (debug aid for
        -- inspecting last-painted QR contents without hosting LFG). During
        -- an active session the frame is alpha=1 anyway — toggle is a no-op
        -- there. With qrAlwaysVisible=true: frame stays Show()'d at alpha=1
        -- across StartSession→EndSession boundaries; with false: EndSession's
        -- deferred Hide() reaches the frame as designed.
        qrAlwaysVisible = not qrAlwaysVisible
        if qrFrame then
            if qrAlwaysVisible then
                qrFrame:SetAlpha(1)
                qrFrame:Show()
            elseif not isSessionActive then
                qrFrame:Hide()  -- not hosting → off; mid-session toggle stays alpha=1
            end
        end
        APSPrint("QR frame always-visible: " .. tostring(qrAlwaysVisible))
    elseif msg == "debug" or msg == "debug on" then
        _SetDebug(true)
    elseif msg == "debug off" or msg == "nodebug" then
        _SetDebug(false)
    else
        PrintHelp()
    end
end
