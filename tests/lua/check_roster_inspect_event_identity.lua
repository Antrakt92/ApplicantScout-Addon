local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

env.unit_data.party2 = nil
env.unit_data.party3 = nil
env.unit_data.party4 = nil
GetNumGroupMembers = function() return 2 end
IsInRaid = function() return false end

local inspect_requests = 0
local inspect_releases = 0
NotifyInspect = function(unit)
    assert(unit == "party1", "fixture should inspect only the unresolved party member")
    inspect_requests = inspect_requests + 1
end
ClearInspectPlayer = function()
    inspect_releases = inspect_releases + 1
end
GetInspectSpecialization = function(unit)
    if unit == "player" then return 73 end
    return 63
end
C_PaperDollInfo.GetInspectItemLevel = function() return 0 end
ApplicantScoutDB = { enabled = true, debug = false }

local harness = env.load_addon()
harness.StartSession()
assert(
    harness.EnsureRosterInspectBatchBeforeSnapshot() == true,
    "the unresolved roster member should start one owned inspect"
)
assert(inspect_requests == 1, "expected exactly one owned inspect request")

local originalIsSecretValue = issecretvalue
local secretGUID = {}
issecretvalue = function(value)
    if value == secretGUID then return true end
    return originalIsSecretValue(value)
end
local ok, resolved = pcall(harness.OnRosterInspectReady, secretGUID)
assert(ok, "a secret INSPECT_READY GUID must not raise")
assert(resolved == false, "a secret INSPECT_READY GUID must be rejected")
assert(inspect_releases == 0, "a secret event must not release the owned inspect")

local unprobeableGUID = {}
issecretvalue = function(value)
    if value == unprobeableGUID then error("secret GUID probe failed") end
    return originalIsSecretValue(value)
end
ok, resolved = pcall(harness.OnRosterInspectReady, unprobeableGUID)
assert(ok, "an unprobeable INSPECT_READY GUID must not raise")
assert(resolved == false, "an unprobeable INSPECT_READY GUID must be rejected")
assert(inspect_releases == 0, "a failed probe must not release the owned inspect")

issecretvalue = originalIsSecretValue
assert(
    harness.OnRosterInspectReady("Party-1") == true,
    "the matching clean callback should still resolve the owned inspect"
)
assert(inspect_releases == 1, "the matching clean callback should release the inspect")

print("ok roster-inspect-event-identity")
