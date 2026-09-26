local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

GetNumGroupMembers = function() return 0 end
IsInRaid = function() return false end

local playerRealmReads = 0
local originalUnitFullName = UnitFullName
UnitFullName = function(unit)
    if unit == "player" then playerRealmReads = playerRealmReads + 1 end
    return originalUnitFullName(unit)
end

C_LFGList.GetApplicantInfo = function(id)
    return {
        applicantID = id,
        applicationStatus = "applied",
        numMembers = 5,
    }
end
C_LFGList.GetApplicantMemberInfo = function(id, memberIndex)
    return string.format("Applicant%d%02d", id, memberIndex),
        "MAGE", nil, nil, 700, nil, nil, nil, nil,
        "DAMAGER", nil, 2500, nil, nil, nil, 63
end

local harness = env.load_addon()
local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "Realm reuse fixture",
    comment = "bare applicant names share the player realm",
}
local payload = assert(harness.BuildPayload)(entry, { 1, 2, 3, 4, 5, 6 }, false)

assert(#payload > 0, "realm reuse fixture emitted an empty payload")
assert(playerRealmReads == 1, string.format(
    "payload resolved the player realm %d times for 30 bare applicant names",
    playerRealmReads
))

-- Roster coverage: the bare-party fallback and the RaiderIO lookup must reuse
-- the same hoisted realm instead of re-reading UnitFullName("player") per
-- row. GetNumGroupMembers=0 above masks this path entirely, so a roster phase
-- is required to keep the leak covered. The stdout contract stays exactly one
-- line; the roster read bound is enforced by the assert below.
playerRealmReads = 0
GetNumGroupMembers = function() return 5 end
for _, unit in ipairs({ "party1", "party2", "party3", "party4" }) do
    env.unit_data[unit].unitFullName = { env.unit_data[unit].name, nil }
    env.unit_data[unit].unitName = env.unit_data[unit].name
end
local _, rosterCount = harness.BuildRosterPayloadRows(0, 0)
assert(rosterCount == 5, "bare-name roster did not transport 5 members")
assert(playerRealmReads == 2, string.format(
    "roster resolved the player realm %d times for 4 bare party names (hoist + player row)",
    playerRealmReads
))

print("ok player-realm-lookup-reuse reads=1")
