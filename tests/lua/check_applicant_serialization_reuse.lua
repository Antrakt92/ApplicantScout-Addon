local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

GetNumGroupMembers = function() return 0 end
IsInRaid = function() return false end
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

local originalInsert = table.insert
local insertCount = 0
table.insert = function(...)
    insertCount = insertCount + 1
    return originalInsert(...)
end

local payload = assert(harness.BuildPayload)({
    activityIDs = { 401 },
    questID = 0,
    name = "Applicants 40",
    comment = "stable",
}, applicantIDs, false)
table.insert = originalInsert

assert(insertCount == 800, string.format(
    "applicant payload used %d table inserts instead of one final member block",
    insertCount
))
assert(#payload == 1737, "applicant block reuse changed the APS1 payload length")
assert(
    harness.HashSnapshot(payload) == 654822407,
    "applicant block reuse changed the APS1 payload bytes"
)

print(string.format(
    "ok applicant-serialization-reuse rows=40 inserts=%d bytes=%d hash=%u",
    insertCount,
    #payload,
    harness.HashSnapshot(payload)
))
