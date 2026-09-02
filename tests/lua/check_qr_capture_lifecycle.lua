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
       or fixture_mode == "screenshot-late-timeout-success"
       or fixture_mode == "screenshot-late-timeout-failure"
       or fixture_mode == "capture-fresh-timeout-clock"
       or fixture_mode == "screenshot-overlap-terminal"
       or fixture_mode == "screenshot-overlap-restart"
       or fixture_mode == "screenshot-overlap-shotnow"
       or fixture_mode == "terminal-shotnow-priority"
       or fixture_mode == "terminal-clear-failure"
       or fixture_mode == "terminal-clear-always-fail"
       or fixture_mode == "terminal-pre-capture-build-failure"
       or fixture_mode == "terminal-pre-capture-watchdog"
       or fixture_mode == "terminal-repeat-disable"
       or fixture_mode == "disable-idle-force"
       or fixture_mode == "disable-idle-force-overlap"
       or fixture_mode == "interaction-during-paint"
       or fixture_mode == "interaction-during-settle"
       or fixture_mode == "info-panel-during-settle"
       or fixture_mode == "interaction-force"
       or fixture_mode == "interaction-terminal"
       or fixture_mode == "interaction-persistent"
       or fixture_mode == "interaction-close-awaiting"
       or fixture_mode == "interaction-quick-close"
       or fixture_mode == "interaction-world-reset"
       or fixture_mode == "interaction-manager-recovery"
       or fixture_mode == "partial-debug"
       or fixture_mode == "overflow"
       or fixture_mode == "overflow-interaction-close"
       or fixture_mode == "overflow-interaction-close-awaiting"
       or fixture_mode == "overflow-terminal"
       or fixture_mode == "listing-recreate"
       or fixture_mode == "lfg-read-transient"
       or fixture_mode == "lfg-read-partial-identity"
       or fixture_mode == "lfg-read-recreate-race"
       or fixture_mode == "activity-info-transient"
       or fixture_mode == "diagnostic-api-errors"
       or fixture_mode == "external-screenshot-overlap"
       or fixture_mode == "external-screenshot-timeout"
       or fixture_mode == "external-screenshot-during-waiter"
       or fixture_mode == "gameplay-combat"
       or fixture_mode == "gameplay-combat-during-paint"
       or fixture_mode == "gameplay-combat-during-settle"
       or fixture_mode == "gameplay-start-edge-lag-combat"
       or fixture_mode == "gameplay-start-edge-lag-challenge"
       or fixture_mode == "gameplay-start-edge-lag-encounter"
       or fixture_mode == "gameplay-challenge-reload"
       or fixture_mode == "gameplay-challenge-complete-lag"
       or fixture_mode == "gameplay-challenge-reset-lag"
       or fixture_mode == "gameplay-raid-encounter"
       or fixture_mode == "gameplay-loading-initial"
       or fixture_mode == "gameplay-loading-during-paint"
       or fixture_mode == "gameplay-loading-during-settle"
       or fixture_mode == "gameplay-loading-awaiting"
       or fixture_mode == "gameplay-loading-awaiting-terminal"
       or fixture_mode == "forced-lockdown-suppression"
       or fixture_mode == "forced-lockdown-transition"
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
local screenshot_late_timeout_success =
    fixture_mode == "screenshot-late-timeout-success"
local screenshot_late_timeout_failure =
    fixture_mode == "screenshot-late-timeout-failure"
local screenshot_late_timeout = screenshot_late_timeout_success
    or screenshot_late_timeout_failure
local capture_fresh_timeout_clock =
    fixture_mode == "capture-fresh-timeout-clock"
local screenshot_overlap_terminal = fixture_mode == "screenshot-overlap-terminal"
local screenshot_overlap_restart = fixture_mode == "screenshot-overlap-restart"
local screenshot_overlap = screenshot_overlap_terminal or screenshot_overlap_restart
local external_screenshot_overlap = fixture_mode == "external-screenshot-overlap"
local external_screenshot_timeout = fixture_mode == "external-screenshot-timeout"
local external_screenshot_mode = external_screenshot_overlap
    or external_screenshot_timeout
local screenshot_overlap_shotnow = fixture_mode == "screenshot-overlap-shotnow"
local terminal_shotnow_priority = fixture_mode == "terminal-shotnow-priority"
local terminal_clear_failure = fixture_mode == "terminal-clear-failure"
local terminal_clear_always_fail = fixture_mode == "terminal-clear-always-fail"
local terminal_clear_mode = terminal_clear_failure or terminal_clear_always_fail
local terminal_pre_capture_kind = fixture_mode:match(
    "^terminal%-pre%-capture%-(%a+%-?%a*)$"
)
local terminal_pre_capture_mode = terminal_pre_capture_kind ~= nil
local terminal_repeat_disable = fixture_mode == "terminal-repeat-disable"
local disable_idle_force = fixture_mode == "disable-idle-force"
local disable_idle_force_overlap = fixture_mode == "disable-idle-force-overlap"
local interaction_during_paint = fixture_mode == "interaction-during-paint"
local interaction_during_settle = fixture_mode == "interaction-during-settle"
local info_panel_during_settle = fixture_mode == "info-panel-during-settle"
local interaction_force = fixture_mode == "interaction-force"
local interaction_terminal = fixture_mode == "interaction-terminal"
local interaction_persistent = fixture_mode == "interaction-persistent"
local interaction_close_awaiting = fixture_mode == "interaction-close-awaiting"
local interaction_quick_close = fixture_mode == "interaction-quick-close"
local interaction_world_reset = fixture_mode == "interaction-world-reset"
local interaction_manager_recovery = fixture_mode == "interaction-manager-recovery"
local partial_debug = fixture_mode == "partial-debug"
local overflow_mode = fixture_mode == "overflow"
    or fixture_mode == "overflow-interaction-close"
    or fixture_mode == "overflow-interaction-close-awaiting"
    or fixture_mode == "overflow-terminal"
    or fixture_mode == "lfg-read-recreate-race"
    or restart_phase == "overflow-settle"
local overflow_terminal = fixture_mode == "overflow-terminal"
local overflow_interaction_close = fixture_mode == "overflow-interaction-close"
local overflow_interaction_close_awaiting =
    fixture_mode == "overflow-interaction-close-awaiting"
local restart_race = fixture_mode == "restart-race"
local listing_recreate = fixture_mode == "listing-recreate"
local lfg_read_transient = fixture_mode == "lfg-read-transient"
local lfg_read_partial_identity = fixture_mode == "lfg-read-partial-identity"
local lfg_read_recreate_race = fixture_mode == "lfg-read-recreate-race"
local activity_info_transient = fixture_mode == "activity-info-transient"
local diagnostic_api_errors = fixture_mode == "diagnostic-api-errors"
local gameplay_combat = fixture_mode == "gameplay-combat"
local gameplay_combat_during_paint = fixture_mode == "gameplay-combat-during-paint"
local gameplay_combat_during_settle = fixture_mode == "gameplay-combat-during-settle"
local gameplay_start_edge_lag_axis = fixture_mode:match(
    "^gameplay%-start%-edge%-lag%-(%a+)$"
)
local gameplay_start_edge_lag = gameplay_start_edge_lag_axis ~= nil
local gameplay_challenge_reload = fixture_mode == "gameplay-challenge-reload"
    or fixture_mode == "gameplay-challenge-complete-lag"
    or fixture_mode == "gameplay-challenge-reset-lag"
local gameplay_raid_encounter = fixture_mode == "gameplay-raid-encounter"
local gameplay_loading_initial = fixture_mode == "gameplay-loading-initial"
local gameplay_loading_during_paint =
    fixture_mode == "gameplay-loading-during-paint"
local gameplay_loading_during_settle =
    fixture_mode == "gameplay-loading-during-settle"
local gameplay_loading_awaiting = fixture_mode == "gameplay-loading-awaiting"
local gameplay_loading_awaiting_terminal =
    fixture_mode == "gameplay-loading-awaiting-terminal"
local forced_lockdown_suppression = fixture_mode == "forced-lockdown-suppression"
local forced_lockdown_transition = fixture_mode == "forced-lockdown-transition"
local gameplay_loading_midflight = gameplay_loading_during_paint
    or gameplay_loading_during_settle
    or gameplay_loading_awaiting
local wide_applicants = overflow_mode or listing_recreate

-- Default mode reproduces the live report: two people and five applicants.
-- Roster-only mode keeps a full party and removes every applicant.
if not roster_only then
    env.unit_data.party2 = nil
    env.unit_data.party3 = nil
    env.unit_data.party4 = nil
end
gameplay_group_member_count_calls = 0
GetNumGroupMembers = function()
    gameplay_group_member_count_calls = gameplay_group_member_count_calls + 1
    if roster_only then return 5 end
    if lfg_read_transient or lfg_read_partial_identity then return 0 end
    return 2
end
IsInRaid = function() return false end
local combat_active = gameplay_combat
local combat_api_unavailable = false
local challenge_active = gameplay_challenge_reload
local encounter_active = false
local gameplay_lfg_read_calls = 0
local chat_lockdown = false
C_ChatInfo = C_ChatInfo or {}
C_ChatInfo.InChatMessagingLockdown = function() return chat_lockdown end
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
local screenshot_late_timeout_old_result_drained = false
local screenshot_late_timeout_checked = false
local lfg_read_transient_checked = false
local lfg_read_recreate_race_checked = false
local capture_clock_result_pending = false
local capture_clock_result_release_at = nil
local capture_clock_result_checked = false
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
local regression_state = {
    activityInfoPhase = 0,
    originalActivityInfo = nil,
    lfgPartialIdentityChecked = false,
    startEdge = {
        started = false,
        released = false,
        releaseAt = nil,
        encodeCalls = nil,
        lfgReadCalls = nil,
    },
    terminalPreCapture = {
        started = false,
        injectionReleased = false,
        watchdogAged = false,
    },
}

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
    if capture_fresh_timeout_clock and screenshot_attempts == 1 then
        assert(harness.AgeCurrentQRBuildForFixture(7.9),
            "capture-clock fixture could not age build clock")
        local clocks = harness.QRTransportState()
        assert(now - clocks.transportJobStartedAt >= 7.9
               and now - clocks.transportCaptureRequestedAt < 0.1,
            "physical capture did not receive a fresh timeout clock")
        capture_clock_result_pending = true
        capture_clock_result_release_at = now + 1.0
        return
    end
    if screenshot_event_timeout
       or (screenshot_late_timeout
           and not screenshot_late_timeout_old_result_drained)
       or (fixture_mode == "external-screenshot-during-waiter"
           and screenshot_attempts == 1) then
        return
    end
    if (screenshot_overlap or screenshot_overlap_shotnow)
       and screenshot_attempts == 1 then
        delayed_screenshot_result = true
        return
    end
    if gameplay_loading_awaiting and screenshot_attempts == 1 then
        delayed_screenshot_result = true
        return
    end
    if gameplay_loading_awaiting_terminal and screenshot_attempts == 3 then
        delayed_screenshot_result = true
        return
    end
    if interaction_close_awaiting and screenshot_attempts == 2 then
        delayed_screenshot_result = true
        return
    end
    if overflow_interaction_close_awaiting and screenshot_attempts == 1 then
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
    if terminal_pre_capture_kind == "build-failure"
       and regression_state.terminalPreCapture.started
       and not regression_state.terminalPreCapture.injectionReleased then
        return false, "injected terminal pre-capture QR build failure"
    end
    local ok, result = original_qrcode(...)
    if ok then qr_encode_successes = qr_encode_successes + 1 end
    return ok, result
end
local original_qrcode_async = assert(qr_namespace.QR.qrcodeAsync)
qr_namespace.QR.qrcodeAsync = function(
    data,
    ec_level,
    mode,
    schedule,
    is_cancelled,
    on_complete
)
    qr_encode_calls = qr_encode_calls + 1
    if terminal_pre_capture_kind == "build-failure"
       and regression_state.terminalPreCapture.started
       and not regression_state.terminalPreCapture.injectionReleased then
        schedule(function()
            on_complete(false, "injected terminal pre-capture QR build failure")
        end)
        return
    end
    return original_qrcode_async(
        data,
        ec_level,
        mode,
        schedule,
        is_cancelled,
        function(ok, result)
            if ok then qr_encode_successes = qr_encode_successes + 1 end
            return on_complete(ok, result)
        end
    )
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
assert(event_frame.events.LOADING_SCREEN_ENABLED
       and event_frame.events.LOADING_SCREEN_DISABLED
       and event_frame.events.PLAYER_LEAVING_WORLD,
    "loading-screen lifecycle events were not registered")
local initial_loading_state = harness.QRTransportState()
assert(initial_loading_state.suppressedByGameplay
       and initial_loading_state.gameplayLoadingActive
       and initial_loading_state.gameplaySuppressionReason == "loading-screen",
    "transport did not start conservatively suppressed by loading")

do
    local active, confirmed, reconciled =
        harness.ResolveGameplayActivityState(false, function() return true end, false)
    assert(active and confirmed and not reconciled,
        "current-state API did not recover a missed gameplay start")

    active, confirmed, reconciled = harness.ResolveGameplayActivityState(
        false,
        function() error("temporary protected gameplay state") end,
        confirmed
    )
    assert(active and confirmed and not reconciled,
        "transient unknown API state released an API-confirmed gameplay latch")

    active, confirmed, reconciled = harness.ResolveGameplayActivityState(
        false,
        function() return false end,
        confirmed
    )
    assert(not active and not confirmed and not reconciled,
        "clean inactive API state did not release an API-confirmed gameplay latch")
end

if diagnostic_api_errors then
    local originalPrint = print
    local originalApplicants = C_LFGList.GetApplicants
    local originalKeystone = C_LFGList.GetKeystoneForActivity
    local lines = {}
    print = function(...)
        local parts = {}
        for index = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(index, ...))
        end
        lines[#lines + 1] = table.concat(parts, "\t")
    end
    C_LFGList.GetApplicants = function()
        error("temporary protected applicants surface")
    end
    C_LFGList.GetKeystoneForActivity = function()
        error("temporary protected keystone surface")
    end

    local taintOK = pcall(SlashCmdList.APSCOUT, "taintcheck")
    local statusOK = pcall(SlashCmdList.APSCOUT, "status")

    print = originalPrint
    C_LFGList.GetApplicants = originalApplicants
    C_LFGList.GetKeystoneForActivity = originalKeystone
    assert(taintOK, "taintcheck crashed on an unavailable applicant API")
    assert(statusOK, "status crashed on an unavailable keystone API")
    local output = table.concat(lines, "\n")
    assert(output:find("applicants: unavailable", 1, true),
        "taintcheck did not report the unavailable applicant API")
    assert(output:find("activity.keystoneLevel: unavailable", 1, true),
        "status did not report the unavailable keystone API")
end

if not gameplay_loading_initial then
    event_frame.scripts.OnEvent(event_frame, "LOADING_SCREEN_DISABLED")
end

if external_screenshot_mode then
    event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_STARTED")
    local externalState = harness.QRTransportState()
    assert(externalState.screenshotExternalInProgress,
        "external screenshot start was not serialized")
    assert(externalState.screenshotExternalPendingCount == 1,
        "external screenshot ownership count was not armed")
    if external_screenshot_timeout then
        assert(harness.AgeExternalScreenshotForFixture(9.0),
            "external timeout fixture could not age its ownership clock")
    end
end

if gameplay_combat or gameplay_challenge_reload then
    local state = harness.QRTransportState()
    assert(state.suppressedByGameplay and not state.qrFrameShown,
        "reload did not recover active gameplay suppression")
    if gameplay_combat then
        SlashCmdList.APSCOUT("shotnow")
        state = harness.QRTransportState()
        assert(state.screenshotPendingForce and #screenshot_times == 0,
            "manual force capture was not deferred during combat")
    else
        assert(state.challengeDormant and not state.scanTickerActive,
            "active challenge reload did not stop the scan ticker")
        assert(not state.challengeDormantOptionalEventsRegistered
               and not event_frame.events.GROUP_ROSTER_UPDATE
               and not event_frame.events.CHAT_MSG_ADDON
               and not event_frame.events.PLAYER_INTERACTION_MANAGER_FRAME_SHOW,
            "active challenge reload kept optional background events registered")
        assert(event_frame.events.CHALLENGE_MODE_COMPLETED
               and event_frame.events.PLAYER_REGEN_ENABLED
               and event_frame.events.SCREENSHOT_SUCCEEDED,
            "active challenge reload removed a required recovery event")
        regression_state.groupMemberCountCallsBefore =
            gameplay_group_member_count_calls
        event_frame.scripts.OnEvent(event_frame, "GROUP_ROSTER_UPDATE")
        state = harness.QRTransportState()
        assert(gameplay_group_member_count_calls
                   == regression_state.groupMemberCountCallsBefore
               and state.challengeDormantRosterDirty,
            "dormant roster event performed group work instead of deferring once")
        event_frame.scripts.OnEvent(event_frame, "PLAYER_REGEN_ENABLED")
        state = harness.QRTransportState()
        assert(state.challengeDormant and not state.scanTickerActive,
            "combat-end event restarted work during an active challenge")
        regression_state.dormantTimerCount = #timers
        regression_state.dormantTickerStarts = state.scanTickerStartCount
        regression_state.dormantLFGReads = gameplay_lfg_read_calls
        regression_state.dormantEncodes = qr_encode_calls
        for _ = 1, 100 do
            for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "ENCOUNTER_START",
                "ENCOUNTER_END", "PLAYER_REGEN_ENABLED" }) do
                event_frame.scripts.OnEvent(event_frame, event)
            end
        end
        state = harness.QRTransportState()
        assert(state.challengeDormant and not state.scanTickerActive
               and state.scanTickerStartCount == regression_state.dormantTickerStarts
               and #timers == regression_state.dormantTimerCount
               and gameplay_lfg_read_calls == regression_state.dormantLFGReads
               and qr_encode_calls == regression_state.dormantEncodes
               and gameplay_group_member_count_calls == regression_state.groupMemberCountCallsBefore,
            "combat/encounter event storm woke optional work inside an active key")
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

if interaction_persistent then
    send_interaction_event("MERCHANT_SHOW")
    interaction_opened_at = now
end
if interaction_close_awaiting then
    send_interaction_event("MERCHANT_SHOW")
    interaction_opened_at = now
end
if overflow_interaction_close or overflow_interaction_close_awaiting then
    send_interaction_event("MERCHANT_SHOW")
    interaction_opened = true
    interaction_opened_at = now
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
        local safety = 1000
        while qr_encode_successes == success_before do
            run_earliest_timer()
            safety = safety - 1
            assert(safety > 0, "terminal QR encode did not reach row-scan staging")
        end
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
local external_screenshot_released = false
regression_state.RunLFGPartialIdentityProbe = function()
    local originalGet = C_LFGList.GetActiveEntryInfo
    local originalSecret = issecretvalue
    local before = harness.QRTransportState()
    local attemptsBefore = screenshot_attempts
    local function assert_identity_preserved(label)
        local state = harness.QRTransportState()
        assert(state.sessionActive
               and state.activeListingGeneration == before.activeListingGeneration
               and state.activeListingActivityID == before.activeListingActivityID
               and state.lastSnapshotHash == before.lastSnapshotHash
               and state.deliverySnapshotHash == before.deliverySnapshotHash
               and state.deliverySnapshotSendCount == 2,
            label .. " mutated the active listing epoch")
        assert(screenshot_attempts == attemptsBefore,
            label .. " emitted a false replacement snapshot")
    end

    local secretActivityID = {}
    issecretvalue = function(value) return value == secretActivityID end
    C_LFGList.GetActiveEntryInfo = function()
        return {
            activityIDs = { secretActivityID },
            questID = 0,
            name = "Protected listing identity",
            comment = "activity ID is temporarily secret",
        }
    end
    local secretEntry, secretStateKnown = harness.CheckSessionTransition(true)
    assert(secretEntry and not secretStateKnown,
        "secret activity identity was declared authoritative")
    harness.MaybeTriggerScreenshot(false, secretEntry, nil, true, secretStateKnown)
    assert_identity_preserved("secret active-entry identity")

    issecretvalue = originalSecret
    C_LFGList.GetActiveEntryInfo = function() return {} end
    local partialEntry, partialStateKnown = harness.CheckSessionTransition(true)
    assert(partialEntry and not partialStateKnown,
        "empty active-entry identity was declared authoritative")
    harness.MaybeTriggerScreenshot(false, partialEntry, nil, true, partialStateKnown)
    assert_identity_preserved("empty active-entry identity")

    C_LFGList.GetActiveEntryInfo = originalGet
    local cleanEntry, cleanStateKnown = harness.CheckSessionTransition(true)
    assert(cleanEntry and cleanStateKnown,
        "clean active-entry identity did not recover")
    assert_identity_preserved("clean identity recovery")

    C_LFGList.HasActiveEntryInfo = function() return false end
    C_LFGList.GetActiveEntryInfo = function() return nil end
    harness.CheckSessionTransition(true)
    assert(not harness.QRTransportState().sessionActive,
        "clean inactive listing did not end the partial-identity fixture")
    regression_state.lfgPartialIdentityChecked = true
end
local midflight_combat_started = false
local midflight_combat_released = false
local midflight_combat_release_at = nil
local midflight_combat_encode_calls = nil
local loading_transition_started = false
local loading_transition_released = false
local loading_transition_release_at = gameplay_release_at
local loading_transition_encode_calls = nil
local loading_transition_lfg_read_calls = nil
local terminal_loading_started = false
local terminal_loading_old_result_drained = false
local terminal_loading_old_result_at = nil
local terminal_loading_released = false
local terminal_loading_release_at = nil
local overflow_interaction_shots_before = nil
local overflow_interaction_old_generation = nil
local overflow_interaction_new_generation = nil
local overflow_interaction_chunk_count = nil
local overflow_interaction_awaiting_old_result_drained = false
local forced_lockdown_started = false
local forced_lockdown_released = false
local forced_lockdown_release_at = nil
local forced_lockdown_lfg_reads_before = nil
for _ = 1, (overflow_interaction_close
             or overflow_interaction_close_awaiting) and 5000
        or (overflow_mode or listing_recreate) and 2500
        or (screenshot_event_timeout or screenshot_late_timeout) and 650 or 360 do
    now = now + frame_step
    local holdTerminalWatchdogTimers = terminal_pre_capture_kind == "watchdog"
        and regression_state.terminalPreCapture.started
        and not regression_state.terminalPreCapture.injectionReleased
    if not holdTerminalWatchdogTimers then
        drain_due_timers()
    end
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


    if external_screenshot_mode and not external_screenshot_released then
        local state = harness.QRTransportState()
        if state.screenshotLastResult == "deferred: external screenshot" then
            assert(screenshot_attempts == 0
                   and #screenshot_times == 0
                   and qr_encode_calls == 0
                   and state.screenshotExternalInProgress
                   and state.screenshotExternalPendingCount == 1,
                "ApplicantScout worked before the external screenshot completed")
            if external_screenshot_timeout then
                assert(state.screenshotExternalOrphaned,
                    "timed-out external screenshot released physical ownership")
            end
            event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
            external_screenshot_released = true
            state = harness.QRTransportState()
            assert(not state.screenshotExternalInProgress
                   and not state.screenshotAwaitingResult,
                "external screenshot terminal event was attributed to ApplicantScout")
        end
    end

    if fixture_mode == "external-screenshot-during-waiter"
       and not regression_state.externalWaiterOverlapChecked then
        local waiting = harness.QRTransportState()
        if screenshot_attempts == 1
           and waiting.screenshotAwaitingResult
           and waiting.screenshotAwaitingStarted then
            event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_STARTED")
            local overlapped = harness.QRTransportState()
            assert(overlapped.screenshotOverlapAmbiguous
                   and overlapped.screenshotExternalInProgress
                   and overlapped.screenshotExternalPendingCount == 2,
                "second screenshot start did not make APS result ownership ambiguous")
            event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_FAILED")
            local halfDrained = harness.QRTransportState()
            assert(halfDrained.screenshotAwaitingResult
                   and halfDrained.screenshotOverlapAmbiguous
                   and halfDrained.screenshotExternalPendingCount == 1
                   and halfDrained.deliverySnapshotHash == nil
                   and halfDrained.screenshotFailureAttemptCount == 0,
                "first ambiguous terminal event completed the APS waiter")
            event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
            local drained = harness.QRTransportState()
            assert(not drained.screenshotAwaitingResult
                   and not drained.screenshotExternalInProgress
                   and not drained.screenshotOverlapAmbiguous
                   and drained.deliverySnapshotHash == nil
                   and drained.screenshotFailureAttemptCount == 1,
                "ambiguous result drain did not fail closed and queue a retry")
            regression_state.externalWaiterOverlapChecked = true
        end
    end

    if screenshot_late_timeout
       and not screenshot_late_timeout_old_result_drained then
        local waiting = harness.QRTransportState()
        if screenshot_attempts == 1
           and waiting.screenshotAwaitingResult
           and waiting.screenshotAwaitingSuperseded
           and waiting.screenshotLastResult
               == "timed out; waiting for late result" then
            assert(not waiting.paintInProgress
                   and not waiting.captureInProgress
                   and waiting.deliverySnapshotHash == nil
                   and waiting.screenshotFailureAttemptCount == 0,
                "timed-out screenshot did not fail closed before late result")
            if screenshot_late_timeout_success then
                screenshot_times[#screenshot_times + 1] = now
                event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
            else
                event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_FAILED")
            end
            screenshot_late_timeout_old_result_drained = true
            local drained = harness.QRTransportState()
            assert(screenshot_attempts == 1
                   and drained.deliverySnapshotHash == nil
                   and drained.screenshotFailureAttemptCount == 0,
                "late result was attributed to replacement delivery state")
        end
    end

    if capture_fresh_timeout_clock
       and capture_clock_result_pending
       and not capture_clock_result_checked
       and now >= capture_clock_result_release_at then
        local waiting = harness.QRTransportState()
        assert(screenshot_attempts == 1
               and waiting.screenshotAwaitingResult
               and not waiting.screenshotAwaitingSuperseded
               and waiting.screenshotLastResult == "started"
               and waiting.screenshotFailureAttemptCount == 0,
            "aged build clock prematurely timed out a fresh physical capture")
        screenshot_times[#screenshot_times + 1] = now
        event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
        capture_clock_result_checked = true
    end

    if screenshot_late_timeout_old_result_drained
       and not screenshot_late_timeout_checked
       and screenshot_attempts == 3 then
        local settled = harness.QRTransportState()
        assert(settled.deliverySnapshotHash == settled.lastSnapshotHash
               and settled.deliverySnapshotSendCount == 2
               and settled.screenshotFailureAttemptCount == 0,
            "replacement screenshots did not settle independently of late result")
        screenshot_late_timeout_checked = true
    end

    if lfg_read_transient
       and not lfg_read_transient_checked
       and #screenshot_times == 2
       and not harness.QRTransportState().paintInProgress
       and not harness.QRTransportState().captureInProgress then
        local originalGet = C_LFGList.GetActiveEntryInfo
        local originalSecret = issecretvalue
        local before = harness.QRTransportState()
        local attemptsBefore = screenshot_attempts
        local function assert_preserved(label)
            local state = harness.QRTransportState()
            assert(state.sessionActive
                   and state.lastSnapshotHash == before.lastSnapshotHash
                   and state.deliverySnapshotHash == before.deliverySnapshotHash
                   and state.deliverySnapshotSendCount == 2
                   and state.terminalClearDispatchCount == 0,
                label .. " was mistaken for an ended listing")
            assert(screenshot_attempts == attemptsBefore,
                label .. " emitted a false empty snapshot")
        end

        C_LFGList.HasActiveEntryInfo = function()
            error("injected active-entry probe failure")
        end
        assert(harness.CheckSessionTransition(true) == nil)
        harness.MaybeTriggerScreenshot(false, nil, nil, true)
        assert_preserved("throwing HasActiveEntryInfo")

        local secretHasEntry = {}
        issecretvalue = function(value) return value == secretHasEntry end
        C_LFGList.HasActiveEntryInfo = function() return secretHasEntry end
        assert(harness.CheckSessionTransition(true) == nil)
        harness.MaybeTriggerScreenshot(false, nil, nil, true)
        assert_preserved("secret HasActiveEntryInfo")
        issecretvalue = originalSecret

        C_LFGList.HasActiveEntryInfo = function() return true end
        C_LFGList.GetActiveEntryInfo = function()
            error("injected active-entry fetch failure")
        end
        assert(harness.CheckSessionTransition(true) == nil)
        harness.MaybeTriggerScreenshot(false, nil, nil, true)
        assert_preserved("throwing GetActiveEntryInfo")

        C_LFGList.GetActiveEntryInfo = function() return nil end
        assert(harness.CheckSessionTransition(true) == nil)
        harness.MaybeTriggerScreenshot(false, nil, nil, true)
        assert_preserved("nil GetActiveEntryInfo")

        C_LFGList.HasActiveEntryInfo = function() return false end
        C_LFGList.GetActiveEntryInfo = originalGet
        harness.CheckSessionTransition(true)
        assert(not harness.QRTransportState().sessionActive,
            "clean inactive listing did not end the transport session")
        C_LFGList.HasActiveEntryInfo = function() return false end
        lfg_read_transient_checked = true
    end

    if lfg_read_partial_identity
       and not regression_state.lfgPartialIdentityChecked
       and #screenshot_times == 2
       and not harness.QRTransportState().paintInProgress
       and not harness.QRTransportState().captureInProgress then
        regression_state.RunLFGPartialIdentityProbe()
    end

    if activity_info_transient then
        local state = harness.QRTransportState()
        if regression_state.activityInfoPhase == 0
           and #screenshot_times == 2
           and not state.paintInProgress
           and not state.captureInProgress then
            regression_state.originalActivityInfo =
                C_LFGList.GetActivityInfoTable
            C_LFGList.GetActivityInfoTable = function()
                error("injected transient activity-info failure")
            end
            applicant_ids = { 42, 43, 44, 45, 46, 47 }
            local ok, err = pcall(
                harness.MaybeTriggerScreenshot,
                false,
                nil,
                nil,
                true
            )
            assert(ok, "activity-info failure escaped QR payload build: " .. tostring(err))
            regression_state.activityInfoPhase = 1
        elseif regression_state.activityInfoPhase == 1
           and #screenshot_times == 4
           and state.deliverySnapshotSendCount == 2
           and state.lastEmittedApplicantCount == 6
           and not state.paintInProgress
           and not state.captureInProgress then
            C_LFGList.GetActivityInfoTable =
                regression_state.originalActivityInfo
            applicant_ids = { 42, 43, 44, 45, 46, 47, 48 }
            harness.MaybeTriggerScreenshot(false, nil, nil, true)
            regression_state.activityInfoPhase = 2
        elseif regression_state.activityInfoPhase == 2
           and #screenshot_times == 6
           and state.deliverySnapshotSendCount == 2
           and state.lastEmittedApplicantCount == 7
           and not state.paintInProgress
           and not state.captureInProgress then
            regression_state.activityInfoPhase = 3
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
                   and after_old.terminalClearDispatchCount == 0,
                "queued terminal job consumed physical budget before Screenshot()")
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
       and (interaction_during_paint
            or interaction_during_settle
            or info_panel_during_settle)
       and now - interaction_opened_at >= 0.75 then
        if info_panel_during_settle then
            WorldMapFrame.shown = false
        else
            send_interaction_event("MERCHANT_CLOSED")
        end
        interaction_closed = true
    end

    if interaction_persistent
       and not interaction_deferred_checked
       and now - interaction_opened_at >= 0.5 then
        applicant_ids = { 42, 43, 44 }
        interaction_deferred_checked = true
    end
    if interaction_persistent
       and interaction_deferred_checked
       and not interaction_closed
       and #screenshot_times == 2 then
        local state = harness.QRTransportState()
        if not state.paintInProgress and not state.captureInProgress then
            assert(screenshot_times[1] - interaction_opened_at >= 1.0,
                "persistent interaction captured before its bounded grace expired")
            assert(state.lastEmittedApplicantCount == 3,
                "persistent interaction missed applicant churn during its grace")
            send_interaction_event("MERCHANT_CLOSED")
            interaction_closed = true
        end
    end
    if interaction_close_awaiting
       and not interaction_closed
       and screenshot_attempts == 2
       and harness.QRTransportState().screenshotAwaitingResult then
        assert(delayed_screenshot_result,
            "interaction close fixture lost its delayed screenshot result")
        send_interaction_event("MERCHANT_CLOSED")
        local closing = harness.QRTransportState()
        assert(closing.screenshotAwaitingSuperseded
               and closing.deliverySnapshotSendCount == 1,
            "interaction close did not supersede the panel-open result")
        screenshot_times[#screenshot_times + 1] = now
        event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
        local after_old = harness.QRTransportState()
        assert(after_old.deliverySnapshotSendCount == 1
               and after_old.pendingShotDirty,
            "late panel-open success consumed the safe resend budget")
        interaction_closed = true
    end
    if interaction_quick_close
       and not interaction_opened
       and #screenshot_times == 2
       and not harness.QRTransportState().paintInProgress
       and not harness.QRTransportState().captureInProgress
       and not harness.QRTransportState().pendingShotDirty then
        interaction_opened = true
        interaction_shots_before = #screenshot_times
        send_interaction_event("MERCHANT_SHOW")
        assert(harness.QRTransportState().suppressedByInteraction,
            "quick-close fixture did not open interaction state")
        send_interaction_event("MERCHANT_CLOSED")
        interaction_closed = true
        local closed = harness.QRTransportState()
        assert(not closed.suppressedByInteraction
               and closed.deliverySnapshotSendCount == 2
               and not closed.pendingShotDirty,
            string.format(
                "quick panel close rearmed a snapshot without a panel-open capture: suppressed=%s delivery=%s pending=%s",
                tostring(closed.suppressedByInteraction),
                tostring(closed.deliverySnapshotSendCount),
                tostring(closed.pendingShotDirty)
            ))
    end
    if overflow_interaction_close_awaiting and not interaction_closed then
        local state = harness.QRTransportState()
        if screenshot_attempts == 1
           and state.screenshotAwaitingResult
           and state.overflowState then
            overflow_interaction_shots_before = #screenshot_times
            overflow_interaction_old_generation = state.overflowState.generation
            overflow_interaction_chunk_count = state.overflowState.chunkCount
            send_interaction_event("MERCHANT_CLOSED")
            interaction_closed = true
            local closed = harness.QRTransportState()
            assert(closed.overflowState == nil
                   and closed.screenshotAwaitingResult
                   and closed.screenshotAwaitingSuperseded
                   and closed.pendingShotDirty,
                "awaiting interaction close did not retire and supersede overflow")
        end
    elseif overflow_interaction_close_awaiting
       and interaction_closed
       and not overflow_interaction_awaiting_old_result_drained then
        local state = harness.QRTransportState()
        if state.screenshotLastResult == "timed out; waiting for late result" then
            assert(screenshot_attempts == 1
                   and state.screenshotAwaitingResult
                   and state.screenshotAwaitingSuperseded
                   and state.overflowState == nil,
                "timed-out panel capture armed replacement overflow too early")
            screenshot_times[#screenshot_times + 1] = now
            event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
            overflow_interaction_awaiting_old_result_drained = true
            local drained = harness.QRTransportState()
            assert(drained.deliverySnapshotHash == nil
                   and drained.deliverySnapshotSendCount == 0,
                "late panel-open result committed replacement overflow")
        end
    elseif overflow_interaction_close_awaiting
       and overflow_interaction_awaiting_old_result_drained
       and not overflow_interaction_new_generation then
        local state = harness.QRTransportState()
        if state.overflowState then
            overflow_interaction_new_generation = state.overflowState.generation
            assert(overflow_interaction_new_generation
                       ~= overflow_interaction_old_generation,
                "late panel result reused the tainted overflow generation")
            assert(state.overflowState.chunkIndex == 0
                   and state.overflowState.pass == 1,
                "late panel replacement did not restart at fragment zero/pass one")
        end
    end

    if overflow_interaction_close and not interaction_closed then
        local state = harness.QRTransportState()
        if state.overflowState
           and state.overflowState.pass == 2
           and state.overflowState.chunkIndex >= 1
           and state.paintInProgress
           and not state.captureInProgress
           and not state.screenshotAwaitingResult then
            overflow_interaction_shots_before = #screenshot_times
            overflow_interaction_old_generation = state.overflowState.generation
            overflow_interaction_chunk_count = state.overflowState.chunkCount
            send_interaction_event("MERCHANT_CLOSED")
            interaction_closed = true
            local closed = harness.QRTransportState()
            assert(closed.overflowState == nil
                   and not closed.paintInProgress
                   and not closed.captureInProgress
                   and closed.pendingShotDirty,
                "interaction close did not retire the tainted overflow job")
        end
    elseif overflow_interaction_close
       and interaction_closed
       and not overflow_interaction_new_generation then
        local state = harness.QRTransportState()
        if state.overflowState then
            overflow_interaction_new_generation = state.overflowState.generation
            assert(overflow_interaction_new_generation
                       ~= overflow_interaction_old_generation,
                "interaction close reused the tainted overflow generation")
            assert(state.overflowState.chunkIndex == 0
                   and state.overflowState.pass == 1,
                "replacement overflow did not restart at fragment zero/pass one")
        end
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
    if terminal_pre_capture_mode
       and not regression_state.terminalPreCapture.started
       and #screenshot_times == 2 then
        pre_terminal_hash = harness.QRTransportState().lastSnapshotHash
        assert(pre_terminal_hash ~= nil,
            "pre-terminal delivery hash was not committed")
        regression_state.terminalPreCapture.started = true
        applicant_ids = {}
        GetNumGroupMembers = function() return 0 end
        C_LFGList.HasActiveEntryInfo = function() return false end
        C_LFGList.GetActiveEntryInfo = function() return nil end
        harness.EndSession()
        if terminal_pre_capture_kind == "watchdog" then
            assert(harness.AgeCurrentQRBuildForFixture(8.1),
                "terminal watchdog fixture could not age the pre-capture job")
            regression_state.terminalPreCapture.watchdogAged = true
        end
    end
    if terminal_pre_capture_mode
       and regression_state.terminalPreCapture.started
       and not regression_state.terminalPreCapture.injectionReleased then
        local state = harness.QRTransportState()
        if state.terminalClearRetryScheduled
           and not state.paintInProgress
           and not state.captureInProgress then
            regression_state.terminalPreCapture.injectionReleased = true
        end
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
               and (not gameplay_challenge_reload
                    or (state.challengeDormant and not state.scanTickerActive))
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
            challenge_active = fixture_mode ~= "gameplay-challenge-reload"
            regression_state.challengeEndEvent =
                fixture_mode == "gameplay-challenge-reset-lag"
                    and "CHALLENGE_MODE_RESET" or "CHALLENGE_MODE_COMPLETED"
            assert(event_frame.events[regression_state.challengeEndEvent],
                "challenge recovery event was not registered")
            event_frame.scripts.OnEvent(event_frame, regression_state.challengeEndEvent)
            if challenge_active then
                assert(harness.QRTransportState().challengeDormant,
                    "challenge exit ignored the still-active current-state API")
                C_Timer.After(0.1, function() challenge_active = false end)
            end
        end
        gameplay_released = true
    end

    if gameplay_loading_initial
       and not loading_transition_released
       and now >= loading_transition_release_at then
        local state = harness.QRTransportState()
        assert(#screenshot_times == 0 and screenshot_attempts == 0
               and qr_encode_calls == 0
               and gameplay_lfg_read_calls == 0
               and state.suppressedByGameplay
               and state.gameplayLoadingActive
               and state.gameplaySuppressionReason == "loading-screen",
            "initial loading gate allowed QR or LFG work")
        event_frame.scripts.OnEvent(event_frame, "LOADING_SCREEN_DISABLED")
        loading_transition_released = true
    end

    if gameplay_loading_midflight and not loading_transition_started then
        local state = harness.QRTransportState()
        local targetReached = gameplay_loading_during_paint
            and state.paintInProgress and not state.captureInProgress
            or gameplay_loading_during_settle
                and state.captureInProgress and state.forceVisible
            or gameplay_loading_awaiting
                and state.screenshotAwaitingResult
        if targetReached then
            event_frame.scripts.OnEvent(event_frame, "LOADING_SCREEN_ENABLED")
            state = harness.QRTransportState()
            assert(state.suppressedByGameplay
                   and state.gameplayLoadingActive
                   and state.gameplaySuppressionReason == "loading-screen"
                   and not state.qrFrameShown,
                "mid-flight loading did not hard-suppress QR transport")
            if gameplay_loading_awaiting then
                assert(state.screenshotAwaitingResult
                       and state.screenshotAwaitingSuperseded
                       and delayed_screenshot_result,
                    "loading did not supersede the identity-free screenshot result")
                screenshot_times[#screenshot_times + 1] = now
                event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
                state = harness.QRTransportState()
                assert(state.lastSnapshotHash == nil
                       and state.deliverySnapshotHash == nil
                       and state.deliverySnapshotSendCount == 0,
                    "loading-screen screenshot result committed delivery state")
            else
                assert(not state.paintInProgress
                       and not state.captureInProgress
                       and not state.forceVisible,
                    "loading did not cancel pre-screenshot QR work")
            end
            applicant_ids = { 42, 43, 44 }
            loading_transition_encode_calls = qr_encode_calls
            loading_transition_lfg_read_calls = gameplay_lfg_read_calls
            loading_transition_release_at = now + 1.0
            loading_transition_started = true
        end
    elseif gameplay_loading_midflight
       and loading_transition_started
       and not loading_transition_released
       and now >= loading_transition_release_at then
        assert(qr_encode_calls == loading_transition_encode_calls
               and gameplay_lfg_read_calls == loading_transition_lfg_read_calls,
            "loading gate allowed QR build or LFG polling before release")
        event_frame.scripts.OnEvent(event_frame, "LOADING_SCREEN_DISABLED")
        loading_transition_released = true
    end

    if gameplay_loading_awaiting_terminal
       and not terminal_loading_started
       and #screenshot_times == 2
       and screenshot_attempts == 2 then
        applicant_ids = {}
        GetNumGroupMembers = function() return 0 end
        C_LFGList.HasActiveEntryInfo = function() return false end
        C_LFGList.GetActiveEntryInfo = function() return nil end
        harness.EndSession()
    end
    if gameplay_loading_awaiting_terminal
       and not terminal_loading_started
       and screenshot_attempts == 3
       and harness.QRTransportState().screenshotAwaitingResult then
        assert(delayed_screenshot_result,
            "terminal loading fixture lost its delayed screenshot result")
        event_frame.scripts.OnEvent(event_frame, "LOADING_SCREEN_ENABLED")
        combat_active = true
        local suppressed = harness.QRTransportState()
        assert(suppressed.screenshotAwaitingSuperseded
               and suppressed.terminalClearDispatchCount == 0,
            "loading did not refund the superseded terminal dispatch")
        terminal_loading_old_result_at = now + 1.0
        terminal_loading_started = true
    elseif gameplay_loading_awaiting_terminal
       and terminal_loading_started
       and not terminal_loading_old_result_drained
       and now >= terminal_loading_old_result_at then
        local repeatedlySuppressed = harness.QRTransportState()
        assert(repeatedlySuppressed.screenshotAwaitingResult
               and repeatedlySuppressed.terminalClearDispatchCount == 0,
            "repeated gameplay suppression refunded terminal dispatch more than once")
        screenshot_times[#screenshot_times + 1] = now
        event_frame.scripts.OnEvent(event_frame, "SCREENSHOT_SUCCEEDED")
        local after_old = harness.QRTransportState()
        assert(after_old.screenshotPendingTerminalClear
               and after_old.terminalClearDispatchCount == 0,
            "superseded terminal result consumed safe delivery budget")
        terminal_loading_release_at = now + 1.0
        terminal_loading_old_result_drained = true
    elseif gameplay_loading_awaiting_terminal
       and terminal_loading_started
       and terminal_loading_old_result_drained
       and not terminal_loading_released
       and now >= terminal_loading_release_at then
        combat_active = false
        event_frame.scripts.OnEvent(event_frame, "LOADING_SCREEN_DISABLED")
        terminal_loading_released = true
    end

    if (forced_lockdown_suppression or forced_lockdown_transition)
       and not forced_lockdown_started
       and #screenshot_times == 2
       and not harness.QRTransportState().paintInProgress
       and not harness.QRTransportState().captureInProgress then
        chat_lockdown = forced_lockdown_suppression
        if forced_lockdown_suppression then
            forced_lockdown_lfg_reads_before = gameplay_lfg_read_calls
        end
        SlashCmdList.APSCOUT("shotnow")
        local building = harness.QRTransportState()
        assert(building.paintInProgress,
            "lockdown force fixture did not start an asynchronous job")
        if forced_lockdown_transition then
            forced_lockdown_lfg_reads_before = gameplay_lfg_read_calls
            chat_lockdown = true
        end
        event_frame.scripts.OnEvent(event_frame, "LOADING_SCREEN_ENABLED")
        local suppressed = harness.QRTransportState()
        assert(suppressed.suppressedByGameplay
               and suppressed.screenshotPendingForce
               and not suppressed.paintInProgress
               and not suppressed.captureInProgress,
            "loading did not queue the lockdown force job")
        forced_lockdown_release_at = now + 1.0
        forced_lockdown_started = true
    elseif (forced_lockdown_suppression or forced_lockdown_transition)
       and forced_lockdown_started
       and not forced_lockdown_released
       and now >= forced_lockdown_release_at then
        assert(gameplay_lfg_read_calls == forced_lockdown_lfg_reads_before,
            "suppressed lockdown force job performed LFG reads")
        event_frame.scripts.OnEvent(event_frame, "LOADING_SCREEN_DISABLED")
        forced_lockdown_released = true
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

    if gameplay_start_edge_lag and not regression_state.startEdge.started then
        local state = harness.QRTransportState()
        if state.captureInProgress and state.forceVisible then
            local startEvent = gameplay_start_edge_lag_axis == "combat"
                and "PLAYER_REGEN_DISABLED"
                or gameplay_start_edge_lag_axis == "challenge"
                    and "CHALLENGE_MODE_START"
                    or "ENCOUNTER_START"
            local expectedReason = gameplay_start_edge_lag_axis == "combat"
                and "combat"
                or gameplay_start_edge_lag_axis == "challenge"
                    and "mythic-plus"
                    or "raid-encounter"
            assert(not combat_active and not challenge_active and not encounter_active,
                "start-edge fixture did not preserve the injected clean-false API lag")
            assert(event_frame.events[startEvent],
                "gameplay start event was not registered: " .. startEvent)
            event_frame.scripts.OnEvent(event_frame, startEvent, 9001)
            state = harness.QRTransportState()
            assert(state.suppressedByGameplay
                   and state.gameplaySuppressionReason == expectedReason
                   and not state.paintInProgress
                   and not state.captureInProgress
                   and not state.forceVisible
                   and not state.qrFrameShown,
                "clean-false API lag cleared the authoritative gameplay start edge")
            assert(#screenshot_times == 0 and screenshot_attempts == 0,
                "gameplay start edge allowed a settle callback to capture")
            regression_state.startEdge.encodeCalls = qr_encode_calls
            regression_state.startEdge.lfgReadCalls = gameplay_lfg_read_calls
            regression_state.startEdge.releaseAt = now + 1.0
            regression_state.startEdge.started = true
        end
    elseif gameplay_start_edge_lag
       and regression_state.startEdge.started
       and not regression_state.startEdge.released
       and now >= regression_state.startEdge.releaseAt then
        assert(#screenshot_times == 0 and screenshot_attempts == 0
               and qr_encode_calls == regression_state.startEdge.encodeCalls
               and gameplay_lfg_read_calls == regression_state.startEdge.lfgReadCalls,
            "latched gameplay start allowed transport before the matching end")
        local endEvent = gameplay_start_edge_lag_axis == "combat"
            and "PLAYER_REGEN_ENABLED"
            or gameplay_start_edge_lag_axis == "challenge"
                and "CHALLENGE_MODE_COMPLETED"
                or "ENCOUNTER_END"
        assert(event_frame.events[endEvent],
            "gameplay end event was not registered: " .. endEvent)
        event_frame.scripts.OnEvent(event_frame, endEvent, 9001)
        regression_state.startEdge.released = true
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

    if lfg_read_recreate_race and not lfg_read_recreate_race_checked then
        local state = harness.QRTransportState()
        if state.overflowState and #screenshot_times == 0 then
            local oldGeneration = state.overflowState.generation
            local hasCalls = 0
            C_LFGList.HasActiveEntryInfo = function()
                hasCalls = hasCalls + 1
                if hasCalls == 1 then
                    error("injected first-probe listing race")
                end
                return true
            end
            C_LFGList.GetActiveEntryInfo = function()
                return {
                    activityIDs = { 402 },
                    questID = 0,
                    name = "Recreated after unavailable probe",
                    comment = "fresh listing epoch",
                }
            end

            local entry, listingKnown = harness.CheckSessionTransition(true)
            assert(entry == nil and not listingKnown and hasCalls == 1,
                "first unavailable listing probe was not preserved as unknown")
            harness.MaybeTriggerScreenshot(
                false, entry, nil, true, listingKnown
            )
            local deferred = harness.QRTransportState()
            assert(hasCalls == 1
                   and deferred.overflowState
                   and deferred.overflowState.generation == oldGeneration
                   and screenshot_attempts == 0,
                "unknown hint was re-read or captured before reconciliation")

            entry, listingKnown = harness.CheckSessionTransition(true)
            local reconciled = harness.QRTransportState()
            assert(entry and listingKnown and hasCalls == 2
                   and reconciled.overflowState == nil
                   and reconciled.lastSnapshotHash == nil
                   and reconciled.deliverySnapshotHash == nil,
                "fresh listing did not retire old overflow before capture")
            harness.MaybeTriggerScreenshot(
                false, entry, nil, true, listingKnown
            )
            lfg_read_recreate_race_checked = true
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
               and building.terminalClearDispatchCount == 0,
            "terminal shotnow fixture did not start the first clear")
        SlashCmdList.APSCOUT("shotnow")
        local after_build_shotnow = harness.QRTransportState()
        assert(after_build_shotnow.paintInProgress
               and after_build_shotnow.terminalClearDispatchCount == 0
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
    assert(#screenshot_times == 0 and screenshot_attempts == 1,
        string.format("missing result events produced shots=%d attempts=%d, expected 0/1",
            #screenshot_times, screenshot_attempts))
    assert(state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and state.screenshotAwaitingResult
           and state.screenshotAwaitingSuperseded
           and not state.forceVisible
           and not state.qrFrameShown,
        "missing result event did not stop behind a fail-closed waiter")
    assert(state.screenshotFailureHash == nil
           and state.screenshotFailureAttemptCount == 0,
        "missing result event was counted as a safely attributable failure")
elseif screenshot_late_timeout then
    local state = harness.QRTransportState()
    local expectedShots = screenshot_late_timeout_success and 3 or 2
    assert(screenshot_late_timeout_old_result_drained
           and screenshot_late_timeout_checked,
        "late timeout result boundaries were not exercised")
    assert(#screenshot_times == expectedShots and screenshot_attempts == 3,
        string.format(
            "late result produced shots=%d attempts=%d, expected %d/3",
            #screenshot_times,
            screenshot_attempts,
            expectedShots
        ))
    assert(not state.screenshotAwaitingResult
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2
           and state.screenshotFailureAttemptCount == 0,
        "late result contaminated replacement delivery state")
elseif capture_fresh_timeout_clock then
    local state = harness.QRTransportState()
    assert(capture_clock_result_checked,
        "fresh capture timeout-clock boundary was not exercised")
    assert(#screenshot_times == 2 and screenshot_attempts == 2
           and not state.screenshotAwaitingResult
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2
           and state.screenshotFailureAttemptCount == 0,
        "fresh capture clock did not settle two normal deliveries")
elseif lfg_read_transient then
    local state = harness.QRTransportState()
    assert(lfg_read_transient_checked,
        "transient LFG read boundaries were not exercised")
    assert(not state.sessionActive
           and state.terminalClearDispatchCount == 2
           and not state.screenshotPendingTerminalClear,
        "clean inactive control did not settle terminal delivery")
    assert(#screenshot_times == 4 and screenshot_attempts == 4,
        string.format(
            "transient LFG fixture produced shots=%d attempts=%d instead of 4/4",
            #screenshot_times,
            screenshot_attempts
        ))
elseif lfg_read_partial_identity then
    local state = harness.QRTransportState()
    assert(regression_state.lfgPartialIdentityChecked,
        "partial LFG identity boundaries were not exercised")
    assert(not state.sessionActive
           and state.terminalClearDispatchCount == 2
           and not state.screenshotPendingTerminalClear,
        "partial identity control did not settle terminal delivery")
    assert(#screenshot_times == 4 and screenshot_attempts == 4,
        string.format(
            "partial LFG identity fixture produced shots=%d attempts=%d instead of 4/4",
            #screenshot_times,
            screenshot_attempts
        ))
elseif lfg_read_recreate_race then
    local state = harness.QRTransportState()
    assert(lfg_read_recreate_race_checked,
        "unavailable-to-recreated listing race was not exercised")
    assert(state.overflowState == nil
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "recreated listing did not settle a fresh complete overflow")
elseif activity_info_transient then
    local state = harness.QRTransportState()
    assert(regression_state.activityInfoPhase == 3,
        "transient activity-info failure/recovery boundaries were not exercised")
    assert(#screenshot_times == 6 and screenshot_attempts == 6,
        string.format(
            "activity-info recovery produced shots=%d attempts=%d instead of 6/6",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(state.sessionActive
           and state.lastEmittedApplicantCount == 7
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "activity-info recovery did not settle the newest applicant snapshot")
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
elseif terminal_pre_capture_mode then
    local state = harness.QRTransportState()
    assert(regression_state.terminalPreCapture.started
           and regression_state.terminalPreCapture.injectionReleased,
        "terminal pre-capture failure boundary was not exercised")
    if terminal_pre_capture_kind == "watchdog" then
        assert(regression_state.terminalPreCapture.watchdogAged,
            "terminal watchdog clock was not aged")
    end
    assert(#screenshot_times == 4 and screenshot_attempts == 4,
        string.format(
            "terminal pre-capture recovery produced shots=%d attempts=%d instead of 4/4",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(not state.sessionActive
           and not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown
           and not state.terminalClearRetryScheduled,
        "terminal pre-capture recovery did not settle in an idle ended session")
    assert(state.terminalClearDispatchCount == 2
           and state.terminalClearPreCaptureFailureCount == 1,
        string.format(
            "terminal pre-capture failure consumed the physical clear budget: dispatch=%s pre-capture=%s",
            tostring(state.terminalClearDispatchCount),
            tostring(state.terminalClearPreCaptureFailureCount)
        ))
    assert(state.lastSnapshotHash ~= nil
           and state.lastSnapshotHash ~= pre_terminal_hash
           and state.deliverySnapshotHash == nil
           and state.deliverySnapshotSendCount == 0,
        "terminal pre-capture recovery did not commit the clear state")
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
elseif forced_lockdown_suppression or forced_lockdown_transition then
    local state = harness.QRTransportState()
    assert(forced_lockdown_started and forced_lockdown_released,
        "forced lockdown suppression boundaries were not exercised")
    assert(gameplay_lfg_read_calls == forced_lockdown_lfg_reads_before,
        "resumed forced job widened its original LFG-read permission")
    assert(#screenshot_times == 4 and screenshot_attempts == 4,
        string.format(
            "lockdown force resume produced shots=%d attempts=%d instead of 4/4",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2
           and not state.screenshotPendingForce,
        "lockdown force resume did not settle bounded delivery")
elseif gameplay_loading_awaiting_terminal then
    local state = harness.QRTransportState()
    assert(terminal_loading_started
           and terminal_loading_old_result_drained
           and terminal_loading_released,
        "terminal loading race boundaries were not exercised")
    assert(#screenshot_times == 5 and screenshot_attempts == 5,
        string.format(
            "terminal loading resume produced shots=%d attempts=%d instead of 5/5",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(not state.sessionActive
           and not state.suppressedByGameplay
           and not state.screenshotPendingTerminalClear
           and not state.terminalClearRetryScheduled
           and state.terminalClearDispatchCount == 2,
        "terminal loading resume did not preserve two safe clear deliveries")
elseif gameplay_loading_initial or gameplay_loading_midflight then
    local state = harness.QRTransportState()
    assert(loading_transition_released,
        "loading-screen release boundary was not exercised")
    local expected_attempts = gameplay_loading_awaiting and 3 or 2
    assert(#screenshot_times == expected_attempts
           and screenshot_attempts == expected_attempts,
        string.format(
            "loading resume produced shots=%d attempts=%d instead of %d/%d",
            #screenshot_times,
            screenshot_attempts,
            expected_attempts,
            expected_attempts
        ))
    assert(not state.suppressedByGameplay
           and not state.gameplayLoadingActive
           and not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "loading-screen transport did not rebuild and settle")
    assert(state.lastEmittedApplicantCount
           == (gameplay_loading_initial and 5 or 3),
        "loading resume did not deliver the newest applicant generation")
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
           and (not gameplay_challenge_reload
                or (not state.challengeDormant and state.scanTickerActive
                    and state.challengeDormantOptionalEventsRegistered
                    and state.scanTickerStartCount >= 2
                    and state.scanTickerStopCount >= 1
                    and event_frame.events.GROUP_ROSTER_UPDATE
                    and event_frame.events.CHAT_MSG_ADDON
                    and event_frame.events.PLAYER_INTERACTION_MANAGER_FRAME_SHOW))
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
elseif gameplay_start_edge_lag then
    local state = harness.QRTransportState()
    assert(regression_state.startEdge.started and regression_state.startEdge.released,
        "gameplay start-edge lag boundaries were not exercised")
    assert(#screenshot_times == 2 and screenshot_attempts == 2,
        string.format(
            "gameplay start-edge resume produced shots=%d attempts=%d instead of 2/2",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(not state.suppressedByGameplay
           and not state.pendingShotDirty
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown,
        "gameplay start-edge latch did not resume and settle after the matching end")
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
elseif overflow_interaction_close_awaiting then
    local state = harness.QRTransportState()
    assert(interaction_closed
           and overflow_interaction_awaiting_old_result_drained
           and overflow_interaction_new_generation
           and overflow_interaction_chunk_count,
        "awaiting overflow interaction-close boundaries were not exercised")
    local cleanPostCloseShots =
        #screenshot_times - overflow_interaction_shots_before - 1
    assert(cleanPostCloseShots == overflow_interaction_chunk_count * 2,
        string.format(
            "post-timeout overflow captured %d clean frames instead of two %d-frame passes",
            cleanPostCloseShots,
            overflow_interaction_chunk_count
        ))
    assert(screenshot_attempts == 1 + overflow_interaction_chunk_count * 2
           and state.overflowState == nil
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "late panel result contaminated replacement overflow delivery")
elseif overflow_interaction_close then
    local state = harness.QRTransportState()
    assert(interaction_closed
           and overflow_interaction_new_generation
           and overflow_interaction_chunk_count,
        "overflow interaction-close boundaries were not exercised")
    local post_close_shots =
        #screenshot_times - overflow_interaction_shots_before
    assert(post_close_shots == overflow_interaction_chunk_count * 2,
        string.format(
            "post-close overflow captured %d frames instead of two clean %d-frame passes",
            post_close_shots,
            overflow_interaction_chunk_count
        ))
    assert(state.overflowState == nil
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "post-close overflow did not commit two complete clean passes")
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
elseif interaction_persistent then
    local state = harness.QRTransportState()
    assert(#screenshot_times == 3 and screenshot_attempts == 3,
        string.format(
            "persistent interaction produced shots=%d attempts=%d, expected 3/3",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(interaction_closed
           and not state.suppressedByInteraction
           and not state.interactionDeferralActive
           and not state.paintInProgress
           and not state.captureInProgress
           and not state.forceVisible
           and not state.qrFrameShown,
        "persistent interaction did not resend after the panel closed")
    assert(state.lastEmittedApplicantCount == 3
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "persistent interaction did not settle the newest bounded resend")
elseif interaction_quick_close then
    local state = harness.QRTransportState()
    assert(interaction_opened and interaction_closed,
        "quick interaction close boundary was not exercised")
    assert(#screenshot_times == interaction_shots_before
           and screenshot_attempts == interaction_shots_before,
        string.format(
            "quick interaction close produced shots=%d attempts=%d instead of %d/%d",
            #screenshot_times,
            screenshot_attempts,
            interaction_shots_before,
            interaction_shots_before
        ))
    assert(state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "quick interaction close disturbed stable delivery state")
elseif interaction_close_awaiting then
    local state = harness.QRTransportState()
    assert(interaction_closed
           and #screenshot_times == 3
           and screenshot_attempts == 3,
        string.format(
            "interaction-close race produced shots=%d attempts=%d, expected 3/3",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(not state.screenshotAwaitingResult
           and not state.screenshotAwaitingSuperseded
           and not state.pendingShotDirty
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "interaction-close race did not settle one safe post-close resend")
elseif interaction_force then
    local state = harness.QRTransportState()
    assert(#screenshot_times == 2 and screenshot_attempts == 2,
        string.format(
            "force plus resumed transport produced shots=%d attempts=%d, expected 2/2",
            #screenshot_times,
            screenshot_attempts
        ))
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
elseif fixture_mode == "external-screenshot-during-waiter" then
    local state = harness.QRTransportState()
    assert(regression_state.externalWaiterOverlapChecked,
        "in-flight external screenshot overlap was not exercised")
    assert(#screenshot_times == 2 and screenshot_attempts == 3,
        string.format(
            "overlap retry produced shots=%d attempts=%d, expected 2/3",
            #screenshot_times,
            screenshot_attempts
        ))
    assert(not state.screenshotAwaitingResult
           and not state.screenshotExternalInProgress
           and not state.screenshotOverlapAmbiguous
           and state.screenshotFailureAttemptCount == 0
           and state.deliverySnapshotHash == state.lastSnapshotHash
           and state.deliverySnapshotSendCount == 2,
        "overlap retry did not settle a clean bounded APS delivery")
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
   and not capture_fresh_timeout_clock
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
if external_screenshot_mode then
    assert(external_screenshot_released,
        "external screenshot serialization boundary was not exercised")
end
assert(screenshot_event_timeout or not final_state.screenshotAwaitingResult,
    "QR capture left a stale SCREENSHOT_* result waiter")
assert(final_state.qrFrameStrata == "DIALOG",
    "QR capture did not restore DIALOG frame strata")

print(string.format("ok qr-capture-lifecycle mode=%s shots=%d attempts=%d",
    fixture_mode, #screenshot_times, screenshot_attempts))
