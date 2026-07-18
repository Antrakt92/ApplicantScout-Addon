local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

env.install_raid_roster(40)
C_LFGList.GetApplicantInfo = function(id)
    return {
        applicantID = id,
        applicationStatus = "applied",
        numMembers = 1,
    }
end
C_LFGList.GetApplicantMemberInfo = function(id, memberIndex)
    if memberIndex ~= 1 then return nil end
    return string.format("Applicant%02d-Realm", id),
        "MAGE", nil, nil, 700, nil, nil, nil, nil,
        "DAMAGER", nil, 2500, nil, nil, nil, 63
end

local harness = env.load_addon({})
local applicantIDs = {}
for id = 1, 40 do applicantIDs[id] = id end

local originalGsub = string.gsub
local gsubCount = 0
string.gsub = function(...)
    gsubCount = gsubCount + 1
    return originalGsub(...)
end
local payload = assert(harness.BuildPayload)({
    activityIDs = { 401 },
    questID = 0,
    name = "Applicants 40",
    comment = "stable",
}, applicantIDs, false)
string.gsub = originalGsub

assert(gsubCount <= 4000, string.format(
    "transport payload repeated full string sanitation %d times",
    gsubCount
))
assert(#payload == 3817, "sanitization reuse changed the APS1 payload length")
assert(
    harness.HashSnapshot(payload) == 1141367375,
    "sanitization reuse changed the APS1 payload bytes"
)

local originalUnitFullName = UnitFullName
UnitFullName = function(unit)
    if unit == "raid1" then
        return "|cffff0000Raidmember01|r", "DefiasBrotherhood"
    end
    return originalUnitFullName(unit)
end
C_LFGList.GetApplicantMemberInfo = function(id, memberIndex)
    if memberIndex ~= 1 then return nil end
    local name = string.format("Applicant%02d-Realm", id)
    if id == 1 then name = "|cffff0000Applicant01|r-Realm" end
    return name, "MAGE", nil, nil, 700, nil, nil, nil, nil,
        "DAMAGER", nil, 2500, nil, nil, nil, 63
end
local escapedPayload = assert(harness.BuildPayload)({
    activityIDs = { 401 },
    questID = 0,
    name = "|cffff0000Applicants 40|r",
    comment = "stable|nline",
}, applicantIDs, false)

assert(
    escapedPayload:find("Applicant01-Realm", 1, true),
    "raw applicant name was not sanitized at the API boundary"
)
assert(
    escapedPayload:find("Raidmember01-DefiasBrotherhood", 1, true),
    "raw roster name was not sanitized at the API boundary"
)
assert(
    escapedPayload:find("Applicants 40", 1, true),
    "raw listing name was not sanitized at the API boundary"
)
assert(
    escapedPayload:find("stable line", 1, true),
    "raw listing comment was not sanitized at the API boundary"
)

print(string.format(
    "ok transport-string-sanitization gsubs=%d bytes=%d hash=%u",
    gsubCount,
    #payload,
    harness.HashSnapshot(payload)
))
