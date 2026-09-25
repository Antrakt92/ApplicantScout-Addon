local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

_G.UNKNOWN = "Unknown"
_G.UNKNOWNOBJECT = "Unknown Object"

env.install_raid_roster(40)
env.install_single_applicant()

local harness = env.load_addon({})
local applicantIDs = {}
for id = 1, 40 do applicantIDs[id] = id end

local originalGsub = string.gsub
local gsubCount = 0
string.gsub = function(...)
    gsubCount = gsubCount + 1
    return originalGsub(...)
end

local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "+40 Applicant",
    comment = "stable",
}
local payload = assert(harness.BuildPayload)(entry, applicantIDs, false)
local firstBuildGsubs = gsubCount

env.start_session_quietly(harness)
gsubCount = 0
local repeatedPayload = assert(harness.BuildPayload)(entry, applicantIDs, false)
local repeatedBuildGsubs = gsubCount
string.gsub = originalGsub

assert(firstBuildGsubs <= 4000, string.format(
    "placeholder labels were sanitized per row on first build: %d gsubs",
    firstBuildGsubs
))
assert(repeatedBuildGsubs <= 3952, string.format(
    "placeholder label cache did not survive session reset: %d gsubs",
    repeatedBuildGsubs
))
assert(payload == repeatedPayload, "session reset changed stable payload bytes")
assert(#payload == 3817, "placeholder label reuse changed APS1 payload length")
assert(
    harness.HashSnapshot(payload) == 42405359,
    "placeholder label reuse changed APS1 payload bytes"
)

env.install_single_applicant({ names = {
    [101] = "Unknown-Realm",
    [102] = "Unknown Object-Realm",
    [103] = "UNKNOWNOBJECT-Realm",
    [104] = "Visible-Realm",
} })
local placeholderPayload = assert(harness.BuildPayload)(
    entry,
    { 101, 102, 103, 104 },
    false
)
assert(not placeholderPayload:find("Unknown-Realm", 1, true))
assert(not placeholderPayload:find("Unknown Object-Realm", 1, true))
assert(not placeholderPayload:find("UNKNOWNOBJECT-Realm", 1, true))
assert(not placeholderPayload:find("Visible-Realm", 1, true))

print(string.format(
    "ok placeholder-label-reuse first=%d repeated=%d bytes=%d hash=%u",
    firstBuildGsubs,
    repeatedBuildGsubs,
    #payload,
    harness.HashSnapshot(payload)
))
