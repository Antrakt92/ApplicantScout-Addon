local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local fixture_mode = arg and arg[1] or "applicants"
local restart_phase = fixture_mode == "restart-race" and arg and arg[2] or nil
local idle_force_phase = fixture_mode == "disable-idle-force" and arg and arg[2] or nil
assert(fixture_mode == "applicants"
       or fixture_mode == "roster-only"
       or fixture_mode == "screenshot-failure"
       or fixture_mode == "screenshot-always-fail"
       or fixture_mode == "screenshot-event-failure"
       or fixture_mode == "screenshot-event-timeout"
       or fixture_mode == "screenshot-overlap-terminal"
       or fixture_mode == "screenshot-overlap-restart"
       or fixture_mode == "screenshot-overlap-shotnow"
       or fixture_mode == "terminal-shotnow-priority"
       or fixture_mode == "terminal-clear-failure"
       or fixture_mode == "terminal-clear-always-fail"
       or fixture_mode == "terminal-repeat-disable"
       or fixture_mode == "disable-idle-force"
       or fixture_mode == "disable-idle-force-overlap"
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
       or fixture_mode == "listing-recreate"
       or fixture_mode == "gameplay-combat"
       or fixture_mode == "gameplay-combat-during-paint"
       or fixture_mode == "gameplay-combat-during-settle"
       or fixture_mode == "gameplay-challenge-reload"
       or fixture_mode == "gameplay-raid-encounter"
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
if fixture_mode == "disable-idle-force" then
    assert(idle_force_phase == "build"
           or idle_force_phase == "row-scan"
           or idle_force_phase == "paint"
           or idle_force_phase == "settle",
        "unsupported idle force phase: " .. tostring(idle_force_phase))
end
local roster_only = fixture_mode == "roster-only"
local transient_screenshot_failure = fixture_mode == "screenshot-failure"
local persistent_screenshot_failure = fixture_mode == "screenshot-always-fail"
local screenshot_event_failure = fixture_mode == "screenshot-event-failure"
local screenshot_event_timeout = fixture_mode == "screenshot-event-timeout"
local screenshot_overlap_terminal = fixture_mode == "screenshot-overlap-terminal"
local screenshot_overlap_restart = fixture_mode == "screenshot-overlap-restart"
local screenshot_overlap = screenshot_overlap_terminal or screenshot_overlap_restart
local screenshot_overlap_shotnow = fixture_mode == "screenshot-overlap-shotnow"
local terminal_shotnow_priority = fixture_mode == "terminal-shotnow-priority"
local terminal_clear_failure = fixture_mode == "terminal-clear-failure"
local terminal_clear_always_fail = fixture_mode == "terminal-clear-always-fail"
local terminal_clear_mode = terminal_clear_failure or terminal_clear_always_fail
local terminal_repeat_disable = fixture_mode == "terminal-repeat-disable"
local disable_idle_force = fixture_mode == "disable-idle-force"
local disable_idle_force_overlap = fixture_mode == "disable-idle-force-overlap"
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
local listing_recreate = fixture_mode == "listing-recreate"
local gameplay_combat = fixture_mode == "gameplay-combat"
local gameplay_combat_during_paint = fixture_mode == "gameplay-combat-during-paint"
local gameplay_combat_during_settle = fixture_mode == "gameplay-combat-during-settle"
local gameplay_challenge_reload = fixture_mode == "gameplay-challenge-reload"
local gameplay_raid_encounter = fixture_mode == "gameplay-raid-encounter"
local wide_applicants = overflow_mode or listing_recreate

-- Default mode reproduces the live report: two people and five applicants.
-- Roster-only mode keeps a full party and removes every applicant.
if not roster_only then
    env.unit_data.party2 = nil
    env.unit_data.party3 = nil
    env.unit_data.party4 = nil
end
GetNumGroupMembers = function() return roster_only and 5 or 2 end
IsInRaid = function() return false end
local combat_active = gameplay_combat
local combat_api_unavailable = false
local challenge_active = gameplay_challenge_reload
local encounter_active = false
local gameplay_lfg_read_calls = 0
InCombatLockdown = function()
    if combat_api_unavailable then
        error("injected unavailable combat state")
    end
    return combat_active
end
C_ChallengeMode = {
    IsChallengeModeActive = function() return challenge_active end,
}
C_InstanceEncounter = {
    IsEncounterInProgress = function() return encounter_active end,
}

local applicant_ids = roster_only and {} or { 42, 43, 44, 45, 46 }
if wide_applicants then
    applicant_ids = {}
    for id = 1, 40 do applicant_ids[#applicant_ids + 1] = id end
end
C_LFGList.HasActiveEntryInfo = function()
    gameplay_lfg_read_calls = gameplay_lfg_read_calls + 1
    return true
end
C_LFGList.GetActiveEntryInfo = function()
    gameplay_lfg_read_calls = gameplay_lfg_read_calls + 1
    return {
        activityIDs = { 401 },
        questID = 0,
        name = "Capture lifecycle fixture",
        comment = "five applicants and two party members",
    }
end
C_LFGList.GetApplicants = function()
    gameplay_lfg_read_calls = gameplay_lfg_read_calls + 1
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
local midflight_combat_lfg_read_calls = 0
local raid_encounter_lfg_read_calls = 0
local event_frame = nil
local interaction_manager_active = {}
local interaction_manager_query_calls = 0
local delayed_screenshot_result = false
local screenshot_overlap_started = false
local screenshot_overlap_old_result_checked = false
local screenshot_overlap_new_result_checked = false
local screenshot_shotnow_started = false
local screenshot_shotnow_result_checked = false
local terminal_shotnow_started = false
local terminal_shotnow_await_checked = false
local terminal_shotnow_retry_checked = false
local terminal_repeat_disable_started = false
local terminal_repeat_disable_visibility_checks = 0
local idle_force_terminal_started = false
local idle_force_started = false
local idle_force_cancel_checked = false
local idle_force_overlap_checked = false
local idle_force_attempts_before = nil
local idle_force_interaction_queries_after_disable = nil
local harness = nil

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
        interaction_manager_query_calls = interaction_manager_query_calls + 1
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
    local transport_state = harness and harness.QRTransportState()
    if terminal_repeat_disable
       and transport_state
       and transport_state.terminalClearDispatchCount > 0 then
        SlashCmdList.APSCOUT("off")
        transport_state = harness.QRTransportState()
        terminal_repeat_disable_visibility_checks =
            terminal_repeat_disable_visibility_checks + 1
        assert(transport_state.captureInProgress
               and transport_state.forceVisible
               and transport_state.qrFrameShown,
            "repeated disable hid the QR during a terminal capture lease")
    end
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
    if (screenshot_overlap or screenshot_overlap_shotnow)
       and screenshot_attempts == 1 then
        delayed_screenshot_result = true
        return
    end
    if terminal_shotnow_priority and screenshot_attempts == 3 then
        delayed_screenshot_result = true
        return
    end
    if disable_idle_force_overlap
       and idle_force_started
       and screenshot_attempts == 5 then
        delayed_screenshot_result = true
        return
    end
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
harness = env.load_addon(qr_namespace.QR)

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

if gameplay_combat or gameplay_challenge_reload then
    local state = harness.QRTransportState()
    assert(state.suppressedByGameplay and not state.qrFrameShown,
        "reload did not recover active gameplay suppression")
    if gameplay_combat then
        SlashCmdList.APSCOUT("shotnow")
        state = harness.QRTransportState()
        assert(state.screenshotPendingForce and #screenshot_times == 0,
            "manual force capture was not deferred during combat")
    end
end

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
    "screenshotAwaitingSuperseded",
    "screenshotPendingForce",
    "screenshotPendingTerminalClear",
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
local listing_recreate_started = false
local retired_listing_overflow = nil
local gameplay_released = false
local gameplay_release_at = now + 1.0
local raid_encounter_started = false
local raid_encounter_released = false
local raid_encounter_release_at = nil
local raid_encounter_encode_calls = nil
local midflight_combat_started = false
local midflight_combat_released = false
local midflight_combat_release_at = nil
local midflight_combat_encode_calls = nil
for _ = 1, (overflow_mode or listing_recreate) and 2500
        or screenshot_event_timeout and 650 or 360 do
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

    if screenshot_overlap
       and not screenshot_overlap_started
       and screenshot_attempts == 1
       and harness.QRTransportState().screenshotAwaitingResult then
        screenshot_overlap_started = true
        applicant_ids = {}
        GetNumGroupMembers = function() return 0 end
        C_LFGList.HasActiveEntryInfo = function() return false end
        C_LFGList.GetActiveEntryInfo = function() return nil end
        harness.EndSession()
        local queued = harness.QRTransportState()
        assert(screenshot_attempts == 1,
            "terminal capture overlapped the unresolved screenshot")
        assert(queued.screenshotAwaitingResult
               and queued.screenshotAwaitingSuperseded
               and queued.screenshotPendingForce
               and queued.screenshotPendingTerminalClear,
            "terminal capture was not queued behind the unresolved screenshot")
        if screenshot_overlap_restart then
            applicant_ids = { 91, 92 }
            GetNumGroupMembers = function() return 2 end
            C_LFGList.HasActiveEntryInfo = function() return true end
            C_LFGList.GetActiveEntryInfo = function()
                return {
                    activityIDs = { 401 },
                    questID = 0,
                    name = "Replacement capture lifecycle fixture",
                    comment = "fresh session after queued terminal",
                }
            end
            harness.StartSession()
            local restarted = harness.QRTransportState()
            assert(restarted.sessionActive
                   and not restarted.screenshotPendingForce
                   and not restarted.screenshotPendingTerminalClear,
                "fresh session did not cancel the queued terminal capture")
        end
        assert(delayed_screenshot_result, "fixture lost the delayed screenshot result")
        screenshot_times[#screenshot_times + 1] = now
        event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
        local after_old = harness.QRTransportState()
        assert(screenshot_attempts == 1,
            "old screenshot result synchronously launched a second Screenshot()")
        assert(after_old.lastSnapshotHash == nil
               and after_old.deliverySnapshotHash == nil
               and after_old.deliverySnapshotSendCount == 0,
            "old screenshot result committed replacement delivery state")
        if screenshot_overlap_terminal then
            assert(not after_old.sessionActive
                   and after_old.paintInProgress
                   and after_old.terminalClearDispatchCount == 1,
                "old result did not start exactly one queued terminal job")
        else
            assert(after_old.sessionActive
                   and after_old.terminalClearDispatchCount == 0,
                "old result revived terminal work after a fresh session")
        end
        screenshot_overlap_old_result_checked = true
    end

    if screenshot_overlap_old_result_checked
       and not screenshot_overlap_new_result_checked
       and screenshot_attempts >= 2 then
        local after_new = harness.QRTransportState()
        assert(after_new.lastSnapshotHash ~= nil,
            "replacement screenshot result did not commit its own delivery")
        if screenshot_overlap_terminal then
            assert(after_new.deliverySnapshotHash == nil
                   and after_new.deliverySnapshotSendCount == 0,
                "terminal screenshot result committed nonterminal delivery state")
        else
            assert(after_new.deliverySnapshotHash == after_new.lastSnapshotHash,
                "fresh-session screenshot did not commit fresh delivery state")
        end
        screenshot_overlap_new_result_checked = true
    end

    if screenshot_overlap_shotnow
       and not screenshot_shotnow_started
       and screenshot_attempts == 1
       and harness.QRTransportState().screenshotAwaitingResult then
        screenshot_shotnow_started = true
        SlashCmdList.APSCOUT("shotnow")
        local queued = harness.QRTransportState()
        assert(screenshot_attempts == 1,
            "manual force overlapped the unresolved screenshot")
        assert(queued.screenshotAwaitingResult
               and not queued.screenshotAwaitingSuperseded
               and queued.screenshotPendingForce
               and not queued.screenshotPendingTerminalClear,
            "manual force did not queue behind the valid screenshot")
        assert(delayed_screenshot_result,
            "fixture lost the delayed ordinary screenshot result")
        screenshot_times[#screenshot_times + 1] = now
        event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
        local after_old = harness.QRTransportState()
        assert(screenshot_attempts == 1,
            "old ordinary result synchronously launched another Screenshot()")
        assert(after_old.lastSnapshotHash ~= nil
               and after_old.deliverySnapshotHash == after_old.lastSnapshotHash
               and after_old.deliverySnapshotSendCount == 1,
            "valid ordinary result was discarded by queued shotnow")
        assert(after_old.paintInProgress
               and not after_old.screenshotPendingForce,
            "queued shotnow did not start after the ordinary result")
    end

    if screenshot_shotnow_started
       and not screenshot_shotnow_result_checked
       and screenshot_attempts >= 2 then
        local after_manual = harness.QRTransportState()
        assert(after_manual.deliverySnapshotHash == after_manual.lastSnapshotHash
               and after_manual.deliverySnapshotSendCount == 2,
            "queued shotnow did not commit the second valid delivery")
        screenshot_shotnow_result_checked = true
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
    if (disable_idle_force or disable_idle_force_overlap)
       and not idle_force_terminal_started
       and #screenshot_times == 2 then
        idle_force_terminal_started = true
        applicant_ids = {}
        GetNumGroupMembers = function() return 0 end
        C_LFGList.HasActiveEntryInfo = function() return false end
        C_LFGList.GetActiveEntryInfo = function() return nil end
        harness.EndSession()
    end
    if terminal_repeat_disable
       and not terminal_repeat_disable_started
       and #screenshot_times == 2 then
        terminal_repeat_disable_started = true
        applicant_ids = {}
        GetNumGroupMembers = function() return 0 end
        C_LFGList.HasActiveEntryInfo = function() return false end
        C_LFGList.GetActiveEntryInfo = function() return nil end
        harness.EndSession()
    end

    if (disable_idle_force or disable_idle_force_overlap)
       and idle_force_terminal_started
       and not idle_force_started then
        local state = harness.QRTransportState()
        if #screenshot_times == 4
           and state.terminalClearDispatchCount == 2
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.terminalClearRetryScheduled then
            idle_force_started = true
            idle_force_attempts_before = screenshot_attempts
            local encode_successes_before = qr_encode_successes
            local frame_sizes_before = qr_frame_set_size_count
            SlashCmdList.APSCOUT("shotnow")

            if disable_idle_force then
                if idle_force_phase == "row-scan" then
                    local safety = 1000
                    while qr_encode_successes == encode_successes_before do
                        run_earliest_timer()
                        safety = safety - 1
                        assert(safety > 0, "idle force did not reach row-scan staging")
                    end
                elseif idle_force_phase == "paint" then
                    local safety = 1000
                    while qr_frame_set_size_count == frame_sizes_before do
                        run_earliest_timer()
                        safety = safety - 1
                        assert(safety > 0, "idle force did not reach paint staging")
                    end
                elseif idle_force_phase == "settle" then
                    local staged = harness.QRTransportState()
                    local safety = 1000
                    while not staged.captureInProgress do
                        run_earliest_timer()
                        staged = harness.QRTransportState()
                        safety = safety - 1
                        assert(safety > 0, "idle force did not reach settle staging")
                    end
                end

                local staged = harness.QRTransportState()
                assert(staged.paintInProgress or staged.captureInProgress,
                    "idle force fixture did not stage async QR work")
                SlashCmdList.APSCOUT("off")
                local cancelled = harness.QRTransportState()
                idle_force_interaction_queries_after_disable =
                    interaction_manager_query_calls
                assert(not cancelled.paintInProgress
                       and not cancelled.captureInProgress
                       and not cancelled.forceVisible
                       and not cancelled.qrFrameShown
                       and not cancelled.screenshotPendingForce,
                    "disable did not cancel idle manual force work")
                idle_force_cancel_checked = true
            end
        end
    end

    if (gameplay_combat or gameplay_challenge_reload)
       and not gameplay_released
       and now >= gameplay_release_at then
        local state = harness.QRTransportState()
        assert(#screenshot_times == 0 and screenshot_attempts == 0
               and qr_encode_calls == 0
               and gameplay_lfg_read_calls == 0
               and state.suppressedByGameplay
               and not state.paintInProgress
               and not state.captureInProgress
               and not state.qrFrameShown,
            "gameplay suppression allowed transport polling before release")
        if gameplay_combat then
            combat_active = false
            assert(event_frame.events.PLAYER_REGEN_ENABLED,
                "PLAYER_REGEN_ENABLED was not registered")
            event_frame.scripts.OnEvent(event_frame, "PLAYER_REGEN_ENABLED")
        else
            challenge_active = false
            assert(event_frame.events.CHALLENGE_MODE_COMPLETED,
                "CHALLENGE_MODE_COMPLETED was not registered")
            event_frame.scripts.OnEvent(event_frame, "CHALLENGE_MODE_COMPLETED")
        end
        gameplay_released = true
    end

    if (gameplay_combat_during_paint or gameplay_combat_during_settle)
       and not midflight_combat_started then
        local state = harness.QRTransportState()
        local targetReached = gameplay_combat_during_paint
            and state.paintInProgress
            and not state.captureInProgress
            or gameplay_combat_during_settle
            and state.captureInProgress
            and state.forceVisible
        if targetReached then
            combat_active = true
            combat_api_unavailable = gameplay_combat_during_paint
            assert(event_frame.events.PLAYER_REGEN_DISABLED,
                "PLAYER_REGEN_DISABLED was not registered")
            event_frame.scripts.OnEvent(event_frame, "PLAYER_REGEN_DISABLED")
            state = harness.QRTransportState()
            assert(state.suppressedByGameplay
                   and state.gameplaySuppressionReason == "combat"
                   and not state.paintInProgress
                   and not state.captureInProgress
                   and not state.forceVisible
                   and not state.qrFrameShown,
                "combat did not cancel and hide mid-flight QR work")
            midflight_combat_encode_calls = qr_encode_calls
            midflight_combat_lfg_read_calls = gameplay_lfg_read_calls
            midflight_combat_release_at = now + 1.0
            midflight_combat_started = true
        end
    elseif (gameplay_combat_during_paint or gameplay_combat_during_settle)
       and midflight_combat_started
       and not midflight_combat_released
       and now >= midflight_combat_release_at then
        assert(#screenshot_times == 0 and screenshot_attempts == 0
               and qr_encode_calls == midflight_combat_encode_calls
               and gameplay_lfg_read_calls == midflight_combat_lfg_read_calls,
            "mid-flight combat suppression allowed later transport polling")
        combat_active = false
        combat_api_unavailable = false
        event_frame.scripts.OnEvent(event_frame, "PLAYER_REGEN_ENABLED")
        midflight_combat_released = true
    end

    if gameplay_raid_encounter and not raid_encounter_started then
        local state = harness.QRTransportState()
        if #screenshot_times == 2
           and not state.paintInProgress
           and not state.captureInProgress then
            applicant_ids = { 42, 43, 44, 45 }
            encounter_active = true
            assert(event_frame.events.ENCOUNTER_START,
                "ENCOUNTER_START was not registered")
            event_frame.scripts.OnEvent(event_frame, "ENCOUNTER_START", 9001)
            state = harness.QRTransportState()
            assert(state.suppressedByGameplay
                   and state.gameplaySuppressionReason == "raid-encounter"
                   and not state.qrFrameShown,
                "raid encounter did not suppress QR transport")
            raid_encounter_encode_calls = qr_encode_calls
            raid_encounter_lfg_read_calls = gameplay_lfg_read_calls
            raid_encounter_release_at = now + 1.0
            raid_encounter_started = true
        end
    elseif gameplay_raid_encounter
       and raid_encounter_started
       and not raid_encounter_released
       and now >= raid_encounter_release_at then
        assert(#screenshot_times == 2 and screenshot_attempts == 2
               and qr_encode_calls == raid_encounter_encode_calls
               and gameplay_lfg_read_calls == raid_encounter_lfg_read_calls,
            "raid boss encounter allowed QR build, capture, or LFG polling")
        -- Simulate a lost ENCOUNTER_END event. The current-state API is the
        -- authoritative recovery surface and must clear the event fallback.
        encounter_active = false
        raid_encounter_released = true
    end

    if listing_recreate and not listing_recreate_started then
        local state = harness.QRTransportState()
        if state.overflowState then
            assert(#screenshot_times == 0,
                "old listing captured before recreate boundary was staged")
            retired_listing_overflow = state.overflowState
            applicant_ids = {}
            wide_applicants = false
            C_LFGList.HasActiveEntryInfo = function() return false end
            C_LFGList.GetActiveEntryInfo = function() return nil end
            harness.CheckSessionTransition(true)

            local party_only = harness.QRTransportState()
            assert(party_only.sessionActive,
                "group roster did not keep transport alive after delist")
            assert(party_only.overflowState == nil
                   and party_only.lastSnapshotHash == nil
                   and party_only.deliverySnapshotHash == nil
                   and party_only.deliverySnapshotSendCount == 0,
                "delist boundary retained stale listing delivery state")

            C_LFGList.HasActiveEntryInfo = function() return true end
            C_LFGList.GetActiveEntryInfo = function()
                return {
                    activityIDs = { 401 },
                    questID = 0,
                    name = "Recreated capture lifecycle fixture",
                    comment = "same group, fresh empty applicant list",
                }
            end
            harness.CheckSessionTransition(true)
            local recreated = harness.QRTransportState()
            assert(recreated.sessionActive
                   and recreated.overflowState == nil
                   and recreated.lastSnapshotHash == nil
                   and recreated.deliverySnapshotHash == nil,
                "recreated listing inherited stale transport state")
            listing_recreate_started = true
        end
    end

    if disable_idle_force_overlap
       and idle_force_started
       and not idle_force_overlap_checked
       and screenshot_attempts == 5
       and harness.QRTransportState().screenshotAwaitingResult then
        SlashCmdList.APSCOUT("shotnow")
        local queued = harness.QRTransportState()
        assert(queued.screenshotPendingForce,
            "idle overlap fixture did not queue a second manual force")
        SlashCmdList.APSCOUT("off")
        local disabled = harness.QRTransportState()
        assert(disabled.screenshotAwaitingResult
               and not disabled.screenshotPendingForce,
            "disable orphaned the physical result or retained queued manual force")
        assert(delayed_screenshot_result,
            "idle overlap fixture lost the delayed screenshot result")
        screenshot_times[#screenshot_times + 1] = now
        event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
        idle_force_overlap_checked = true
    end

    if terminal_shotnow_priority
       and not terminal_shotnow_started
       and #screenshot_times == 2 then
        terminal_shotnow_started = true
        pre_terminal_hash = harness.QRTransportState().lastSnapshotHash
        assert(pre_terminal_hash ~= nil,
            "terminal shotnow fixture lacks a delivered pre-terminal snapshot")
        applicant_ids = {}
        GetNumGroupMembers = function() return 0 end
        C_LFGList.HasActiveEntryInfo = function() return false end
        C_LFGList.GetActiveEntryInfo = function() return nil end
        harness.EndSession()
        local building = harness.QRTransportState()
        assert(building.paintInProgress
               and building.terminalClearDispatchCount == 1,
            "terminal shotnow fixture did not start the first clear")
        SlashCmdList.APSCOUT("shotnow")
        local after_build_shotnow = harness.QRTransportState()
        assert(after_build_shotnow.paintInProgress
               and after_build_shotnow.terminalClearDispatchCount == 1
               and not after_build_shotnow.screenshotPendingForce,
            "shotnow replaced terminal work during build/paint")
    end

    if terminal_shotnow_started
       and not terminal_shotnow_await_checked
       and screenshot_attempts == 3
       and harness.QRTransportState().screenshotAwaitingResult then
        SlashCmdList.APSCOUT("shotnow")
        local awaiting = harness.QRTransportState()
        assert(screenshot_attempts == 3
               and awaiting.screenshotAwaitingResult
               and not awaiting.screenshotAwaitingSuperseded
               and not awaiting.screenshotPendingForce,
            "shotnow replaced the terminal physical result waiter")
        screenshot_times[#screenshot_times + 1] = now
        event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
        local retrying = harness.QRTransportState()
        assert(retrying.deliverySnapshotHash == nil
               and retrying.deliverySnapshotSendCount == 0
               and retrying.terminalClearRetryScheduled,
            "terminal result did not commit clear state and schedule its retry")
        terminal_shotnow_await_checked = true
        SlashCmdList.APSCOUT("shotnow")
        local after_retry_shotnow = harness.QRTransportState()
        assert(screenshot_attempts == 3
               and after_retry_shotnow.terminalClearRetryScheduled
               and not after_retry_shotnow.screenshotPendingForce,
            "shotnow displaced the scheduled terminal retry")
        terminal_shotnow_retry_checked = true
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
elseif terminal_repeat_disable then
    local state = harness.QRTransportState()
    assert(terminal_repeat_disable_started,
        "terminal repeated-disable checkpoint did not start")
    assert(terminal_repeat_disable_visibility_checks == 2,
        "repeated disable did not cover both terminal captures")
    assert(#screenshot_times == 4 and screenshot_attempts == 4,
        string.format("repeated disable produced shots=%d attempts=%d, expected 4/4",
            #screenshot_times, screenshot_attempts))
    assert(not state.sessionActive
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown
           and state.terminalClearDispatchCount == 2,
        "terminal repeated-disable transport did not settle cleanly")
elseif disable_idle_force then
    local state = harness.QRTransportState()
    assert(idle_force_terminal_started
           and idle_force_started
           and idle_force_cancel_checked,
        "idle manual-force cancellation checkpoints did not complete")
    assert(#screenshot_times == 4
           and screenshot_attempts == idle_force_attempts_before,
        string.format("cancelled idle force produced shots=%d attempts=%d",
            #screenshot_times, screenshot_attempts))
    assert(interaction_manager_query_calls
               == idle_force_interaction_queries_after_disable,
        "disabled addon continued polling QR interaction state")
    assert(not state.sessionActive
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.screenshotAwaitingResult
           and not state.screenshotPendingForce
           and not state.forceVisible
           and not state.qrFrameShown,
        "cancelled idle manual force did not settle cleanly")
elseif disable_idle_force_overlap then
    local state = harness.QRTransportState()
    assert(idle_force_terminal_started
           and idle_force_started
           and idle_force_overlap_checked,
        "idle force overlap checkpoints did not complete")
    assert(#screenshot_times == 5 and screenshot_attempts == 5,
        string.format("idle force overlap produced shots=%d attempts=%d, expected 5/5",
            #screenshot_times, screenshot_attempts))
    assert(not state.sessionActive
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.screenshotAwaitingResult
           and not state.screenshotPendingForce
           and not state.forceVisible
           and not state.qrFrameShown,
        "idle force overlap retained work after disable")
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
elseif screenshot_overlap_terminal then
    local state = harness.QRTransportState()
    assert(screenshot_overlap_started
           and screenshot_overlap_old_result_checked
           and screenshot_overlap_new_result_checked,
        "screenshot/terminal overlap checkpoints did not complete")
    assert(#screenshot_times == 3 and screenshot_attempts == 3,
        string.format("serialized overlap produced shots=%d attempts=%d, expected 3/3",
            #screenshot_times, screenshot_attempts))
    assert(not state.sessionActive
           and not state.screenshotAwaitingResult
           and not state.screenshotPendingForce
           and not state.screenshotPendingTerminalClear
           and state.terminalClearDispatchCount == 2,
        "serialized terminal capture did not settle after the old result")
elseif screenshot_overlap_restart then
    local state = harness.QRTransportState()
    assert(screenshot_overlap_started
           and screenshot_overlap_old_result_checked
           and screenshot_overlap_new_result_checked,
        "screenshot/restart overlap checkpoints did not complete")
    assert(#screenshot_times == 3 and screenshot_attempts == 3,
        string.format("restart overlap produced shots=%d attempts=%d, expected 3/3",
            #screenshot_times, screenshot_attempts))
    assert(state.sessionActive
           and not state.screenshotAwaitingResult
           and not state.screenshotPendingForce
           and not state.screenshotPendingTerminalClear
           and state.terminalClearDispatchCount == 0
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "fresh session did not retire the queued terminal and deliver normally")
elseif screenshot_overlap_shotnow then
    local state = harness.QRTransportState()
    assert(screenshot_shotnow_started and screenshot_shotnow_result_checked,
        "ordinary screenshot/shotnow checkpoints did not complete")
    assert(#screenshot_times == 2 and screenshot_attempts == 2,
        string.format("shotnow serialization produced shots=%d attempts=%d, expected 2/2",
            #screenshot_times, screenshot_attempts))
    assert(state.sessionActive
           and not state.screenshotAwaitingResult
           and not state.screenshotPendingForce
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "queued shotnow did not settle after the valid ordinary result")
elseif terminal_shotnow_priority then
    local state = harness.QRTransportState()
    assert(terminal_shotnow_started
           and terminal_shotnow_await_checked
           and terminal_shotnow_retry_checked,
        "terminal shotnow priority checkpoints did not complete")
    assert(#screenshot_times == 4 and screenshot_attempts == 4,
        string.format("terminal shotnow produced shots=%d attempts=%d, expected 4/4",
            #screenshot_times, screenshot_attempts))
    assert(not state.sessionActive
           and not state.screenshotAwaitingResult
           and not state.screenshotPendingForce
           and not state.screenshotPendingTerminalClear
           and not state.terminalClearRetryScheduled
           and state.terminalClearDispatchCount == 2
           and state.deliverySnapshotHash == nil
           and state.deliverySnapshotSendCount == 0,
        "manual force displaced or duplicated terminal clear delivery")
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
elseif listing_recreate then
    local state = harness.QRTransportState()
    assert(listing_recreate_started and retired_listing_overflow,
        "listing recreate boundary was not exercised")
    assert(#screenshot_times == 2 and screenshot_attempts == 2,
        string.format(
            "recreated listing produced shots=%d attempts=%d instead of 2/2",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(state.sessionActive
           and not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and state.overflowState == nil
           and state.lastEmittedApplicantCount == 0
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "recreated empty listing did not settle as the current delivery")
elseif gameplay_combat or gameplay_challenge_reload then
    local state = harness.QRTransportState()
    assert(gameplay_released,
        "gameplay suppression release boundary was not exercised")
    assert(#screenshot_times == 2 and screenshot_attempts == 2,
        string.format(
            "gameplay resume produced shots=%d attempts=%d instead of 2/2",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(not state.suppressedByGameplay
           and not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.screenshotPendingForce
           and not state.forceVisible
           and not state.qrFrameShown,
        "gameplay-suppressed transport did not settle after release")
elseif gameplay_combat_during_paint or gameplay_combat_during_settle then
    local state = harness.QRTransportState()
    assert(midflight_combat_started and midflight_combat_released,
        "mid-flight combat suppression boundaries were not exercised")
    assert(#screenshot_times == 2 and screenshot_attempts == 2,
        string.format(
            "mid-flight combat resume produced shots=%d attempts=%d instead of 2/2",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(not state.suppressedByGameplay
           and not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown,
        "mid-flight combat transport did not rebuild and settle")
elseif gameplay_raid_encounter then
    local state = harness.QRTransportState()
    assert(raid_encounter_started and raid_encounter_released,
        "raid encounter suppression boundaries were not exercised")
    assert(#screenshot_times == 4 and screenshot_attempts == 4,
        string.format(
            "raid encounter resume produced shots=%d attempts=%d instead of 4/4",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(not state.suppressedByGameplay
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown,
        "raid encounter transport did not resume and settle")
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
    if fixture_mode == "applicants" then
        assert(qr_encode_calls == 1,
            string.format(
                "unchanged redundant resend encoded QR %d times instead of once",
                qr_encode_calls
            ))
    end
end
if #screenshot_times >= 2
   and not screenshot_overlap
   and not screenshot_overlap_shotnow
   and not terminal_shotnow_priority then
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
