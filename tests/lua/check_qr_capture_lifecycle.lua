local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local fixture_mode = arg and arg[1] or "applicants"
local restart_phase = fixture_mode == "restart-race" and arg and arg[2] or nil
assert(fixture_mode == "applicants"
       or fixture_mode == "roster-only"
       or fixture_mode == "screenshot-failure"
       or fixture_mode == "screenshot-always-fail"
       or fixture_mode == "screenshot-event-failure"
       or fixture_mode == "screenshot-event-timeout"
       or fixture_mode == "terminal-clear-failure"
       or fixture_mode == "terminal-clear-always-fail"
       or fixture_mode == "interaction-during-paint"
       or fixture_mode == "interaction-during-settle"
       or fixture_mode == "info-panel-during-settle"
       or fixture_mode == "interaction-force"
       or fixture_mode == "interaction-terminal"
       or fixture_mode == "interaction-world-reset"
       or fixture_mode == "interaction-manager-recovery"
       or fixture_mode == "partial-debug"
       or fixture_mode == "overflow"
       or fixture_mode == "overflow-terminal"
       or fixture_mode == "restart-race",
    "unsupported fixture mode: " .. tostring(fixture_mode))
if fixture_mode == "restart-race" then
    assert(restart_phase == "build"
           or restart_phase == "row-scan"
           or restart_phase == "paint"
           or restart_phase == "settle"
           or restart_phase == "overflow-settle",
        "unsupported restart phase: " .. tostring(restart_phase))
end
local roster_only = fixture_mode == "roster-only"
local transient_screenshot_failure = fixture_mode == "screenshot-failure"
local persistent_screenshot_failure = fixture_mode == "screenshot-always-fail"
local screenshot_event_failure = fixture_mode == "screenshot-event-failure"
local screenshot_event_timeout = fixture_mode == "screenshot-event-timeout"
local terminal_clear_failure = fixture_mode == "terminal-clear-failure"
local terminal_clear_always_fail = fixture_mode == "terminal-clear-always-fail"
local terminal_clear_mode = terminal_clear_failure or terminal_clear_always_fail
local interaction_during_paint = fixture_mode == "interaction-during-paint"
local interaction_during_settle = fixture_mode == "interaction-during-settle"
local info_panel_during_settle = fixture_mode == "info-panel-during-settle"
local interaction_force = fixture_mode == "interaction-force"
local interaction_terminal = fixture_mode == "interaction-terminal"
local interaction_world_reset = fixture_mode == "interaction-world-reset"
local interaction_manager_recovery = fixture_mode == "interaction-manager-recovery"
local partial_debug = fixture_mode == "partial-debug"
local overflow_mode = fixture_mode == "overflow"
    or fixture_mode == "overflow-terminal"
    or restart_phase == "overflow-settle"
local overflow_terminal = fixture_mode == "overflow-terminal"
local restart_race = fixture_mode == "restart-race"
local wide_applicants = overflow_mode

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
C_LFGList.GetApplicants = function()
    if partial_debug then error("injected unavailable applicant surface") end
    return applicant_ids
end
C_LFGList.GetApplicantInfo = function(id)
    return {
        applicantID = id,
        applicationStatus = "applied",
        numMembers = wide_applicants and 5 or 1,
    }
end
C_LFGList.GetApplicantMemberInfo = function(id, member_index)
    if member_index < 1 or member_index > (wide_applicants and 5 or 1) then return nil end
    local suffix = tostring(id)
    return "Applicant" .. suffix .. "Member" .. tostring(member_index) .. "-Ravencrest", "PALADIN", nil, nil,
        700 + id / 100, nil, nil, nil, nil, "DAMAGER", nil, 2500 + id,
        nil, nil, nil, 70
end

local now = 1000
local frame_step = 0.033
local timers = {}
local timer_sequence = 0
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
local qr_encode_calls = 0
local qr_encode_successes = 0
local qr_mutation_count = 0
local qr_frame_set_size_count = 0
local event_frame = nil
local interaction_manager_active = {}

Enum = Enum or {}
Enum.PlayerInteractionType = {
    Merchant = 1,
    Gossip = 2,
    QuestGiver = 3,
    MailInfo = 4,
    Banker = 5,
    GuildBanker = 6,
    TaxiNode = 7,
    BarbersChoice = 8,
    TradePartner = 9,
    Auctioneer = 10,
    Professions = 11,
    ProfessionsCraftingOrder = 12,
    ProfessionsCustomerOrder = 13,
}
C_PlayerInteractionManager = {
    IsInteractingWithNpcOfType = function(interactionType)
        return interaction_manager_active[interactionType] == true
    end,
}

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
    assert(event_frame and event_frame.events.SCREENSHOT_STARTED,
        "screenshot lifecycle events were not registered")
    event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_STARTED")
    if screenshot_event_timeout then return end
    if screenshot_event_failure and screenshot_attempts == 1 then
        event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_FAILED")
        return
    end
    screenshot_times[#screenshot_times + 1] = now
    event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
end

local function texture_stub(owner_name)
    local texture = { shown = false }
    local function mutate()
        if owner_name == "ApplicantScoutQRFrame" then
            qr_mutation_count = qr_mutation_count + 1
        end
    end
    function texture:SetColorTexture() mutate() end
    function texture:SetPoint() mutate() end
    function texture:ClearAllPoints() mutate() end
    function texture:SetSize() mutate() end
    function texture:SetAllPoints() mutate() end
    function texture:Show() self.shown = true; mutate() end
    function texture:Hide() self.shown = false; mutate() end
    return texture
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
    function frame:SetSize(width, height)
        self.width, self.height = width, height
        if self.name == "ApplicantScoutQRFrame" then
            qr_mutation_count = qr_mutation_count + 1
            qr_frame_set_size_count = qr_frame_set_size_count + 1
        end
    end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetLeft() return 0 end
    function frame:GetTop() return self.height end
    function frame:SetPoint()
        if self.name == "ApplicantScoutQRFrame" then
            qr_mutation_count = qr_mutation_count + 1
        end
    end
    function frame:ClearAllPoints()
        if self.name == "ApplicantScoutQRFrame" then
            qr_mutation_count = qr_mutation_count + 1
        end
    end
    function frame:SetFrameStrata(strata) self.strata = strata end
    function frame:GetFrameStrata() return self.strata end
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
    function frame:Show()
        self.shown = true
        if self.name == "ApplicantScoutQRFrame" then
            qr_mutation_count = qr_mutation_count + 1
        end
    end
    function frame:Hide()
        self.shown = false
        if self.name == "ApplicantScoutQRFrame" then
            qr_mutation_count = qr_mutation_count + 1
        end
    end
    function frame:CreateTexture() return texture_stub(self.name) end
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
    timer_sequence = timer_sequence + 1
    timers[#timers + 1] = {
        due = now + ((delay and delay > 0) and delay or frame_step),
        callback = callback,
        sequence = timer_sequence,
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
    debug = partial_debug,
    qrAlwaysVisible = false,
    qrMoveMode = false,
}

local qr_namespace = {}
local qr_chunk = assert(loadfile("libs/qrencode.lua"))
qr_chunk("ApplicantScout", qr_namespace)
local original_qrcode = assert(qr_namespace.QR.qrcode)
qr_namespace.QR.qrcode = function(...)
    qr_encode_calls = qr_encode_calls + 1
    local ok, result = original_qrcode(...)
    if ok then qr_encode_successes = qr_encode_successes + 1 end
    return ok, result
end
local harness = env.load_addon(qr_namespace.QR)

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
    if event == "MERCHANT_SHOW" then
        interaction_manager_active[Enum.PlayerInteractionType.Merchant] = true
    elseif event == "MERCHANT_CLOSED" then
        interaction_manager_active[Enum.PlayerInteractionType.Merchant] = nil
    end
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
    interaction_manager_active[Enum.PlayerInteractionType.Merchant] = nil
    event_frame.scripts.OnEvent(event_frame, "PLAYER_ENTERING_WORLD")
    assert(not harness.QRTransportState().suppressedByInteraction,
        "PLAYER_ENTERING_WORLD did not clear stale interaction suppression")
end

if interaction_manager_recovery then
    send_interaction_event("MERCHANT_SHOW")
    assert(harness.QRTransportState().suppressedByInteraction,
        "fixture did not establish interaction suppression")
    -- Simulate a missed MERCHANT_CLOSED: only Blizzard's authoritative manager
    -- state changes. The normal poll must repair the stale legacy slot.
    interaction_manager_active[Enum.PlayerInteractionType.Merchant] = nil
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

local function earliest_timer_index()
    local selected = nil
    for index, item in ipairs(timers) do
        if not selected
           or item.due < timers[selected].due
           or (item.due == timers[selected].due
               and item.sequence < timers[selected].sequence) then
            selected = index
        end
    end
    return selected
end

local function take_earliest_timer()
    local index = earliest_timer_index()
    if not index then return nil end
    return table.remove(timers, index)
end

local function run_earliest_timer()
    local item = take_earliest_timer()
    assert(item, "expected a queued timer")
    now = math.max(now, item.due)
    item.callback()
    return item
end

local function take_settle_timer(capture_at)
    local target_due = capture_at + 0.3
    local selected = nil
    for index, item in ipairs(timers) do
        if math.abs(item.due - target_due) < 0.000001
           and (not selected
                or item.sequence > timers[selected].sequence) then
            selected = index
        end
    end
    assert(selected, "capture settle callback was not queued")
    return table.remove(timers, selected)
end

local transport_state_fields = {
    "pendingShotDirty",
    "lastSnapshotHash",
    "deliverySnapshotHash",
    "deliverySnapshotSendCount",
    "paintInProgress",
    "captureInProgress",
    "forceVisible",
    "alwaysVisible",
    "qrFrameShown",
    "screenshotFailureHash",
    "screenshotFailureAttemptCount",
    "screenshotAwaitingResult",
    "screenshotLastResult",
    "qrFrameStrata",
    "terminalClearDispatchCount",
    "terminalClearRetryScheduled",
    "lastEmittedApplicantCount",
    "overflowState",
    "overflowLastFailure",
    "overflowSupersededCount",
    "sessionActive",
    "suppressedByInteraction",
}

local function assert_transport_state_equal(before, after)
    for _, field in ipairs(transport_state_fields) do
        assert(after[field] == before[field],
            "stale " .. tostring(restart_phase)
            .. " callback mutated fresh transport field " .. field)
    end
end

local restart_started = false
local stale_callback_replayed = false
local stale_callback = nil
local restart_shots_before = nil
local restart_attempts_before = nil
local stale_overflow_state = nil
local stale_overflow_chunk_index = nil
local stale_overflow_pass = nil

local function start_fresh_session_after_staging()
    wide_applicants = false
    applicant_ids = { 91, 92 }
    restart_shots_before = #screenshot_times
    restart_attempts_before = screenshot_attempts
    harness.StartSession()
    local state = harness.QRTransportState()
    assert(state.sessionActive, "fresh session did not start")
    assert(state.lastSnapshotHash == nil
           and state.deliverySnapshotHash == nil
           and state.deliverySnapshotSendCount == 0
           and state.lastEmittedApplicantCount == 0
           and state.overflowState == nil,
        "fresh session inherited stale delivery state")
    restart_started = true
end

local function stage_terminal_restart_callback()
    timers = {}
    harness.EndSession()
    if restart_phase == "build" then
        stale_callback = assert(take_earliest_timer()).callback
    elseif restart_phase == "row-scan" then
        local success_before = qr_encode_successes
        run_earliest_timer()
        assert(qr_encode_successes > success_before,
            "terminal QR encode did not reach row-scan staging")
        stale_callback = assert(take_earliest_timer()).callback
    elseif restart_phase == "paint" then
        local size_before = qr_frame_set_size_count
        local safety = 1000
        while qr_frame_set_size_count == size_before do
            run_earliest_timer()
            safety = safety - 1
            assert(safety > 0, "terminal QR did not reach paint staging")
        end
        stale_callback = assert(take_earliest_timer()).callback
    elseif restart_phase == "settle" then
        local state = harness.QRTransportState()
        local safety = 1000
        while not state.captureInProgress do
            run_earliest_timer()
            state = harness.QRTransportState()
            safety = safety - 1
            assert(safety > 0, "terminal QR did not reach settle staging")
        end
        stale_callback = take_settle_timer(now).callback
    else
        error("terminal staging received unexpected phase " .. tostring(restart_phase))
    end
    start_fresh_session_after_staging()
end

local transient_failure_checked = false
local transient_restore_checked = false
local transient_failure_at = nil
for _ = 1, overflow_mode and 2500 or screenshot_event_timeout and 650 or 360 do
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

    if restart_race and not restart_started then
        local state = harness.QRTransportState()
        if restart_phase == "overflow-settle"
           and #screenshot_times == 0
           and state.captureInProgress
           and state.forceVisible
           and state.overflowState then
            local item = take_settle_timer(now)
            stale_callback = item.callback
            stale_overflow_state = state.overflowState
            stale_overflow_chunk_index = stale_overflow_state.chunkIndex
            stale_overflow_pass = stale_overflow_state.pass
            harness.EndSession()
            start_fresh_session_after_staging()
        elseif restart_phase ~= "overflow-settle"
           and #screenshot_times == 2
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and cvars.screenshotFormat == "png"
           and cvars.screenshotQuality == "3" then
            stage_terminal_restart_callback()
        end
    end

    if restart_race and restart_started and not stale_callback_replayed then
        local before = harness.QRTransportState()
        if before.sessionActive
           and before.captureInProgress
           and before.forceVisible
           and before.terminalClearDispatchCount == 0 then
            local shots_before = #screenshot_times
            local attempts_before = screenshot_attempts
            local timers_before = #timers
            local encodes_before = qr_encode_calls
            local mutations_before = qr_mutation_count
            assert(stale_callback, "restart fixture lost its stale callback")
            stale_callback()
            local after = harness.QRTransportState()
            assert(#screenshot_times == shots_before
                   and screenshot_attempts == attempts_before,
                "stale callback captured a terminal or overflow frame")
            assert(#timers == timers_before,
                "stale callback scheduled work into the fresh session")
            assert(qr_encode_calls == encodes_before,
                "stale callback restarted QR encoding")
            assert(qr_mutation_count == mutations_before,
                "stale callback mutated fresh QR frame textures")
            assert_transport_state_equal(before, after)
            if stale_overflow_state then
                assert(stale_overflow_state.chunkIndex == stale_overflow_chunk_index
                       and stale_overflow_state.pass == stale_overflow_pass,
                    "stale overflow settle advanced the retired fragment stream")
            end
            stale_callback_replayed = true
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

    if (transient_screenshot_failure or screenshot_event_failure)
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

if transient_screenshot_failure or screenshot_event_failure then
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
elseif screenshot_event_timeout then
    local state = harness.QRTransportState()
    assert(#screenshot_times == 0 and screenshot_attempts == 2,
        string.format("missing result events produced shots=%d attempts=%d, expected 0/2",
            #screenshot_times, screenshot_attempts))
    assert(not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.screenshotAwaitingResult
           and not state.forceVisible
           and not state.qrFrameShown,
        "missing result events did not recover to an idle state")
    assert(state.screenshotFailureHash ~= nil
           and state.screenshotFailureAttemptCount == 2,
        "missing result events did not exhaust the bounded retry budget")
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
elseif restart_race then
    local state = harness.QRTransportState()
    assert(restart_started and stale_callback_replayed,
        "restart race did not stage and replay its stale callback")
    assert(#screenshot_times - restart_shots_before == 2
           and screenshot_attempts - restart_attempts_before == 2,
        string.format(
            "fresh restart produced shots=%d attempts=%d instead of 2/2",
            #screenshot_times - restart_shots_before,
            screenshot_attempts - restart_attempts_before
        ))
    assert(screenshot_times[restart_shots_before + 2]
           - screenshot_times[restart_shots_before + 1] >= 0.5,
        "fresh restart resend ignored the screenshot throttle")
    assert(state.sessionActive
           and not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown
           and state.overflowState == nil,
        "fresh restart transport did not settle in its active idle state")
    assert(state.lastSnapshotHash ~= nil
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2
           and state.lastEmittedApplicantCount == 2,
        "fresh restart did not commit its exact bounded delivery state")
    assert(state.terminalClearDispatchCount == 0
           and not state.terminalClearRetryScheduled,
        "stale terminal work mutated the fresh session clear state")
    if stale_overflow_state then
        assert(stale_overflow_state.chunkIndex == stale_overflow_chunk_index
               and stale_overflow_state.pass == stale_overflow_pass,
            "retired overflow stream advanced after stale callback drain")
    end
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
elseif interaction_world_reset or interaction_manager_recovery then
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
local final_state = harness.QRTransportState()
assert(not final_state.screenshotAwaitingResult,
    "QR capture left a stale SCREENSHOT_* result waiter")
assert(final_state.qrFrameStrata == "DIALOG",
    "QR capture did not restore DIALOG frame strata")

print(string.format("ok qr-capture-lifecycle mode=%s shots=%d attempts=%d",
    fixture_mode, #screenshot_times, screenshot_attempts))
