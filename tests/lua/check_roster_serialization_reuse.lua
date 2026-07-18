local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
env.install_raid_roster(40)

-- Keep every raid member fully resolved so this fixture measures only the
-- synchronous serialization work for the stable roster payload.
C_PaperDollInfo.GetInspectItemLevel = function(unit)
    if string.find(unit, "^raid") then return 700 end
    return 0
end

local harness = env.load_addon({})
local buildRosterPayloadRows = assert(
    harness.BuildRosterPayloadRows,
    "missing roster payload fixture hook"
)

local originalInsert = table.insert
local insertCount = 0
table.insert = function(...)
    insertCount = insertCount + 1
    return originalInsert(...)
end

local rosterPayload, rosterCount, quietSignature,
      hasUnknownSpec, inRaid, rosterIncomplete =
    buildRosterPayloadRows(401, 15)
table.insert = originalInsert

assert(type(rosterPayload) == "string", "roster payload was not serialized once")
assert(rosterPayload == quietSignature, "quiet signature diverged from wire roster bytes")
assert(rosterCount == 40, "raid-40 fixture did not serialize every roster row")
assert(not hasUnknownSpec, "resolved raid roster reported an unknown specialization")
assert(inRaid, "raid-40 fixture lost raid context")
assert(not rosterIncomplete, "resolved raid roster was marked incomplete")
assert(insertCount == 800, string.format(
    "roster serialization used %d table inserts instead of one 20-insert path per row",
    insertCount
))

local wirePayload = assert(harness.BuildPayload)({
    activityIDs = { 401 },
    questID = 0,
    name = "Raid 40 transport benchmark",
    comment = "stable roster",
}, {}, false)
assert(#wirePayload == 2198, "roster reuse changed the APS1 payload length")
assert(
    harness.HashSnapshot(wirePayload) == 185550839,
    "roster reuse changed the APS1 payload bytes"
)

print(string.format(
    "ok roster-serialization-reuse rows=%d inserts=%d bytes=%d wire_hash=%u",
    rosterCount,
    insertCount,
    #rosterPayload,
    harness.HashSnapshot(wirePayload)
))
