local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local grouped = true
local lockdown = false
local leaderMode = "player"
local secretValue = {}
local secretName = false
local sends = {}

IsInGroup = function() return grouped end
InCombatLockdown = function() return lockdown end

local originalIsSecretValue = issecretvalue
issecretvalue = function(value)
    if value == secretValue then return true end
    return originalIsSecretValue(value)
end

UnitIsGroupLeader = function(unit)
    if leaderMode == "secret" and unit == "player" then return secretValue end
    if leaderMode == "error" and unit == "player" then error("leader unreadable") end
    if leaderMode == "party1" then return unit == "party1" end
    return unit == "player"
end

local originalUnitFullName = UnitFullName
UnitFullName = function(unit)
    if secretName and unit == "player" then return secretValue, secretValue end
    return originalUnitFullName(unit)
end
local originalGetUnitName = GetUnitName
GetUnitName = function(unit, ...)
    if secretName and unit == "player" then return secretValue end
    return originalGetUnitName(unit, ...)
end

C_ChatInfo = {
    InChatMessagingLockdown = function() return false end,
    RegisterAddonMessagePrefix = function() return 0 end,
    SendAddonMessage = function(prefix, payload, channel)
        sends[#sends + 1] = { prefix = prefix, payload = payload, channel = channel }
        return 0
    end,
}
ApplicantScoutDB = { enabled = true, debug = false }

local harness = env.load_addon()

local function assertKey(level, mapID, label)
    local key = harness.ResolveLeaderKeystoneContext()
    assert(key, label .. ": cached leader key was lost")
    assert(key.level == level, label .. ": wrong key level")
    assert(key.challengeMapID == mapID, label .. ": wrong challenge map")
end

harness.OnLeaderKeystoneData(18, 504, 0, "Host-Realm", "PARTY")
assertKey(18, 504, "initial")

lockdown = true
leaderMode = "secret"
for _ = 1, 3 do assertKey(18, 504, "secret leader decision") end
leaderMode = "error"
assertKey(18, 504, "failed leader decision")
leaderMode = "player"
secretName = true
assertKey(18, 504, "secret leader name")
assert(#sends == 0, "combat identity uncertainty sent an immediate request")
assert(harness.LeaderKeystoneRecoveryState().combatDeferred,
    "combat identity uncertainty did not arm post-combat recovery")

lockdown = false
secretName = false
harness.FireEvent("PLAYER_REGEN_ENABLED")
assert(#sends == 1 and sends[1].payload == "R" and sends[1].channel == "PARTY",
    string.format("post-combat identity recovery sent %d PARTY requests", #sends))
harness.FireEvent("PLAYER_REGEN_ENABLED")
assert(#sends == 1, "post-combat identity recovery was not bounded")
assertKey(18, 504, "post-combat recovery")

leaderMode = "party1"
assert(harness.ResolveLeaderKeystoneContext() == nil,
    "clean leader mismatch retained old key context")
leaderMode = "player"
assert(harness.ResolveLeaderKeystoneContext() == nil,
    "clean leader mismatch did not clear old key context")

harness.OnLeaderKeystoneData(19, 505, 0, "Host-Realm", "PARTY")
assertKey(19, 505, "before group exit")
grouped = false
assert(harness.ResolveLeaderKeystoneContext() == nil,
    "clean group exit retained old key context")
grouped = true
assert(harness.ResolveLeaderKeystoneContext() == nil,
    "clean group exit did not clear old key context")

print("leader-keystone-identity-recovery-ok")
