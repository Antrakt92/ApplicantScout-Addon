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

print("ok player-realm-lookup-reuse reads=" .. playerRealmReads)
