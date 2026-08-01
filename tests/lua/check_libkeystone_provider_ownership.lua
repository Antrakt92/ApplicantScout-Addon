local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local fail = env.fail
local assert_equal = env.assert_equal

local timers = {}
local sends = {}
local owned_key_reads = 0
local rating_reads = 0
local lockdown = false
local external_registers = 0
local external_callback = nil

local function reset_observed()
    sends = {}
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
    return true
end

C_ChatInfo = {
    InChatMessagingLockdown = function()
        return lockdown
    end,
    RegisterAddonMessagePrefix = function()
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

local external_lib = {
    Register = function(_owner, callback)
        external_registers = external_registers + 1
        external_callback = callback
    end,
    Request = function() end,
}

LibStub = function(name, silent)
    assert_equal("external library name", name, "LibKeystone")
    assert_equal("external library silent lookup", silent, true)
    return external_lib
end

ApplicantScoutDB = { enabled = true, debug = false }
local external_harness = env.load_addon()

reset_observed()
reset_timers()
external_harness.FireEvent("CHAT_MSG_ADDON", "LibKS", "R", "PARTY", "Friend-Realm")
assert_equal("external pre-registration response sends", #sends, 0)
assert_equal("external pre-registration response timers", #timers, 0)
assert_equal("external pre-registration owned-key reads", owned_key_reads, 0)
assert_equal("external pre-registration rating reads", rating_reads, 0)

external_harness.RequestLeaderKeystone(true)
assert_equal("external callback registrations", external_registers, 1)
assert_equal("external checked request count", #sends, 1)
assert_equal("external checked request payload", sends[1].payload, "R")
assert_equal("external checked request channel", sends[1].channel, "PARTY")
assert_equal("external request own-key reads", owned_key_reads, 2)
assert_equal("external request rating reads", rating_reads, 1)
local external_local_key = external_harness.ResolveLeaderKeystoneContext()
if not external_local_key then fail("external request lost local leader key") end
assert_equal("external local leader key level", external_local_key.level, 17)
assert_equal("external local leader key map", external_local_key.challengeMapID, 503)
if type(external_callback) ~= "function" then
    fail("external provider callback was not registered")
end

reset_observed()
reset_timers()
external_harness.FireEvent("CHAT_MSG_ADDON", "LibKS", "R", "PARTY", "Friend-Realm")
assert_equal("external responder sends", #sends, 0)
assert_equal("external responder timers", #timers, 0)
assert_equal("external responder owned-key reads", owned_key_reads, 0)
assert_equal("external responder rating reads", rating_reads, 0)

lockdown = true
external_harness.FireEvent("CHAT_MSG_ADDON", "LibKS", "R", "PARTY", "Friend-Realm")
assert_equal("external lockdown response sends", #sends, 0)
assert_equal("external lockdown response timers", #timers, 0)
assert_equal("external lockdown owned-key reads", owned_key_reads, 0)
assert_equal("external lockdown rating reads", rating_reads, 0)

lockdown = false
external_callback(18, 504, 2999, "Host-Realm", "PARTY")
local external_key = external_harness.ResolveLeaderKeystoneContext()
if not external_key then fail("external provider callback did not update leader key") end
assert_equal("external provider callback level", external_key.level, 18)
assert_equal("external provider callback map", external_key.challengeMapID, 504)

LibStub = nil
ApplicantScoutDB = { enabled = true, debug = false }
lockdown = false
reset_observed()
reset_timers()
local shim_harness = env.load_addon()

shim_harness.RequestLeaderKeystone(true)
assert_equal("shim checked request count", #sends, 1)
assert_equal("shim checked request payload", sends[1].payload, "R")
assert_equal("shim request own-key reads", owned_key_reads, 2)
assert_equal("shim request rating reads", rating_reads, 1)
local shim_local_key = shim_harness.ResolveLeaderKeystoneContext()
if not shim_local_key then fail("shim request lost local leader key") end
assert_equal("shim local leader key level", shim_local_key.level, 17)
assert_equal("shim local leader key map", shim_local_key.challengeMapID, 503)

reset_observed()
reset_timers()
shim_harness.FireEvent("CHAT_MSG_ADDON", "LibKS", "R", "PARTY", "Friend-Realm")
assert_equal("shim response count", #sends, 1)
assert_equal("shim response payload", sends[1].payload, "17,503,3333")
assert_equal("shim response owned-key reads", owned_key_reads, 2)
assert_equal("shim response rating reads", rating_reads, 1)

lockdown = true
reset_observed()
reset_timers()
shim_harness.FireEvent("CHAT_MSG_ADDON", "LibKS", "R", "PARTY", "Friend-Realm")
assert_equal("shim lockdown immediate sends", #sends, 0)
assert_equal("shim lockdown response retries", #timers, 1)

lockdown = false
reset_observed()
drain_timers()
assert_equal("shim unlocked retry sends", #sends, 1)
assert_equal("shim unlocked retry payload", sends[1].payload, "17,503,3333")

lockdown = true
reset_observed()
reset_timers()
shim_harness.FireEvent("CHAT_MSG_ADDON", "LibKS", "R", "PARTY", "Friend-Realm")
assert_equal("late-provider pending shim sends", #sends, 0)
assert_equal("late-provider pending shim retry", #timers, 1)

external_registers = 0
external_callback = nil
LibStub = function(name, silent)
    assert_equal("late external library name", name, "LibKeystone")
    assert_equal("late external library silent lookup", silent, true)
    return external_lib
end
lockdown = false
shim_harness.FireEvent("ADDON_LOADED", "LateLibKeystone")
assert_equal("late external callback registrations", external_registers, 1)
if type(external_callback) ~= "function" then
    fail("late external provider callback was not registered")
end
shim_harness.FireEvent("ADDON_LOADED", "AnotherLateAddon")
assert_equal("stable late external callback registrations", external_registers, 1)

reset_observed()
drain_timers()
assert_equal("retired shim retry sends", #sends, 0)
assert_equal("retired shim retry owned-key reads", owned_key_reads, 0)
assert_equal("retired shim retry rating reads", rating_reads, 0)

shim_harness.FireEvent("CHAT_MSG_ADDON", "LibKS", "R", "PARTY", "Friend-Realm")
assert_equal("late external responder sends", #sends, 0)
assert_equal("late external responder owned-key reads", owned_key_reads, 0)
assert_equal("late external responder rating reads", rating_reads, 0)

external_callback(18, 504, 2999, "Host-Realm", "PARTY")
local late_external_key = shim_harness.ResolveLeaderKeystoneContext()
if not late_external_key then fail("late external callback did not update leader key") end
assert_equal("late external callback level", late_external_key.level, 18)
assert_equal("late external callback map", late_external_key.challengeMapID, 504)

shim_harness.FireEvent("CHAT_MSG_ADDON", "LibKS", "19,505,3000", "PARTY", "Host-Realm")
late_external_key = shim_harness.ResolveLeaderKeystoneContext()
if not late_external_key then fail("late external key disappeared after shim data") end
assert_equal("retired shim callback level", late_external_key.level, 18)
assert_equal("retired shim callback map", late_external_key.challengeMapID, 504)

ApplicantScoutDB.enabled = false
reset_observed()
reset_timers()
shim_harness.FireEvent("CHAT_MSG_ADDON", "LibKS", "R", "PARTY", "Friend-Realm")
assert_equal("disabled shim response sends", #sends, 0)
assert_equal("disabled shim response timers", #timers, 0)
assert_equal("disabled shim owned-key reads", owned_key_reads, 0)
assert_equal("disabled shim rating reads", rating_reads, 0)

print("ok libkeystone-provider-ownership")
