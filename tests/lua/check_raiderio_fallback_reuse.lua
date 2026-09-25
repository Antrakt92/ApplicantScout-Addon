local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

GetNumGroupMembers = function() return 0 end
IsInRaid = function() return false end

env.install_single_applicant({ name_format = "Missing%02d-Realm" })

local originalRaiderIO = RaiderIO
local nilCalls = 0
RaiderIO = {
    GetProfile = function(_name)
        nilCalls = nilCalls + 1
        return nil
    end,
}

local harness = env.load_addon({})
local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "+40 Applicant",
    comment = "stable",
}
local applicantIDs = {}
for id = 1, 40 do applicantIDs[id] = id end

local firstPayload = assert(harness.BuildPayload(entry, applicantIDs, false))
local secondPayload = assert(harness.BuildPayload(entry, applicantIDs, false))
assert(firstPayload == secondPayload, "zero-summary reuse changed stable payload bytes")
assert(#firstPayload == 1657, "zero-summary reuse changed payload length")
assert(
    harness.HashSnapshot(firstPayload) == 1044733645,
    "zero-summary reuse changed payload hash"
)
assert(nilCalls == 80, string.format(
    "RaiderIO nil misses stopped retrying calls=%d bytes=%d hash=%u",
    nilCalls,
    #firstPayload,
    harness.HashSnapshot(firstPayload)
))
local emptySummary = harness.GetRaiderIOMPlusSummaryForCleanName("", 401, 15)
assert(
    emptySummary == harness.GetRaiderIOMPlusSummaryForCleanName("?", 401, 15),
    "invalid names did not reuse the shared zero summary"
)

local nilThenValidCalls = 0
RaiderIO = {
    GetProfile = function(name)
        nilThenValidCalls = nilThenValidCalls + 1
        if nilThenValidCalls == 1 then return nil end
        return originalRaiderIO.GetProfile(name)
    end,
}
local nilSummary = harness.GetRaiderIOMPlusSummaryForCleanName("Tankone-Realm", 401, 15)
local validAfterNil = harness.GetRaiderIOMPlusSummaryForCleanName(
    "Tankone-Realm",
    401,
    15
)
assert(nilSummary == emptySummary, "nil lookup did not reuse zero summary")
assert(validAfterNil.hasProfile, "nil-first RaiderIO lookup did not recover")
harness.GetRaiderIOMPlusSummaryForCleanName("Tankone-Realm", 401, 15)
assert(nilThenValidCalls == 2, "valid RaiderIO profile was not positively cached")
env.start_session_quietly(harness)
harness.GetRaiderIOMPlusSummaryForCleanName("Tankone-Realm", 401, 15)
assert(nilThenValidCalls == 3, "session start did not reset RaiderIO profile cache")

local errorThenValidCalls = 0
RaiderIO = {
    GetProfile = function(name)
        errorThenValidCalls = errorThenValidCalls + 1
        if errorThenValidCalls == 1 then error("fixture RaiderIO failure") end
        return originalRaiderIO.GetProfile(name)
    end,
}
local errorSummary = harness.GetRaiderIOMPlusSummaryForCleanName("Mageone-Realm", 401, 15)
local validAfterError = harness.GetRaiderIOMPlusSummaryForCleanName(
    "Mageone-Realm",
    401,
    15
)
assert(errorSummary == emptySummary, "throwing lookup did not reuse zero summary")
assert(validAfterError.hasProfile, "error-first RaiderIO lookup did not recover")
assert(errorThenValidCalls == 2, "throwing RaiderIO lookup was not retried")

RaiderIO = nil
local noApiSummary = harness.GetRaiderIOMPlusSummaryForCleanName("Host-Realm", 401, 15)
local lateCalls = 0
RaiderIO = {
    GetProfile = function(name)
        lateCalls = lateCalls + 1
        return originalRaiderIO.GetProfile(name)
    end,
}
local recoveredSummary = harness.GetRaiderIOMPlusSummaryForCleanName("Host-Realm", 401, 15)
assert(lateCalls == 1, "late RaiderIO API availability stayed negatively cached")
assert(noApiSummary == emptySummary, "absent API did not reuse zero summary")
assert(recoveredSummary.hasProfile, "late RaiderIO profile did not recover")

print(string.format(
    "ok raiderio-fallback-reuse calls=%d bytes=%d hash=%u",
    nilCalls,
    #firstPayload,
    harness.HashSnapshot(firstPayload)
))
