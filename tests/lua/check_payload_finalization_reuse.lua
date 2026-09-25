local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

env.install_raid_roster(40)
env.install_single_applicant()

local harness = env.load_addon({})
local applicantIDs = {}
for id = 1, 40 do applicantIDs[id] = id end

local originalByte = string.byte
local originalSub = string.sub
local byteCalls = 0
local maxSubstringBytes = 0
string.byte = function(...)
    byteCalls = byteCalls + 1
    return originalByte(...)
end
string.sub = function(...)
    local value = originalSub(...)
    maxSubstringBytes = math.max(maxSubstringBytes, #value)
    return value
end
local payload, builtHash = harness.BuildPayload({
    activityIDs = { 401 },
    questID = 0,
    name = "+40 Applicant",
    comment = "stable",
}, applicantIDs, false)
string.byte = originalByte
string.sub = originalSub

assert(
    builtHash ~= nil
        and byteCalls == #payload
        and maxSubstringBytes <= 255,
    string.format(
        "payload finalization duplicated work hash=%s byte_calls=%d bytes=%d max_sub=%d",
        tostring(builtHash),
        byteCalls,
        #payload,
        maxSubstringBytes
    )
)
assert(#payload == 3817, "payload finalization changed APS1 length")
assert(builtHash == 42405359, "payload finalization changed APS1 hash")
assert(
    builtHash == harness.HashSnapshot(payload),
    "fused payload hash disagrees with independent oracle"
)

print(string.format(
    "ok payload-finalization byte_calls=%d bytes=%d max_sub=%d hash=%u",
    byteCalls,
    #payload,
    maxSubstringBytes,
    builtHash
))
