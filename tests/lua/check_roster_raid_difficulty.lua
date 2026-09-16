local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
env.install_raid_roster(3)
local harness = env.load_addon({})
local selectedDifficulty = 15
local instanceType, instanceDifficulty = "none", 0
local instanceReads, selectedReads = 0, 0
GetInstanceInfo = function()
    instanceReads = instanceReads + 1
    return "Fixture", instanceType, instanceDifficulty
end
GetRaidDifficultyID = function()
    selectedReads = selectedReads + 1
    return selectedDifficulty
end

local function check(expected)
    instanceReads, selectedReads = 0, 0
    local payload, count, signature, _, inRaid = harness.BuildRosterPayloadRows(0, 0)
    assert(inRaid and count == 3, "small raid group lost raid identity")
    assert(payload == signature, "difficulty omitted from quiet snapshot signature")
    local offset = 1
    for _ = 1, count do
        local flags = string.byte(payload, offset + 1)
        assert(bit.band(flags, 0x1e) == expected,
            string.format("expected raid context flags %d, got %d", expected, flags))
        offset = offset + 22 + string.byte(payload, offset + 21)
    end
    assert(offset == #payload + 1, "roster parsing did not consume exact bytes")
    assert(instanceReads <= 1 and selectedReads <= 1, "difficulty read per row")
    return signature
end

local heroic = check(0x1a)
selectedDifficulty = 14
local generation = harness.QRTransportState().dirtyGeneration
local reads = instanceReads
harness.FireEvent("PLAYER_DIFFICULTY_CHANGED")
assert(harness.QRTransportState().scanDirty
    and harness.QRTransportState().dirtyGeneration == generation + 1,
    "difficulty event did not queue snapshot refresh")
assert(instanceReads == reads, "difficulty event performed synchronous context reads")
local normal = check(0x16)
assert(heroic ~= normal, "difficulty change did not invalidate snapshot")
selectedDifficulty = 16
check(0x1e)
instanceType, instanceDifficulty = "raid", 14
generation = harness.QRTransportState().dirtyGeneration
harness.FireEvent("UPDATE_INSTANCE_INFO")
assert(harness.QRTransportState().dirtyGeneration == generation + 1,
    "instance event did not queue snapshot refresh")
check(0x16)
assert(selectedReads == 0, "selected menu difficulty overrode actual raid instance")
for _, unsupported in ipairs({ "pvp", "arena", "party", "scenario", "interior", "neighborhood", "" }) do
    instanceType = unsupported
    check(0x12)
end
instanceType = "raid"
for _, unsupported in ipairs({ 0, 3, 17, 23, 15.5, math.huge }) do
    instanceDifficulty = unsupported
    check(0x12)
end
instanceType = "none"
local secret = {}
issecretvalue = function(value) return value == secret end
selectedDifficulty = secret
check(0x12)
selectedDifficulty = 15
instanceType = secret
check(0x12)
GetInstanceInfo = function() error("unavailable") end
check(0x12)
GetInstanceInfo = nil
check(0x12)
IsInRaid = function() return secret end
local _, count, _, _, inRaid, incomplete = harness.BuildRosterPayloadRows(0, 0)
assert(count == 0 and not inRaid and incomplete, "unknown raid identity became authoritative party")
IsInRaid = function() error("unavailable") end
local _, failedCount, _, _, _, failedIncomplete = harness.BuildRosterPayloadRows(0, 0)
assert(failedCount == 0 and failedIncomplete, "failed raid identity became authoritative party")
IsInRaid = function() return false end
local partyPayload, partyCount = harness.BuildRosterPayloadRows(0, 0)
local partyOffset = 1
for _ = 1, partyCount do
    assert(bit.band(string.byte(partyPayload, partyOffset + 1), 0x1e) == 0,
        "raid context leaked into party after conversion")
    partyOffset = partyOffset + 22 + string.byte(partyPayload, partyOffset + 21)
end
print("ok roster-raid-difficulty")
