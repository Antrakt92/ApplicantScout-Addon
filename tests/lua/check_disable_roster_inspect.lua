local env = dofile("tests/lua/appscout_fixture_env.lua")

env.unit_data.party3 = nil
env.unit_data.party4 = nil
GetNumGroupMembers = function() return 3 end
IsInRaid = function() return false end

local now = 1000
local resolvedSpec = 0
local inspectRequests = {}
local clearInspectCalls = 0
GetTime = function() return now end
GetInspectSpecialization = function(unit)
    if unit == "player" then return 73 end
    if unit == "party1" then return resolvedSpec end
    if unit == "party2" then return 70 end
    return 0
end
C_PaperDollInfo.GetInspectItemLevel = function(unit)
    if unit == "player" then return 710 end
    return 0
end
CanInspect = function(unit)
    return unit == "party1" or unit == "party2"
end
NotifyInspect = function(unit)
    inspectRequests[#inspectRequests + 1] = unit
end
ClearInspectPlayer = function()
    clearInspectCalls = clearInspectCalls + 1
end
ApplicantScoutDB = { enabled = true, debug = false }

local harness = env.load_addon()
harness.StartSession()
harness.OnRosterInspectReady("Party-1")
assert(clearInspectCalls == 0,
    "an unowned INSPECT_READY must not clear global inspect state")
assert(harness.EnsureRosterInspectBatchBeforeSnapshot() == true,
    "fixture did not start the first roster inspection")
assert(#inspectRequests == 1 and inspectRequests[1] == "party1",
    "fixture did not request the expected first party member")
harness.OnRosterInspectReady("Party-2")
assert(clearInspectCalls == 0,
    "a different GUID must not consume the owned inspect request")

harness.SetEnabled(false)
assert(clearInspectCalls == 1,
    "disabling must release the inspect request while ownership is known")
now = now + 2
resolvedSpec = 63
harness.OnRosterInspectReady("Party-1")

assert(#inspectRequests == 1,
    "late INSPECT_READY restarted roster inspection after the kill switch")
assert(clearInspectCalls == 1,
    "a late disabled INSPECT_READY must not clear unowned global inspect state")

io.write("disable-roster-inspect-ok\n")
