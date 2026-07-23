local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

env.unit_data.party2 = nil
env.unit_data.party3 = nil
env.unit_data.party4 = nil
GetNumGroupMembers = function() return 2 end
IsInRaid = function() return false end

local now = 1000
local timers = {}
local roster_reads = 0
local inspectable = false
local remote_spec_id = 0
local remote_item_level = 0
local inspect_requests = 0

GetTime = function() return now end
C_Timer.After = function(delay, callback)
    timers[#timers + 1] = { delay = delay, callback = callback }
end
GetInspectSpecialization = function(unit)
    if unit == "player" then return 73 end
    roster_reads = roster_reads + 1
    return remote_spec_id
end
C_PaperDollInfo.GetInspectItemLevel = function(unit)
    if unit == "player" then return 710 end
    return remote_item_level
end
CanInspect = function(unit)
    return unit == "party1" and inspectable
end
NotifyInspect = function(unit)
    assert(inspectable and unit == "party1",
        "fixture issued NotifyInspect outside the owned recovery path")
    inspect_requests = inspect_requests + 1
end
ApplicantScoutDB = { enabled = true, debug = false }

local harness = env.load_addon()
local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "Roster retry fixture",
}

local function timer_count(delay)
    local count = 0
    for _, timer in ipairs(timers) do
        if timer.delay == delay then count = count + 1 end
    end
    return count
end

local function run_timer(delay)
    for index, timer in ipairs(timers) do
        if timer.delay == delay then
            table.remove(timers, index)
            now = now + delay
            timer.callback()
            return timer.callback
        end
    end
    error("missing timer at delay " .. tostring(delay))
end

local function take_timer(delay)
    for index, timer in ipairs(timers) do
        if timer.delay == delay then
            table.remove(timers, index)
            return timer.callback
        end
    end
    error("missing timer at delay " .. tostring(delay))
end

local function poll(applicant_ids)
    local deferred = not harness.ShouldAttemptRosterLoad()
    local before_reads = roster_reads
    if not deferred then
        harness.EnsureRosterInspectBatchBeforeSnapshot()
    end
    local payload = assert(harness.BuildPayload(
        entry,
        applicant_ids or {},
        false,
        false,
        deferred
    ))
    local incomplete = deferred or harness.LastPayloadRosterIncomplete()
    if incomplete then
        assert(harness.ScheduleRosterLoadRetry())
    else
        harness.ClearRosterLoadRetryState()
    end
    return payload, deferred, roster_reads - before_reads
end

harness.StartSession()
-- StartSession owns unrelated roster-preflight/leader timers. Isolate the
-- load-retry queue after its state initialization.
timers = {}

local first_payload, first_deferred, first_reads = poll({})
assert(not first_deferred and first_reads > 0, "first roster build was not attempted")
assert(harness.LastPayloadRosterIncomplete(), "stable unreadable roster stayed authoritative")
assert(string.find(first_payload, "Friend-Realm", 1, true) == nil,
    "partial roster bytes escaped authority withholding")
local load_state = harness.RosterLoadRetryState()
assert(load_state.attempt == 1 and not load_state.ready and not load_state.exhausted)
assert(timer_count(0.5) == 1, "first retry did not use the 0.5s backoff")
local inspect_state = harness.RosterInspectFailureState("Party-1")
assert(inspect_state.failures == 1 and not inspect_state.exhausted,
    "CanInspect=false did not consume the first per-GUID failure")

-- Listing/applicant polling continues during the roster wait, but the roster
-- and RaiderIO builder stays skipped and repeated polls coalesce one timer.
for _ = 1, 10 do
    local payload, deferred, read_delta = poll({ 42 })
    assert(deferred and read_delta == 0, "deferred poll rebuilt the roster")
    assert(string.find(payload, "Tankone-Realm", 1, true),
        "applicant polling stopped with the roster builder")
    assert(string.find(payload, "Friend-Realm", 1, true) == nil,
        "deferred roster row leaked into applicant update")
end
load_state = harness.RosterLoadRetryState()
assert(load_state.attempt == 1 and timer_count(0.5) == 1,
    "coalesced polls spent retry attempts or duplicated timers")

local expected_delays = { 0.5, 2.0, 5.0, 15.0 }
for index, delay in ipairs(expected_delays) do
    run_timer(delay)
    local _, deferred, read_delta = poll({})
    assert(not deferred and read_delta > 0,
        "backoff callback did not permit roster attempt " .. tostring(index + 1))
    local state = harness.RosterLoadRetryState()
    if index < #expected_delays then
        assert(state.attempt == index + 1 and not state.exhausted,
            "retry attempt did not advance exactly once")
        assert(timer_count(expected_delays[index + 1]) == 1,
            "next retry delay was not scheduled")
    else
        assert(state.attempt == #expected_delays and state.exhausted and not state.ready,
            "stable failure did not park after the bounded backoff: attempt="
            .. tostring(state.attempt)
            .. " ready=" .. tostring(state.ready)
            .. " exhausted=" .. tostring(state.exhausted))
    end
end

inspect_state = harness.RosterInspectFailureState("Party-1")
assert(inspect_state.failures == 2 and inspect_state.exhausted,
    "stable uninspectable GUID did not share the session inspect budget")
local parked_reads = roster_reads
for _ = 1, 20 do
    local _, deferred, read_delta = poll({ 42 })
    assert(deferred and read_delta == 0, "parked retry rebuilt the roster")
end
assert(roster_reads == parked_reads and #timers == 0,
    "parked retry retained timer or polling ownership")

-- A roster event permits one fresh transport attempt but intentionally keeps
-- the exhausted per-GUID inspect budget for the unchanged member.
harness.FireEvent("GROUP_ROSTER_UPDATE")
load_state = harness.RosterLoadRetryState()
inspect_state = harness.RosterInspectFailureState("Party-1")
assert(load_state.attempt == 0 and load_state.ready and not load_state.exhausted,
    "roster event did not rearm transport loading")
assert(inspect_state.failures == 2 and inspect_state.exhausted,
    "roster event bypassed the unchanged GUID inspect budget")
local _, event_deferred, event_reads = poll({ 42 })
assert(not event_deferred and event_reads > 0,
    "roster event did not permit exactly one fresh builder attempt")

-- A global INSPECT_READY without an ApplicantScout-owned request must not
-- consume another addon's/manual inspect state or rearm this parked batch.
inspectable = true
remote_spec_id = 63
remote_item_level = 704
local before_unowned = harness.RosterLoadRetryState()
harness.FireEvent("INSPECT_READY", "Party-1")
load_state = harness.RosterLoadRetryState()
assert(load_state.attempt == before_unowned.attempt
    and load_state.ready == before_unowned.ready
    and load_state.exhausted == before_unowned.exhausted,
    "unowned INSPECT_READY changed roster loading state")

-- A real roster/spec signal clears the exhausted identity, allowing one owned
-- request. Only its matching INSPECT_READY can publish the recovered roster.
remote_spec_id = 0
remote_item_level = 0
harness.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "party1")
timers = {}
local _, recovery_deferred = poll({})
assert(not recovery_deferred and inspect_requests == 1,
    "recovery did not create one owned inspect request")
remote_spec_id = 63
remote_item_level = 704
harness.FireEvent("INSPECT_READY", "Party-1")
timers = {}
load_state = harness.RosterLoadRetryState()
assert(load_state.attempt == 0 and load_state.ready and not load_state.exhausted,
    "owned INSPECT_READY did not rearm roster loading")
local recovered_payload, recovered_deferred = poll({})
assert(not recovered_deferred and not harness.LastPayloadRosterIncomplete(),
    "late inspect recovery did not produce authoritative roster")
assert(harness.LastPayloadRosterCount() == 2, "recovered roster count is incomplete")
assert(string.find(recovered_payload, "Friend-Realm", 1, true),
    "recovered roster row was not serialized")

-- Session replacement invalidates an old callback even if it fires later.
inspectable = false
remote_spec_id = 0
remote_item_level = 0
harness.FireEvent("PLAYER_SPECIALIZATION_CHANGED", "party1")
timers = {}
poll({})
local stale_callback = take_timer(0.5)
harness.EndSession()
harness.StartSession()
timers = {}
local fresh_state = harness.RosterLoadRetryState()
assert(fresh_state.attempt == 0 and fresh_state.ready and not fresh_state.exhausted)
stale_callback()
local after_stale = harness.RosterLoadRetryState()
assert(after_stale.attempt == fresh_state.attempt
    and after_stale.ready == fresh_state.ready
    and after_stale.exhausted == fresh_state.exhausted,
    "stale session callback mutated fresh retry state")
assert(not harness.QRTransportState().pendingShotDirty,
    "stale session callback dirtied the fresh transport")

print("ok roster-load-retry-backoff reads=" .. tostring(roster_reads))
