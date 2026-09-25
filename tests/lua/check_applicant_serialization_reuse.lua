local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

GetNumGroupMembers = function() return 0 end
IsInRaid = function() return false end
env.install_single_applicant()

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
    name = "+40 Applicant",
    comment = "stable",
}, applicantIDs, false)
table.insert = originalInsert

assert(insertCount == 760, string.format(
    "applicant payload used %d table inserts instead of one final member block",
    insertCount
))
assert(#payload == 1737, "applicant block reuse changed the APS1 payload length")
assert(
    harness.HashSnapshot(payload) == 1931730799,
    "applicant block reuse changed the APS1 payload bytes"
)

print(string.format(
    "ok applicant-serialization-reuse rows=40 inserts=%d bytes=%d hash=%u",
    insertCount,
    #payload,
    harness.HashSnapshot(payload)
))
