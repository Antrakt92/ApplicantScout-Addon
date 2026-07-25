local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local mode = assert(arg and arg[1], "missing identity mode")
local unitExistsMode = mode == "unit-exists-secret" or mode == "unit-exists-error"
local unitGUIDMode = mode == "unit-guid-secret" or mode == "unit-guid-error"
local errorMode = mode == "unit-exists-error" or mode == "unit-guid-error"
assert(unitExistsMode or unitGUIDMode, "unexpected identity mode")

env.unit_data.party2 = nil
env.unit_data.party3 = nil
env.unit_data.party4 = nil
GetNumGroupMembers = function() return 2 end
IsInRaid = function() return false end

local now = 1000
local timers = {}
local lockdown = true
local identityUnreadable = true
local secretValue = {}

GetTime = function() return now end
InCombatLockdown = function() return lockdown end
C_Timer.After = function(delay, callback)
    timers[#timers + 1] = { delay = delay, callback = callback }
end

local originalIsSecretValue = issecretvalue
issecretvalue = function(value)
    if value == secretValue then return true end
    return originalIsSecretValue(value)
end

local originalUnitExists = UnitExists
UnitExists = function(unit)
    if identityUnreadable and unitExistsMode and unit == "party1" then
        if errorMode then error("UnitExists unreadable") end
        return secretValue
    end
    return originalUnitExists(unit)
end

local originalUnitGUID = UnitGUID
UnitGUID = function(unit)
    if identityUnreadable and unitGUIDMode and unit == "party1" then
        if errorMode then error("UnitGUID unreadable") end
        return secretValue
    end
    return originalUnitGUID(unit)
end

local originalGetInspectSpecialization = GetInspectSpecialization
GetInspectSpecialization = function(unit)
    if identityUnreadable and unit == "party1" then return 0 end
    return originalGetInspectSpecialization(unit)
end
local originalGetInspectItemLevel = C_PaperDollInfo.GetInspectItemLevel
C_PaperDollInfo.GetInspectItemLevel = function(unit)
    if identityUnreadable and unit == "party1" then return 0 end
    return originalGetInspectItemLevel(unit)
end

ApplicantScoutDB = { enabled = true, debug = false }
local harness = env.load_addon()
local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "Roster unknown identity fixture",
}

local function run_timer(delay)
    for index, timer in ipairs(timers) do
        if timer.delay == delay then
            table.remove(timers, index)
            now = now + delay
            timer.callback()
            return
        end
    end
    error("missing timer at delay " .. tostring(delay))
end

local function build_incomplete_and_schedule()
    assert(harness.ShouldAttemptRosterLoad(), "bounded retry was not ready")
    assert(harness.BuildPayload(entry, {}, false, false, false))
    assert(harness.LastPayloadRosterIncomplete(), "unknown identity stayed authoritative")
    assert(harness.ScheduleRosterLoadRetry(), "unknown identity did not enter backoff")
end

harness.StartSession()
timers = {}
build_incomplete_and_schedule()
for _, delay in ipairs({ 0.5, 2.0, 5.0, 15.0 }) do
    run_timer(delay)
    build_incomplete_and_schedule()
end

local state = harness.RosterLoadRetryState()
assert(state.exhausted and not state.ready, "unknown identity did not exhaust bounded retries")
assert(state.combatDeferred, "combat identity uncertainty did not arm recovery")
local expectedReason = unitExistsMode and "unit-exists-unknown" or "unit-guid-unknown"
assert(state.blockReason == expectedReason,
    "unexpected identity block reason: " .. tostring(state.blockReason))

identityUnreadable = false
lockdown = false
harness.FireEvent("PLAYER_REGEN_ENABLED")
state = harness.RosterLoadRetryState()
assert(state.attempt == 0 and state.ready and not state.exhausted,
    "post-combat identity recovery did not rearm roster loading")
assert(not state.combatDeferred, "post-combat identity recovery remained armed")

local payload = assert(harness.BuildPayload(entry, {}, false, false, false))
assert(not harness.LastPayloadRosterIncomplete(), "clean post-combat roster stayed incomplete")
assert(harness.LastPayloadRosterCount() == 2, "clean post-combat roster count is incomplete")
assert(string.find(payload, "Friend-Realm", 1, true),
    "clean post-combat roster row was not serialized")

-- Recovery is one-shot: a later exhausted state is not reset by another regen
-- event unless a fresh unknown combat read rearms it.
for _, delay in ipairs({ 0.5, 2.0, 5.0, 15.0 }) do
    assert(harness.ScheduleRosterLoadRetry())
    run_timer(delay)
end
assert(harness.ScheduleRosterLoadRetry())
state = harness.RosterLoadRetryState()
assert(state.exhausted and not state.combatDeferred, "fixture did not rebuild parked state")
harness.FireEvent("PLAYER_REGEN_ENABLED")
state = harness.RosterLoadRetryState()
assert(state.exhausted, "unarmed regen bypassed the bounded retry park")

print("roster-unknown-identity-recovery-ok mode=" .. mode)
