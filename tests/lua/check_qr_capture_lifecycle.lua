local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local fixture_mode = arg and arg[1] or "applicants"
assert(fixture_mode == "applicants"
       or fixture_mode == "roster-only"
       or fixture_mode == "screenshot-failure"
       or fixture_mode == "screenshot-always-fail"
       or fixture_mode == "terminal-clear-failure"
       or fixture_mode == "terminal-clear-always-fail"
       or fixture_mode == "interaction-during-paint"
       or fixture_mode == "interaction-during-settle"
       or fixture_mode == "info-panel-during-settle"
       or fixture_mode == "interaction-force"
       or fixture_mode == "interaction-terminal"
       or fixture_mode == "interaction-world-reset"
       or fixture_mode == "overflow"
       or fixture_mode == "overflow-terminal",
    "unsupported fixture mode: " .. tostring(fixture_mode))
local roster_only = fixture_mode == "roster-only"
local transient_screenshot_failure = fixture_mode == "screenshot-failure"
local persistent_screenshot_failure = fixture_mode == "screenshot-always-fail"
local terminal_clear_failure = fixture_mode == "terminal-clear-failure"
local terminal_clear_always_fail = fixture_mode == "terminal-clear-always-fail"
local terminal_clear_mode = terminal_clear_failure or terminal_clear_always_fail
local interaction_during_paint = fixture_mode == "interaction-during-paint"
local interaction_during_settle = fixture_mode == "interaction-during-settle"
local info_panel_during_settle = fixture_mode == "info-panel-during-settle"
local interaction_force = fixture_mode == "interaction-force"
local interaction_terminal = fixture_mode == "interaction-terminal"
local interaction_world_reset = fixture_mode == "interaction-world-reset"
local overflow_mode = fixture_mode == "overflow"
    or fixture_mode == "overflow-terminal"
local overflow_terminal = fixture_mode == "overflow-terminal"

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
if overflow_mode then
    applicant_ids = {}
    for id = 1, 40 do applicant_ids[#applicant_ids + 1] = id end
end
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
    return {
        applicantID = id,
        applicationStatus = "applied",
        numMembers = overflow_mode and 5 or 1,
    }
end
C_LFGList.GetApplicantMemberInfo = function(id, member_index)
    if member_index < 1 or member_index > (overflow_mode and 5 or 1) then return nil end
    local suffix = tostring(id)
    return "Applicant" .. suffix .. "Member" .. tostring(member_index) .. "-Ravencrest", "PALADIN", nil, nil,
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
local interaction_opened = false
local interaction_deferred_checked = false
local interaction_closed = false
local interaction_opened_at = nil
local interaction_shots_before = nil
local interaction_terminal_started = false

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

local function send_interaction_event(event)
    assert(event_frame.events[event], "interaction event was not registered: " .. event)
    event_frame.scripts.OnEvent(event_frame, event)
end

if interaction_force then
    send_interaction_event("MERCHANT_SHOW")
    SlashCmdList.APSCOUT("shotnow")
end

if interaction_world_reset then
    send_interaction_event("MERCHANT_SHOW")
    assert(harness.QRTransportState().suppressedByInteraction,
        "fixture did not establish stale interaction suppression")
    event_frame.scripts.OnEvent(event_frame, "PLAYER_ENTERING_WORLD")
    assert(not harness.QRTransportState().suppressedByInteraction,
        "PLAYER_ENTERING_WORLD did not clear stale interaction suppression")
end

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
for _ = 1, overflow_mode and 2500 or 360 do
    now = now + frame_step
    drain_due_timers()
    for _, ticker in ipairs(tickers) do
        local hold_info_panel_poll = info_panel_during_settle
            and interaction_opened and not interaction_deferred_checked
        if not ticker.cancelled and ticker.next_due <= now and not hold_info_panel_poll then
            ticker.next_due = ticker.next_due + ticker.period
            ticker.callback()
        end
    end

    if (interaction_during_paint or interaction_during_settle or info_panel_during_settle)
       and not interaction_opened then
        local state = harness.QRTransportState()
        local reached_phase = interaction_during_paint
            and state.paintInProgress and not state.captureInProgress
            or (interaction_during_settle or info_panel_during_settle)
                and state.captureInProgress and state.forceVisible
        if reached_phase then
            interaction_opened = true
            interaction_opened_at = now
            interaction_shots_before = #screenshot_times
            if info_panel_during_settle then
                WorldMapFrame = frame_stub("WorldMapFrame")
                WorldMapFrame.shown = true
            else
                send_interaction_event("MERCHANT_SHOW")
            end
        end
    end
    if interaction_opened
       and not interaction_deferred_checked
       and (interaction_during_paint or interaction_during_settle or info_panel_during_settle) then
        local state = harness.QRTransportState()
        if not state.paintInProgress and not state.captureInProgress then
            assert(#screenshot_times == interaction_shots_before,
                "non-force capture ran after interaction suppression began")
            assert(state.pendingShotDirty,
                "interaction-deferred payload was not retained as pending")
            assert(not state.forceVisible and not state.qrFrameShown,
                "interaction deferral left the QR visibility lease active")
            applicant_ids = { 42, 43 }
            interaction_deferred_checked = true
        end
    end
    if interaction_deferred_checked
       and not interaction_closed
       and now - interaction_opened_at >= 0.75 then
        if info_panel_during_settle then
            WorldMapFrame.shown = false
        else
            send_interaction_event("MERCHANT_CLOSED")
        end
        interaction_closed = true
    end

    if interaction_terminal
       and not interaction_terminal_started
       and #screenshot_times == 2 then
        interaction_terminal_started = true
        send_interaction_event("MERCHANT_SHOW")
        applicant_ids = {}
        GetNumGroupMembers = function() return 0 end
        C_LFGList.HasActiveEntryInfo = function() return false end
        C_LFGList.GetActiveEntryInfo = function() return nil end
        harness.EndSession()
    end
    if overflow_terminal
       and not interaction_terminal_started
       and #screenshot_times == 2 then
        interaction_terminal_started = true
        applicant_ids = {}
        GetNumGroupMembers = function() return 0 end
        C_LFGList.HasActiveEntryInfo = function() return false end
        C_LFGList.GetActiveEntryInfo = function() return nil end
        harness.EndSession()
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
elseif overflow_terminal then
    local state = harness.QRTransportState()
    assert(interaction_terminal_started,
        "overflow terminal checkpoint did not start")
    assert(#screenshot_times == 4 and screenshot_attempts == 4,
        string.format("overflow terminal produced shots=%d attempts=%d, expected 4/4",
            #screenshot_times, screenshot_attempts))
    assert(not state.sessionActive
           and state.overflowState == nil
           and state.deliverySnapshotHash == nil
           and state.deliverySnapshotSendCount == 0
           and state.terminalClearDispatchCount == 2,
        "terminal clear did not cancel overflow and establish final state")
elseif overflow_mode then
    local state = harness.QRTransportState()
    assert(state.overflowState == nil,
        "overflow transport did not finish both bounded passes")
    assert(state.lastSnapshotHash ~= nil
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "overflow completion did not commit one logical delivery")
    assert(state.lastEmittedApplicantCount == 200,
        string.format("overflow restored %d applicant rows instead of 200",
            state.lastEmittedApplicantCount))
    assert(#screenshot_times > 4 and #screenshot_times % 2 == 0,
        "overflow did not capture two complete multi-frame passes")
    for index = 2, #screenshot_times do
        assert(screenshot_times[index] - screenshot_times[index - 1] >= 1.04,
            "overflow screenshots were not paced onto distinct second-scale files")
    end
elseif interaction_during_paint or interaction_during_settle or info_panel_during_settle then
    local state = harness.QRTransportState()
    assert(interaction_opened and interaction_deferred_checked and interaction_closed,
        "interaction race checkpoints did not complete")
    assert(#screenshot_times == 2 and screenshot_attempts == 2,
        string.format("interaction deferral produced shots=%d attempts=%d, expected 2/2",
            #screenshot_times, screenshot_attempts))
    assert(not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown,
        "interaction-deferred transport did not settle after suppression closed")
    assert(state.lastEmittedApplicantCount == 2,
        "interaction retry did not rebuild the latest applicant payload")
elseif interaction_force then
    local state = harness.QRTransportState()
    assert(#screenshot_times == 1 and screenshot_attempts == 1,
        "explicit force capture did not bypass interaction suppression exactly once")
    assert(state.sessionActive
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown,
        "explicit force capture left the suppressed QR active")
elseif interaction_world_reset then
    local state = harness.QRTransportState()
    assert(#screenshot_times == 2 and screenshot_attempts == 2,
        "world-transition recovery did not resume bounded transport")
    assert(not state.suppressedByInteraction
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown,
        "world-transition interaction recovery did not settle")
elseif interaction_terminal then
    local state = harness.QRTransportState()
    assert(interaction_terminal_started,
        "terminal interaction checkpoint did not start")
    assert(#screenshot_times == 4 and screenshot_attempts == 4,
        string.format("terminal interaction produced shots=%d attempts=%d, expected 4/4",
            #screenshot_times, screenshot_attempts))
    assert(not state.sessionActive
           and not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown
           and not state.terminalClearRetryScheduled,
        "terminal force capture did not settle while interaction remained open")
    assert(state.terminalClearDispatchCount == 2,
        "terminal clear did not retain its bounded redundant dispatch")
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
