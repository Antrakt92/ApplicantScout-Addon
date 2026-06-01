local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local function fail(message)
    io.stderr:write(message .. "\n")
    os.exit(1)
end

local function assert_equal(name, actual, expected)
    if actual ~= expected then
        fail(name .. " expected " .. tostring(expected)
             .. " (" .. type(expected) .. ") but got "
             .. tostring(actual) .. " (" .. type(actual) .. ")")
    end
end

local function assert_nil(name, actual)
    if actual ~= nil then
        fail(name .. " expected nil but got " .. tostring(actual))
    end
end

local timers = {}
local sends = {}
local registered_prefixes = {}
local owned_key_reads = 0
local rating_reads = 0
local lockdown = false
local grouped = true

local function reset_observed()
    sends = {}
    registered_prefixes = {}
    owned_key_reads = 0
    rating_reads = 0
end

local function reset_timers()
    timers = {}
end

local function drain_timers()
    local guard = 0
    while #timers > 0 do
        guard = guard + 1
        if guard > 20 then fail("timer queue did not drain") end
        local callback = table.remove(timers, 1)
        callback()
    end
end

C_Timer.After = function(_delay, callback)
    table.insert(timers, callback)
end

IsInGroup = function()
    return grouped
end

UnitNameUnmodified = function(unit)
    if unit == "player" then return "Host" end
    return ""
end

Ambiguate = function(sender, _mode)
    return sender
end

C_ChatInfo = {
    InChatMessagingLockdown = function()
        return lockdown
    end,
    RegisterAddonMessagePrefix = function(prefix)
        table.insert(registered_prefixes, prefix)
        return 0
    end,
    SendAddonMessage = function(prefix, payload, channel)
        table.insert(sends, { prefix = prefix, payload = payload, channel = channel })
        return 0
    end,
}

C_MythicPlus = {
    GetOwnedKeystoneLevel = function()
        owned_key_reads = owned_key_reads + 1
        return 17
    end,
    GetOwnedKeystoneChallengeMapID = function()
        owned_key_reads = owned_key_reads + 1
        return 503
    end,
}

C_PlayerInfo = {
    GetPlayerMythicPlusRatingSummary = function()
        rating_reads = rating_reads + 1
        return { currentSeasonScore = 3333 }
    end,
}

ApplicantScoutDB = {
    enabled = false,
    debug = false,
}

local harness = env.load_addon()

local required_exports = {
    "SendLibKeystoneAddonMessage",
    "RequestLeaderKeystone",
    "GetLibKeystoneShim",
    "LibKeystoneShimHandleAddonMessage",
    "ScheduleLibKeystoneResponseRetry",
    "ScheduleLeaderKeystoneRequestRetry",
    "ResolveLeaderKeystoneContext",
}
for _, name in ipairs(required_exports) do
    if type(harness[name]) ~= "function" then
        fail("missing fixture harness export: " .. name)
    end
end

reset_observed()
local ok, reason = harness.SendLibKeystoneAddonMessage("R", "PARTY")
assert_equal("disabled direct send ok", ok, false)
assert_equal("disabled direct send reason", reason, "disabled")
assert_equal("disabled direct send count", #sends, 0)
assert_equal("disabled direct prefix count", #registered_prefixes, 0)

reset_observed()
harness.RequestLeaderKeystone(true)
assert_equal("disabled request sends", #sends, 0)
assert_equal("disabled request prefix count", #registered_prefixes, 0)

ApplicantScoutDB.enabled = true
reset_observed()
local shim = harness.GetLibKeystoneShim()
if type(shim) ~= "table" then fail("missing LibKeystone shim") end
local shim_callback_count = 0
shim.Register({}, function()
    shim_callback_count = shim_callback_count + 1
end)
reset_observed()
ApplicantScoutDB.enabled = false
shim.Request("PARTY")
assert_equal("disabled shim request callbacks", shim_callback_count, 0)
assert_equal("disabled shim request sends", #sends, 0)
assert_equal("disabled shim request owned reads", owned_key_reads, 0)
assert_equal("disabled shim request rating reads", rating_reads, 0)

ApplicantScoutDB.enabled = false
harness.OnLeaderKeystoneData(18, 504, 2999, "Host-Realm", "PARTY")
assert_nil("disabled direct LibKeystone callback leader key", harness.ResolveLeaderKeystoneContext())

ApplicantScoutDB.enabled = true
harness.OnLeaderKeystoneData(0, 0, 0, "Host-Realm", "PARTY")
local leader_callback_owner = {}
shim.Register(leader_callback_owner, harness.OnLeaderKeystoneData)
ApplicantScoutDB.enabled = false
reset_observed()
harness.LibKeystoneShimHandleAddonMessage("LibKS", "18,504,2999", "PARTY", "Host-Realm")
assert_nil("disabled inbound data leader key", harness.ResolveLeaderKeystoneContext())
assert_equal("disabled inbound data sends", #sends, 0)

lockdown = true
ApplicantScoutDB.enabled = false
reset_timers()
reset_observed()
harness.LibKeystoneShimHandleAddonMessage("LibKS", "R", "PARTY", "Host-Realm")
assert_equal("disabled inbound request timers", #timers, 0)
assert_equal("disabled inbound request sends", #sends, 0)
assert_equal("disabled inbound request owned reads", owned_key_reads, 0)
assert_equal("disabled inbound request rating reads", rating_reads, 0)

ApplicantScoutDB.enabled = true
lockdown = true
reset_timers()
reset_observed()
harness.LibKeystoneShimHandleAddonMessage("LibKS", "R", "PARTY", "Host-Realm")
assert_equal("enabled locked inbound schedules response retry", #timers, 1)
reset_observed()
ApplicantScoutDB.enabled = false
lockdown = false
drain_timers()
assert_equal("disabled response retry sends", #sends, 0)
assert_equal("disabled response retry owned reads", owned_key_reads, 0)
assert_equal("disabled response retry rating reads", rating_reads, 0)

ApplicantScoutDB.enabled = true
lockdown = true
reset_timers()
reset_observed()
harness.RequestLeaderKeystone(true)
assert_equal("enabled locked leader request schedules retry", #timers, 1)
reset_observed()
ApplicantScoutDB.enabled = false
lockdown = false
drain_timers()
assert_equal("disabled leader request retry sends", #sends, 0)

print("ok libkeystone-disabled")
