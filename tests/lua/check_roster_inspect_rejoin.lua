local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local groupCount = 5
GetNumGroupMembers = function() return groupCount end
C_PaperDollInfo.GetInspectItemLevel = function(unit)
    local data = env.unit_data[unit]
    return data and data.ilvl or 0
end

env.unit_data.party1.class = "PRIEST"
env.unit_data.party1.classID = 5
env.unit_data.party1.specID = 256
env.unit_data.party1.role = "NONE"
env.unit_data.party1.ilvl = 704.4

local harness = env.load_addon()
local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "+16 Fixture Halls",
    comment = "bring kicks",
}

local function WritePayload(payload)
    for i = 1, #payload do
        io.write(string.format("%02x", string.byte(payload, i)))
    end
    io.write("\n")
end

assert(harness.StartSession)()
WritePayload(assert(harness.BuildPayload)(entry, {}, false))

env.unit_data.party1 = nil
groupCount = 4
assert(harness.FireEvent)("GROUP_ROSTER_UPDATE")

env.unit_data.party1 = {
    name = "Friend",
    realm = "Realm",
    guid = "Party-1",
    class = "PRIEST",
    classID = 5,
    specID = 258,
    role = "NONE",
    ilvl = 798.6,
}
groupCount = 5
assert(harness.FireEvent)("GROUP_ROSTER_UPDATE")

WritePayload(assert(harness.BuildPayload)(entry, {}, false))
