local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local fail = env.fail
local assert_equal = env.assert_equal

LE_PARTY_CATEGORY_HOME = 1
LE_PARTY_CATEGORY_INSTANCE = 2

-- Group/raid API behavior switches. Each of "true", "false", "nil",
-- "secret", "error" drives the matching stub below.
local homeBehavior = "true"
local instanceBehavior = "false"
local raidBehavior = "false"
local groupBehavior = "true"
local secretToken = {}
local sends = {}
local timers = {}
local lockdown = false

local originalIsSecretValue = issecretvalue
issecretvalue = function(value)
    if value == secretToken then return true end
    return originalIsSecretValue(value)
end

local function resolveBehavior(behavior)
    if behavior == "secret" then return secretToken end
    if behavior == "error" then error("group API unreadable") end
    if behavior == "nil" then return nil end
    if behavior == "true" then return true end
    return false
end

IsInGroup = function(category)
    if category == LE_PARTY_CATEGORY_HOME then return resolveBehavior(homeBehavior) end
    if category == LE_PARTY_CATEGORY_INSTANCE then return resolveBehavior(instanceBehavior) end
    return resolveBehavior(groupBehavior)
end
IsInRaid = function() return resolveBehavior(raidBehavior) end

C_Timer.After = function(_delay, callback)
    timers[#timers + 1] = callback
end

C_ChatInfo = {
    InChatMessagingLockdown = function() return lockdown end,
    RegisterAddonMessagePrefix = function() return 0 end,
    SendAddonMessage = function(prefix, payload, channel)
        sends[#sends + 1] = { prefix = prefix, payload = payload, channel = channel }
        return 0
    end,
}

ApplicantScoutDB = { enabled = true, debug = false }

local harness = env.load_addon()
if type(harness.AutoHiChatChannel) ~= "function" then
    fail("missing AutoHiChatChannel fixture hook")
end

local function channel()
    local ok, result = pcall(harness.AutoHiChatChannel)
    if not ok then fail("AutoHiChatChannel propagated a group API failure: " .. tostring(result)) end
    return result
end

-- Clean paths keep their documented channels.
homeBehavior, instanceBehavior, raidBehavior = "true", "false", "false"
assert_equal("home party channel", channel(), "PARTY")
homeBehavior, instanceBehavior, raidBehavior = "false", "true", "false"
assert_equal("instance group channel", channel(), "INSTANCE_CHAT")
homeBehavior, instanceBehavior, raidBehavior = "true", "false", "true"
assert_equal("raid channel", channel(), "RAID")

-- Secret or failing group APIs fail closed to PARTY without raising.
homeBehavior, instanceBehavior, raidBehavior = "secret", "false", "false"
assert_equal("secret home group channel", channel(), "PARTY")
homeBehavior, instanceBehavior, raidBehavior = "error", "error", "error"
assert_equal("failing group channel", channel(), "PARTY")
homeBehavior, instanceBehavior, raidBehavior = "true", "false", "secret"
assert_equal("secret raid channel", channel(), "PARTY")

-- A missing group API also fails closed to PARTY.
local savedIsInGroup = IsInGroup
IsInGroup = nil
assert_equal("missing group API channel", channel(), "PARTY")
IsInGroup = savedIsInGroup

-- Grouped sends: unknown state refuses with a retryable reason and no bytes.
groupBehavior = "nil"
sends = {}
local ok, reason = harness.SendLibKeystoneAddonMessage("R", "PARTY")
assert_equal("unknown group send ok", ok, false)
assert_equal("unknown group send reason", reason, "request-failed")
assert_equal("unknown group sends", #sends, 0)

groupBehavior = "false"
sends = {}
ok, reason = harness.SendLibKeystoneAddonMessage("R", "PARTY")
assert_equal("ungrouped send ok", ok, false)
assert_equal("ungrouped send reason", reason, "not-grouped")
assert_equal("ungrouped sends", #sends, 0)

groupBehavior = "true"
sends = {}
ok, reason = harness.SendLibKeystoneAddonMessage("R", "PARTY")
assert_equal("grouped send ok", ok, true)
assert_equal("grouped sends", #sends, 1)

groupBehavior = "error"
sends = {}
ok = pcall(harness.SendLibKeystoneAddonMessage, "R", "PARTY")
if not ok then fail("grouped send propagated a group API failure") end
assert_equal("failing group sends", #sends, 0)

-- Leader data on a tainted stack: unknown group refuses without raising.
groupBehavior = "secret"
sends = {}
local onDataOK, onDataError = pcall(harness.OnLeaderKeystoneData, 18, 504, 0, "Host-Realm", "PARTY")
if not onDataOK then fail("leader data propagated a group API failure: " .. tostring(onDataError)) end
assert_equal("secret group leader sends", #sends, 0)
if harness.ResolveLeaderKeystoneContext() ~= nil then
    fail("secret group state cached leader keystone data")
end

-- Retry scheduling: the existing C_Timer path stays armed for clean grouped
-- state and stays quiet when group state is unknown.
groupBehavior = "true"
lockdown = true
timers = {}
sends = {}
harness.LibKeystoneShimHandleAddonMessage("LibKS", "R", "PARTY", "Someone-Realm")
assert_equal("locked grouped retry timers", #timers, 1)
assert_equal("locked grouped retry sends", #sends, 0)

groupBehavior = "nil"
lockdown = false
timers = {}
sends = {}
harness.LibKeystoneShimHandleAddonMessage("LibKS", "R", "PARTY", "Someone-Realm")
assert_equal("unknown group retry timers", #timers, 0)
assert_equal("unknown group retry sends", #sends, 0)

groupBehavior = "true"
lockdown = false
timers = {}
sends = {}
harness.LibKeystoneShimHandleAddonMessage("LibKS", "R", "PARTY", "Someone-Realm")
assert_equal("clean grouped response sends", #sends, 1)
assert_equal("clean grouped response timers", #timers, 0)

print("ok group-api-secret-safety")
