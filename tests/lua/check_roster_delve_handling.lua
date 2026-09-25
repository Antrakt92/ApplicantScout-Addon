local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local harness = env.load_addon({})

-- Delves, follower dungeons, and scenarios are intentionally SUPPORTED through
-- the generic non-Mythic+ path: NPC companions occupy no party slots, so the
-- roster builder must transport the real party unchanged while any such
-- listing carries keyLevel 0 on the wire.

-- Baseline: player + party1-4 all transport as a non-raid party.
local _, partyCount, _, _, partyInRaid = harness.BuildRosterPayloadRows(0, 0)
assert(partyCount == 5 and not partyInRaid, "party baseline did not transport 5 real members")

-- NPC companions live outside player/party1-4, so they must never leak rows
-- into the payload nor change the transported count.
env.unit_data["party5"] = {
    name = "Brann",
    realm = "Realm",
    guid = "NPC-1",
    class = "WARRIOR",
    classID = 1,
    specID = 73,
    role = "DAMAGER",
}
env.unit_data["target"] = {
    name = "Brann",
    realm = "Realm",
    guid = "NPC-1",
    class = "WARRIOR",
    classID = 1,
    specID = 73,
    role = "DAMAGER",
}
local npcPayload, npcCount = harness.BuildRosterPayloadRows(0, 0)
assert(npcCount == 5, "NPC companion changed the roster row count")
assert(not npcPayload:find("Brann", 1, true), "NPC companion leaked into roster payload")
env.unit_data["party5"] = nil
env.unit_data["target"] = nil

-- Delve-like listing (non-Mythic+ category): the M+ gate must hold keyLevel
-- at 0 even with a "+15" title, while the real party roster still ships.
local delveEntry = {
    activityIDs = { 501 },
    questID = 0,
    name = "+15 Delve push",
    comment = "need dps",
}
C_LFGList.GetActivityInfoTable = function()
    return {
        shortName = "Delve",
        fullName = "Delve",
        categoryID = 9,
        difficultyID = 8,
    }
end
local delvePayload = assert(harness.BuildPayload)(delveEntry, {}, false)
assert(delvePayload:byte(10) == 1, "delve listing lost its listing block")
local delveCategory = delvePayload:byte(15) * 256 + delvePayload:byte(16)
assert(delveCategory == 9, "delve listing did not carry its category")
assert(delvePayload:byte(19) == 0, "delve listing carried a Mythic+ key level")
assert(harness.LastPayloadRosterCount() == 5, "delve listing dropped the real party roster")

-- Control: the same "+15" title on a Mythic+ category listing extracts 15,
-- proving the category gate (not the title parser) zeroes delve keys.
C_LFGList.GetActivityInfoTable = function()
    return {
        shortName = "Fixture Halls",
        fullName = "Fixture Halls",
        categoryID = 2,
        difficultyID = 8,
    }
end
local mplusPayload = assert(harness.BuildPayload)(delveEntry, {}, false)
assert(mplusPayload:byte(19) == 15, "M+ gate regressed: +15 title did not yield key level 15")

-- Solo follower/scenario run: no group slots occupied, so the roster is empty.
GetNumGroupMembers = function() return 0 end
local soloPayload, soloCount = harness.BuildRosterPayloadRows(0, 0)
assert(soloCount == 0 and soloPayload == "", "solo follower/scenario run produced roster rows")

print("ok roster-delve-handling")
