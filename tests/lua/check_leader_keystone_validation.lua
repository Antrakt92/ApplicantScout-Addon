local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

GetTime = function() return 1000 end
IsInGroup = function() return true end
ApplicantScoutDB = { enabled = true, debug = false }
local cleanAmbiguate = function(name, context)
    assert(context == "none", "leader aliases must retain foreign realms")
    return name:gsub("%-Realm$", "")
end
Ambiguate = cleanAmbiguate

local harness = env.load_addon()

local function assert_key(expectedLevel, expectedMapID, label)
    local key = harness.ResolveLeaderKeystoneContext()
    assert(key, label .. ": expected cached leader key")
    assert(key.level == expectedLevel, label .. ": wrong key level")
    assert(key.challengeMapID == expectedMapID, label .. ": wrong challenge map ID")
end

local function assert_rejected(level, mapID, playerName, label)
    harness.OnLeaderKeystoneData(level, mapID, 0, playerName or "Host-Realm", "PARTY")
    assert_key(18, 504, label)
end

harness.OnLeaderKeystoneData("18", "504", 0, "Host-Realm", "PARTY")
assert_key(18, 504, "legal numeric strings")

assert_rejected(51, 505, nil, "key level above legal range")
assert_rejected(18.5, 505, nil, "fractional key level")
assert_rejected(math.huge, 505, nil, "infinite key level")
assert_rejected("not-a-level", 505, nil, "malformed key level")
assert_rejected(20, 65536, nil, "challenge map above wire range")
assert_rejected(20, 504.5, nil, "fractional challenge map")
assert_rejected(20, "not-a-map", nil, "malformed challenge map")
assert_rejected(20, 505, "Other-Realm", "wrong leader")
assert_rejected(0, 504, nil, "partial clear payload")
assert_rejected(18, 0, nil, "missing-map partial clear payload")
assert_rejected(0, 0, "Other-Realm", "wrong-leader clear payload")

harness.OnLeaderKeystoneData(0, 0, 0, "Host-Realm", "PARTY")
assert(harness.ResolveLeaderKeystoneContext() == nil, "exact clear payload remained cached")

harness.OnLeaderKeystoneData(50, 65535, 0, "Host-Realm", "PARTY")
assert_key(50, 65535, "legal upper boundaries")

-- LibKeystone shortens only local-realm senders; identical foreign names
-- must not gain ownership of the actual leader's key (including clear frames).
env.unit_data.party1.name = "Host"
env.unit_data.party1.realm = "OtherRealm"
UnitIsGroupLeader = function(unit) return unit == "party1" end
harness.OnLeaderKeystoneData(18, 504, 0, "Host-OtherRealm", "PARTY")
assert_key(18, 504, "fully qualified foreign leader")
assert_rejected(20, 505, "Host", "same short name on local realm")
assert_rejected(0, 0, "Host", "same short name cannot clear foreign leader")
assert_rejected(20, 505, "Host-Realm", "qualified local namesake")
harness.OnLeaderKeystoneData(19, 506, 0, "Host-OtherRealm", "PARTY")
assert_key(19, 506, "foreign leader refresh still accepted")

UnitIsGroupLeader = function(unit) return unit == "player" end
harness.OnLeaderKeystoneData(18, 504, 0, "Host", "PARTY")
assert_key(18, 504, "local leader short alias")
assert_rejected(20, 505, "Host-OtherRealm", "foreign namesake cannot replace local leader")

Ambiguate = function() error("name normalization unavailable") end
assert_rejected(20, 505, "Host", "failed name normalization")
local secretName = {}
issecretvalue = function(value) return value == secretName end
Ambiguate = function() return secretName end
assert_rejected(20, 505, "Host", "secret normalized name")
Ambiguate = nil
assert_rejected(20, 505, "Host", "missing name normalization")
harness.OnLeaderKeystoneData(19, 506, 0, "Host-Realm", "PARTY")
assert_key(19, 506, "exact identity needs no name normalization")
Ambiguate = cleanAmbiguate
harness.OnLeaderKeystoneData(0, 0, 0, "Host", "PARTY")
assert(harness.ResolveLeaderKeystoneContext() == nil, "local short alias can clear its own key")

io.write("ok leader-keystone-validation\n")
