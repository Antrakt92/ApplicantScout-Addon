local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local fail = env.fail

IsInRaid = function() return false end
GetNumGroupMembers = function() return 5 end

-- Player-name API behavior: "healthy", "error", or "secret". party1 always
-- reports a bare name (realm unknown), which forces the player-realm fallback
-- branch of the RaiderIO lookup on the snapshot hot path.
local playerNameMode = "healthy"
local secretToken = {}

local originalIsSecretValue = issecretvalue
issecretvalue = function(value)
    if value == secretToken then return true end
    return originalIsSecretValue(value)
end

local originalUnitFullName = UnitFullName
UnitFullName = function(unit)
    if unit == "party1" then return "Friend", nil end
    if unit == "player" then
        if playerNameMode == "error" then error("name unreadable") end
        if playerNameMode == "secret" then return secretToken, secretToken end
    end
    return originalUnitFullName(unit)
end
local originalGetUnitName = GetUnitName
GetUnitName = function(unit, showRealm)
    if unit == "party1" then return "Friend" end
    if unit == "player" and playerNameMode ~= "healthy" then
        if playerNameMode == "error" then error("name unreadable") end
        return secretToken
    end
    return originalGetUnitName(unit, showRealm)
end

local harness = env.load_addon()
if type(harness.GetRaiderIOMPlusSummaryForCleanName) ~= "function" then
    fail("missing RaiderIO summary fixture hook")
end
if type(harness.BuildPayload) ~= "function" then
    fail("missing BuildPayload fixture hook")
end

-- Direct summary lookup: a qualified name resolves on the clean path, a bare
-- name stays empty, and neither a failing nor a secret player-name API may
-- propagate out of the lookup.
playerNameMode = "healthy"
local summary = harness.GetRaiderIOMPlusSummaryForCleanName("Tankone-Realm", 401, 15)
if type(summary) ~= "table" or summary.hasProfile ~= true then
    fail("clean summary lookup did not resolve the qualified applicant name")
end
local bare = harness.GetRaiderIOMPlusSummaryForCleanName("Tankone", 401, 15)
if type(bare) ~= "table" or bare.hasProfile == true then
    fail("bare applicant name attributed a profile without realm evidence")
end
for _, mode in ipairs({ "error", "secret" }) do
    playerNameMode = mode
    local ok, result = pcall(harness.GetRaiderIOMPlusSummaryForCleanName, "Tankone-Realm", 401, 15)
    if not ok then
        fail(mode .. " player name propagated out of the summary lookup: " .. tostring(result))
    end
    if type(result) ~= "table" then fail(mode .. " summary lookup returned no table") end
end

-- Full snapshot hot path: a bare roster name plus an unreadable player name
-- must build without raising, deterministically, with identical fail-closed
-- bytes for failing and secret APIs.
local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "Name safety fixture",
    comment = "version block must survive unreadable player names",
}

playerNameMode = "healthy"
local okHealthy, healthyPayload = pcall(harness.BuildPayload, entry, {}, false)
if not okHealthy then fail("clean snapshot raised: " .. tostring(healthyPayload)) end
if type(healthyPayload) ~= "string" or #healthyPayload == 0 then
    fail("clean snapshot emitted an empty payload")
end

local degraded = {}
for _, mode in ipairs({ "error", "secret" }) do
    playerNameMode = mode
    local okPayload, payload = pcall(harness.BuildPayload, entry, {}, false)
    if not okPayload then
        fail(mode .. " player name propagated into the snapshot: " .. tostring(payload))
    end
    if type(payload) ~= "string" or #payload == 0 then
        fail(mode .. " player name emitted an empty snapshot")
    end
    local okRepeat, repeatPayload = pcall(harness.BuildPayload, entry, {}, false)
    if not okRepeat or repeatPayload ~= payload then
        fail(mode .. " player name made the snapshot nondeterministic")
    end
    degraded[mode] = payload
end
if degraded.error ~= degraded.secret then
    fail("failing and secret player names produced different snapshot bytes")
end

print("ok transport-name-secret-safety")
