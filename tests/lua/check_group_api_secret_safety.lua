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

-- Retry-stack group guards: secret group state refuses sends without raising
-- and schedules no C_Timer retry (clean ~= true fails closed).
groupBehavior = "secret"
lockdown = false
timers = {}
sends = {}
harness.LibKeystoneShimHandleAddonMessage("LibKS", "R", "PARTY", "Someone-Realm")
assert_equal("secret group response sends", #sends, 0)
assert_equal("secret group response timers", #timers, 0)

-- Leader request guard: secret/failing/unknown group refuses before any send.
for _, behavior in ipairs({ "secret", "error", "nil" }) do
    groupBehavior = behavior
    lockdown = false
    timers = {}
    sends = {}
    local requestOK = pcall(harness.RequestLeaderKeystone, true)
    if not requestOK then fail("leader request propagated a group API failure: " .. behavior) end
    assert_equal("unreadable group request sends (" .. behavior .. ")", #sends, 0)
    assert_equal("unreadable group request timers (" .. behavior .. ")", #timers, 0)
end

-- Auto Hi group-size/raid gates (GROUP_ROSTER_UPDATE path): raw
-- GetNumGroupMembers()/IsInRaid() must never drive greetings. Unknown reads
-- fail closed as nil/false without raising.
for _, hook in ipairs({
    "AutoHiGroupMemberCount",
    "IsGroupedForAutoHi",
    "IsPartyForAutoHiNewMembers",
    "IsPartyContextForAutoHiNewMembers",
    "CollectAutoHiPartyMemberGUIDs",
    "ScheduleAutoHiIfGroupJoined",
    "ToggleSettingsPanel",
}) do
    if type(harness[hook]) ~= "function" then
        fail("missing Auto Hi fixture hook: " .. hook)
    end
end

local groupCountBehavior = "three"
local groupCountValue = 3
local function resolveCountBehavior(behavior)
    if behavior == "secret" then return secretToken end
    if behavior == "error" then error("group size unreadable") end
    if behavior == "nil" then return nil end
    return groupCountValue
end
GetNumGroupMembers = function() return resolveCountBehavior(groupCountBehavior) end

local function autoHiCount()
    local ok, result = pcall(harness.AutoHiGroupMemberCount)
    if not ok then fail("AutoHiGroupMemberCount propagated a group API failure: " .. tostring(result)) end
    return result
end
local function autoHiFlag(fn)
    local ok, result = pcall(fn)
    if not ok then fail("Auto Hi predicate propagated a group API failure") end
    return result
end

-- Clean party: count passes through, party predicates hold.
groupCountBehavior, groupCountValue = "clean", 3
raidBehavior = "false"
assert_equal("clean auto-hi count", autoHiCount(), 3)
assert_equal("clean grouped for auto-hi", autoHiFlag(harness.IsGroupedForAutoHi), true)
assert_equal("clean party for new members", autoHiFlag(harness.IsPartyForAutoHiNewMembers), true)
assert_equal("clean party context", autoHiFlag(harness.IsPartyContextForAutoHiNewMembers), true)
do
    local ok, guids, complete = pcall(harness.CollectAutoHiPartyMemberGUIDs)
    if not ok then fail("party GUID collect propagated a group API failure") end
    assert_equal("clean party sample complete", complete, true)
    assert_equal("clean party sample non-empty", next(guids) ~= nil, true)
end

-- Raid gate: a raid-sized clean group never counts as party/group for Auto Hi.
groupCountBehavior, groupCountValue = "clean", 8
raidBehavior = "true"
assert_equal("raid grouped for auto-hi", autoHiFlag(harness.IsGroupedForAutoHi), false)
assert_equal("raid party for new members", autoHiFlag(harness.IsPartyForAutoHiNewMembers), false)
assert_equal("raid party context", autoHiFlag(harness.IsPartyContextForAutoHiNewMembers), false)
do
    local ok, _, complete = pcall(harness.CollectAutoHiPartyMemberGUIDs)
    if not ok then fail("raid GUID collect propagated a group API failure") end
    assert_equal("raid party sample complete", complete, false)
end

-- Unknown size or raid state fails closed on every predicate.
for _, countBehavior in ipairs({ "secret", "error", "nil" }) do
    groupCountBehavior = countBehavior
    raidBehavior = "false"
    assert_equal("unknown size count (" .. countBehavior .. ")", autoHiCount(), nil)
    assert_equal("unknown size grouped (" .. countBehavior .. ")", autoHiFlag(harness.IsGroupedForAutoHi), false)
    assert_equal("unknown size party (" .. countBehavior .. ")", autoHiFlag(harness.IsPartyForAutoHiNewMembers), false)
    assert_equal("unknown size context (" .. countBehavior .. ")", autoHiFlag(harness.IsPartyContextForAutoHiNewMembers), false)
    do
        local ok, _, complete = pcall(harness.CollectAutoHiPartyMemberGUIDs)
        if not ok then fail("unknown-size GUID collect raised: " .. countBehavior) end
        assert_equal("unknown-size sample complete (" .. countBehavior .. ")", complete, false)
    end
end
for _, badRaid in ipairs({ "secret", "error", "nil" }) do
    groupCountBehavior, groupCountValue = "clean", 3
    raidBehavior = badRaid
    assert_equal("unknown raid grouped (" .. badRaid .. ")", autoHiFlag(harness.IsGroupedForAutoHi), false)
    assert_equal("unknown raid party (" .. badRaid .. ")", autoHiFlag(harness.IsPartyForAutoHiNewMembers), false)
    assert_equal("unknown raid context (" .. badRaid .. ")", autoHiFlag(harness.IsPartyContextForAutoHiNewMembers), false)
end

-- Join greeting raid gate: the kind=="group" delayed send never arms in a
-- raid, while an identical party arms exactly one 5s greeting attempt.
local function groupJoinTimers(count, raid)
    ApplicantScoutDB = { enabled = true, debug = false, autoHiMessage = "hi" }
    local fresh = env.load_addon()
    timers = {}
    C_Timer.After = function(_delay, callback)
        timers[#timers + 1] = callback
    end
    -- Left baseline first, then the observed join: only the neither->group
    -- transition arms the greeting (solo->group just flips tracking flags).
    groupCountBehavior, groupCountValue = "clean", 0
    raidBehavior = "false"
    fresh.ScheduleAutoHiIfGroupJoined()
    groupCountBehavior, groupCountValue = "clean", count
    raidBehavior = raid
    fresh.ScheduleAutoHiIfGroupJoined()
    local delayCount = 0
    for _, callback in ipairs(timers) do
        if type(callback) == "function" then delayCount = delayCount + 1 end
    end
    return delayCount, fresh
end
do
    local raidTimers = groupJoinTimers(8, "true")
    assert_equal("raid join greeting timers", raidTimers, 0)
    local partyTimers = groupJoinTimers(3, "false")
    assert_equal("party join greeting timers", partyTimers, 1)
end

-- Settings combat gate: clean combat still refuses; secret/failing/missing
-- lockdown never raises (unknown proceeds past the gate to unavailable).
do
    local savedPrint = print
    print = function() end
    local savedLockdown = InCombatLockdown
    InCombatLockdown = function() return true end
    local ok, toggleOK, toggleReason = pcall(harness.ToggleSettingsPanel)
    if not ok then fail("settings toggle propagated a combat API failure") end
    assert_equal("combat toggle ok", toggleOK, false)
    assert_equal("combat toggle reason", toggleReason, "combat")
    InCombatLockdown = function() return secretToken end
    ok, toggleOK = pcall(harness.ToggleSettingsPanel)
    if not ok then fail("settings toggle propagated a secret combat value") end
    assert_equal("secret combat toggle ok type", type(toggleOK), "boolean")
    InCombatLockdown = function() error("lockdown unreadable") end
    ok = pcall(harness.ToggleSettingsPanel)
    if not ok then fail("settings toggle propagated a combat API failure") end
    InCombatLockdown = nil
    ok = pcall(harness.ToggleSettingsPanel)
    if not ok then fail("settings toggle propagated a missing combat API") end
    InCombatLockdown = savedLockdown
    print = savedPrint
end

print("ok group-api-secret-safety")
