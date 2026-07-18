local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local fixture_mode = arg and arg[1] or "applicants"
assert(fixture_mode == "applicants"
       or fixture_mode == "roster-only"
       or fixture_mode == "screenshot-failure"
       or fixture_mode == "screenshot-always-fail"
       or fixture_mode == "terminal-clear-failure"
       or fixture_mode == "terminal-clear-always-fail",
    "unsupported fixture mode: " .. tostring(fixture_mode))
local roster_only = fixture_mode == "roster-only"
local transient_screenshot_failure = fixture_mode == "screenshot-failure"
local persistent_screenshot_failure = fixture_mode == "screenshot-always-fail"
local terminal_clear_failure = fixture_mode == "terminal-clear-failure"
local terminal_clear_always_fail = fixture_mode == "terminal-clear-always-fail"
local terminal_clear_mode = terminal_clear_failure or terminal_clear_always_fail

-- Default mode reproduces the live report: two people and five applicants.
-- Roster-only mode keeps a full party and removes every applicant.
if not roster_only then
    env.unit_data.party2 = nil
    env.unit_data.party3 = nil
    env.unit_data.party4 = nil
end
GetNumGroupMembers = function() return roster_only and 5 or 2 end
IsInRaid = function() return false end

local applicant_ids = roster_only and {} or { 42, 43, 44, 45, 46 }
C_LFGList.HasActiveEntryInfo = function() return true end
C_LFGList.GetActiveEntryInfo = function()
    return {
        activityIDs = { 401 },
        questID = 0,
        name = "Capture lifecycle fixture",
        comment = "five applicants and two party members",
    }
end
C_LFGList.GetApplicants = function() return applicant_ids end
C_LFGList.GetApplicantInfo = function(id)
    return { applicantID = id, applicationStatus = "applied", numMembers = 1 }
end
C_LFGList.GetApplicantMemberInfo = function(id, member_index)
    if member_index ~= 1 then return nil end
    local suffix = tostring(id)
    return "Applicant" .. suffix .. "-Ravencrest", "PALADIN", nil, nil,
        700 + id / 100, nil, nil, nil, nil, "DAMAGER", nil, 2500 + id,
        nil, nil, nil, 70
end

local now = 1000
local frame_step = 0.033
local timers = {}
local tickers = {}
local frames = {}
local screenshot_times = {}
local screenshot_attempt_cvars = {}
local screenshot_attempts = 0
local terminal_failure_started = false
local terminal_failure_count = 0
local pre_terminal_hash = nil

GetTime = function() return now end
local cvars = {
    screenshotFormat = "png",
    screenshotQuality = "3",
}
GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value) cvars[name] = tostring(value) end
Screenshot = function()
    screenshot_attempts = screenshot_attempts + 1
    screenshot_attempt_cvars[#screenshot_attempt_cvars + 1] = {
        format = cvars.screenshotFormat,
        quality = cvars.screenshotQuality,
    }
    local fail_terminal = terminal_failure_started
       and (terminal_clear_always_fail
            or (terminal_clear_failure and terminal_failure_count == 0))
    if (transient_screenshot_failure and screenshot_attempts == 1)
       or persistent_screenshot_failure
       or fail_terminal then
        if fail_terminal then
            terminal_failure_count = terminal_failure_count + 1
        end
        error("injected Screenshot() failure")
    end
    screenshot_times[#screenshot_times + 1] = now
end

local function texture_stub()
    return {
        SetColorTexture = function() end,
        SetPoint = function() end,
        ClearAllPoints = function() end,
        SetSize = function() end,
        SetAllPoints = function() end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    }
end

local function frame_stub(name)
    local frame = {
        name = name,
        shown = false,
        width = 1920,
        height = 1080,
        scripts = {},
        events = {},
    }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetScript(kind, callback) self.scripts[kind] = callback end
    function frame:HookScript(kind, callback) self.scripts[kind] = callback end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetLeft() return 0 end
    function frame:GetTop() return self.height end
    function frame:SetPoint() end
    function frame:ClearAllPoints() end
    function frame:SetFrameStrata() end
    function frame:SetAlpha() end
    function frame:SetBackdrop() end
    function frame:SetBackdropColor() end
    function frame:SetBackdropBorderColor() end
    function frame:SetIgnoreParentScale() end
    function frame:SetMovable() end
    function frame:SetClampedToScreen() end
    function frame:RegisterForDrag() end
    function frame:EnableMouse() end
    function frame:SetMouseClickEnabled() end
    function frame:SetMouseMotionEnabled() end
    function frame:SetUserPlaced() end
    function frame:IsUserPlaced() return false end
    function frame:IsMouseOver() return false end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:CreateTexture() return texture_stub() end
    function frame:CreateFontString()
        return {
            SetPoint = function() end,
            SetText = function() end,
            SetTextColor = function() end,
            SetFontObject = function() end,
            SetJustifyH = function() end,
        }
    end
    return frame
end

UIParent = frame_stub("UIParent")
CreateFrame = function(_kind, name)
    local frame = frame_stub(name)
    frames[#frames + 1] = frame
    return frame
end

C_Timer.After = function(delay, callback)
    timers[#timers + 1] = {
        due = now + ((delay and delay > 0) and delay or frame_step),
        callback = callback,
    }
end
C_Timer.NewTicker = function(period, callback)
    local ticker = {
        period = period,
        next_due = now + period,
        callback = callback,
        cancelled = false,
    }
    function ticker:Cancel() self.cancelled = true end
    tickers[#tickers + 1] = ticker
    return ticker
end

ApplicantScoutDB = {
    enabled = true,
    debug = false,
    qrAlwaysVisible = false,
    qrMoveMode = false,
}

local qr_namespace = {}
local qr_chunk = assert(loadfile("libs/qrencode.lua"))
qr_chunk("ApplicantScout", qr_namespace)
local harness = env.load_addon(qr_namespace.QR)

local event_frame = nil
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_ENTERING_WORLD and frame.scripts.OnEvent then
        event_frame = frame
        break
    end
end
assert(event_frame, "addon event frame was not registered")
event_frame.scripts.OnEvent(event_frame, "PLAYER_ENTERING_WORLD")
assert(cvars.screenshotFormat == "png" and cvars.screenshotQuality == "3",
    "PLAYER_ENTERING_WORLD changed screenshot CVars before a capture")

local function drain_due_timers()
    local made_progress = true
    local safety = 10000
    while made_progress do
        made_progress = false
        for index = #timers, 1, -1 do
            if timers[index].due <= now then
                local item = table.remove(timers, index)
                item.callback()
                made_progress = true
                safety = safety - 1
                assert(safety > 0, "timer queue did not settle")
            end
        end
    end
end

local transient_failure_checked = false
local transient_restore_checked = false
local transient_failure_at = nil
for _ = 1, 360 do
    now = now + frame_step
    drain_due_timers()
    for _, ticker in ipairs(tickers) do
        if not ticker.cancelled and ticker.next_due <= now then
            ticker.next_due = ticker.next_due + ticker.period
            ticker.callback()
        end
    end

    if transient_screenshot_failure
       and screenshot_attempts == 1
       and not transient_failure_checked then
        local state = harness.QRTransportState()
        assert(state.pendingShotDirty, "failed capture was not left pending")
        assert(not state.paintInProgress and not state.captureInProgress,
            "failed capture left the transport job active")
        assert(not state.forceVisible and not state.qrFrameShown,
            "failed capture left the QR visibility lease active")
        assert(state.lastSnapshotHash == nil
               and state.deliverySnapshotHash == nil
               and state.deliverySnapshotSendCount == 0,
            "failed capture committed dedup or delivery state")
        assert(state.screenshotFailureHash ~= nil
               and state.screenshotFailureAttemptCount == 1,
            "failed capture did not consume exactly one retry-budget attempt")
        assert(cvars.screenshotFormat == "jpg" and cvars.screenshotQuality == "8",
            "failed capture did not hold the screenshot CVar lease")
        assert(ApplicantScoutDB.priorScreenshotFormat == "png"
               and ApplicantScoutDB.priorScreenshotQuality == 3,
            "failed capture lost the pending screenshot CVar restore state")
        transient_failure_checked = true
        transient_failure_at = now
    end
    if transient_failure_checked
       and not transient_restore_checked
       and screenshot_attempts == 1
       and now - transient_failure_at >= 0.06 then
        assert(cvars.screenshotFormat == "png" and cvars.screenshotQuality == "3",
            "failed capture did not restore screenshot CVars before retry")
        assert(ApplicantScoutDB.priorScreenshotFormat == nil
               and ApplicantScoutDB.priorScreenshotQuality == nil,
            "failed capture left stale screenshot CVar restore state")
        transient_restore_checked = true
    end

    if terminal_clear_mode
       and not terminal_failure_started
       and #screenshot_times == 2 then
        pre_terminal_hash = harness.QRTransportState().lastSnapshotHash
        assert(pre_terminal_hash ~= nil, "pre-terminal delivery hash was not committed")
        terminal_failure_started = true
        applicant_ids = {}
        GetNumGroupMembers = function() return 0 end
        C_LFGList.HasActiveEntryInfo = function() return false end
        C_LFGList.GetActiveEntryInfo = function() return nil end
        harness.EndSession()
    end
end

if transient_screenshot_failure then
    assert(transient_failure_checked and transient_restore_checked,
        "transient failure checkpoints did not run")
    assert(#screenshot_times == 2 and screenshot_attempts == 3,
        string.format("transient failure produced shots=%d attempts=%d, expected 2/3",
            #screenshot_times, screenshot_attempts))
elseif persistent_screenshot_failure then
    local state = harness.QRTransportState()
    assert(#screenshot_times == 0 and screenshot_attempts == 2,
        string.format("persistent failure produced shots=%d attempts=%d, expected 0/2",
            #screenshot_times, screenshot_attempts))
    assert(not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown,
        "persistent failure did not stop in an idle state")
    assert(state.screenshotFailureHash ~= nil
           and state.screenshotFailureAttemptCount == 2,
        "persistent failure did not exhaust the exact retry budget")
elseif terminal_clear_failure then
    local state = harness.QRTransportState()
    assert(terminal_failure_started, "terminal-clear failure phase did not start")
    assert(#screenshot_times == 3 and screenshot_attempts == 4,
        string.format("terminal failure produced shots=%d attempts=%d, expected 3/4",
            #screenshot_times, screenshot_attempts))
    assert(not state.sessionActive
           and not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown
           and not state.terminalClearRetryScheduled,
        "terminal-clear failures did not stop in an idle ended-session state")
    assert(state.terminalClearDispatchCount == 2,
        "terminal clear did not use exactly two serialized dispatches")
    assert(state.lastSnapshotHash ~= nil
           and state.lastSnapshotHash ~= pre_terminal_hash
           and state.deliverySnapshotHash == nil
           and state.deliverySnapshotSendCount == 0,
        "successful terminal retry did not commit terminal delivery state")
elseif terminal_clear_always_fail then
    local state = harness.QRTransportState()
    assert(terminal_failure_started, "terminal-clear failure phase did not start")
    assert(#screenshot_times == 2 and screenshot_attempts == 4,
        string.format("persistent terminal failure produced shots=%d attempts=%d, expected 2/4",
            #screenshot_times, screenshot_attempts))
    assert(not state.sessionActive
           and not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown
           and not state.terminalClearRetryScheduled,
        "persistent terminal failures did not stop in an idle ended-session state")
    assert(state.terminalClearDispatchCount == 2,
        "persistent terminal clear exceeded or missed its dispatch budget")
    assert(state.lastSnapshotHash == pre_terminal_hash,
        "failed terminal captures committed a false delivery hash")
elseif roster_only then
    assert(#screenshot_times == 2, string.format(
        "changed roster-only snapshot got %d captures instead of exactly two",
        #screenshot_times))
else
    assert(#screenshot_times >= 2,
        "polling during the render-settle window starved QR screenshots")
end
if #screenshot_times >= 2 then
    assert(screenshot_times[2] - screenshot_times[1] >= 0.5,
        string.format("redundant resend interval %.3fs ignored the screenshot throttle",
            screenshot_times[2] - screenshot_times[1]))
end
for _, values in ipairs(screenshot_attempt_cvars) do
    assert(values.format == "jpg" and values.quality == "8",
        "QR capture attempt did not hold its JPG/quality 8 CVar lease")
end
assert(cvars.screenshotFormat == "png" and cvars.screenshotQuality == "3",
    "QR capture did not restore screenshot CVars after its lease")
assert(ApplicantScoutDB.priorScreenshotFormat == nil
       and ApplicantScoutDB.priorScreenshotQuality == nil,
    "QR capture left stale screenshot CVar restore state")

print(string.format("ok qr-capture-lifecycle mode=%s shots=%d attempts=%d",
    fixture_mode, #screenshot_times, screenshot_attempts))
