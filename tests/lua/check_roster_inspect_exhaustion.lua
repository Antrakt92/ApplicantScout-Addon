local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

env.unit_data.party2 = nil
env.unit_data.party3 = nil
env.unit_data.party4 = nil
GetNumGroupMembers = function() return 2 end
IsInRaid = function() return false end

local now = 1000
local inspect_requests = 0
local remote_spec_id = 0
GetTime = function() return now end
GetInspectSpecialization = function(unit)
    if unit == "player" then return 73 end
    return remote_spec_id
end
C_PaperDollInfo.GetInspectItemLevel = function() return 0 end
NotifyInspect = function(unit)
    assert(unit == "party1", "fixture should inspect only the unresolved party member")
    inspect_requests = inspect_requests + 1
end

local harness = env.load_addon()
harness.StartSession()

assert(
    harness.EnsureRosterInspectBatchBeforeSnapshot() == true,
    "the first unresolved roster member should start one inspect"
)
assert(inspect_requests == 1, "expected exactly one initial inspect request")

now = 1005
assert(
    harness.EnsureRosterInspectBatchBeforeSnapshot() == false,
    "a timed-out inspect must release the roster snapshot"
)
assert(inspect_requests == 1, "timeout handling must not reissue immediately")
assert(
    harness.EnsureRosterInspectBatchBeforeSnapshot() == false,
    "the same GUID must remain suppressed during its retry cooldown"
)
assert(inspect_requests == 1, "cooldown must keep inspect requests bounded")

now = 1021
assert(
    harness.EnsureRosterInspectBatchBeforeSnapshot() == true,
    "the unresolved GUID should receive one bounded retry after cooldown"
)
assert(inspect_requests == 2, "expected exactly one post-cooldown retry")

now = 1026
assert(
    harness.EnsureRosterInspectBatchBeforeSnapshot() == false,
    "the second timeout must exhaust the GUID for this session"
)
now = 2000
assert(
    harness.EnsureRosterInspectBatchBeforeSnapshot() == false,
    "an exhausted GUID must not reopen another batch later in the same session"
)
assert(inspect_requests == 2, "session retry budget must remain bounded")

local payload = harness.BuildPayload(
    { activityIDs = { 401 }, questID = 0, name = "Inspect exhaustion fixture" },
    {},
    false,
    false
)
assert(type(payload) == "string" and #payload > 0, "partial roster payload must serialize")
assert(harness.LastPayloadRosterCount() == 2, "partial roster must retain both group rows")
assert(inspect_requests == 2, "payload construction must respect exhaustion state")

harness.EndSession()
harness.StartSession()
remote_spec_id = 63
assert(
    harness.EnsureRosterInspectBatchBeforeSnapshot() == true,
    "a new listing session must reset the per-GUID retry budget"
)
assert(inspect_requests == 3, "new session should permit one fresh inspect")
harness.OnRosterInspectReady("Party-1")
assert(
    harness.EnsureRosterInspectBatchBeforeSnapshot() == false,
    "a partial inspect callback must enter the same retry cooldown"
)
assert(inspect_requests == 3, "partial callback cooldown must suppress immediate retry")

now = 2016
assert(
    harness.EnsureRosterInspectBatchBeforeSnapshot() == true,
    "a partial callback should receive one bounded retry after cooldown"
)
assert(inspect_requests == 4, "expected one retry after the partial callback")
harness.OnRosterInspectReady("Party-1")
now = 3000
assert(
    harness.EnsureRosterInspectBatchBeforeSnapshot() == false,
    "two partial callbacks must exhaust the GUID for the session"
)
assert(inspect_requests == 4, "partial callbacks must share the bounded request budget")

print("ok roster-inspect-exhaustion requests=" .. inspect_requests)
