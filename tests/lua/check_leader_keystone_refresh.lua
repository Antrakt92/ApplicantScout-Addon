local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local now = 1000
local grouped = true
local timers = {}
local sends = {}

GetTime = function() return now end
IsInGroup = function() return grouped end
C_Timer.After = function(_delay, callback)
    timers[#timers + 1] = callback
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

local function DrainTimers()
    local guard = 0
    while #timers > 0 do
        guard = guard + 1
        assert(guard < 100, "leader-key timer queue did not settle")
        local callback = table.remove(timers, 1)
        callback()
    end
end

local function AssertKey(level, mapID)
    local key = harness.ResolveLeaderKeystoneContext()
    assert(key and key.level == level and key.challengeMapID == mapID,
        "leader-key response did not refresh cached context")
end

harness.OnLeaderKeystoneData(18, 504, 0, "Host-Realm", "PARTY")
AssertKey(18, 504)

now = 1061
assert(harness.ResolveLeaderKeystoneContext() == nil, "expired leader key remained visible")
assert(#timers == 1, "expiry did not schedule one leader-key refresh")
assert(harness.ResolveLeaderKeystoneContext() == nil, "cleared leader key unexpectedly returned")
assert(#timers == 1, "repeated expiry resolution scheduled duplicate refreshes")
DrainTimers()
assert(#sends == 1 and sends[1].payload == "R" and sends[1].channel == "PARTY",
    "scheduled refresh did not send one throttled PARTY request")

harness.OnLeaderKeystoneData(19, 505, 0, "Host-Realm", "PARTY")
AssertKey(19, 505)

now = 1122
assert(harness.ResolveLeaderKeystoneContext() == nil, "second expired leader key remained visible")
assert(#timers == 1, "second expiry did not schedule refresh")
harness.OnLeaderKeystoneData(20, 506, 0, "Host-Realm", "PARTY")
DrainTimers()
assert(#sends == 1, "accepted response did not cancel stale refresh callback")
AssertKey(20, 506)

now = 1183
assert(harness.ResolveLeaderKeystoneContext() == nil, "group-left key did not expire")
assert(#timers == 1, "group-left scenario did not schedule refresh")
grouped = false
assert(harness.FireEvent)("GROUP_LEFT")
DrainTimers()
assert(#sends == 1, "GROUP_LEFT did not cancel scheduled leader-key refresh")
harness.OnLeaderKeystoneData(22, 508, 0, "Host-Realm", "PARTY")
assert(harness.ResolveLeaderKeystoneContext() == nil,
    "late PARTY response restored leader key after GROUP_LEFT")

grouped = true
ApplicantScoutDB.enabled = true
now = 1200
harness.OnLeaderKeystoneData(21, 507, 0, "Host-Realm", "PARTY")
AssertKey(21, 507)
now = 1261
assert(harness.ResolveLeaderKeystoneContext() == nil, "disable scenario key did not expire")
assert(#timers == 1, "disable scenario did not schedule refresh")
ApplicantScoutDB.enabled = false
DrainTimers()
assert(#sends == 1, "disabled addon sent scheduled leader-key refresh")

print(string.format("ok leader-keystone-refresh sends=%d", #sends))
