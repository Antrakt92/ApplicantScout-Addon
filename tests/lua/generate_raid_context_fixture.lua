local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
env.install_raid_roster(3)
GetInstanceInfo = function() return "Fixture", arg[1], tonumber(arg[2]) end
GetRaidDifficultyID = function() return tonumber(arg[3]) end
local harness = env.load_addon({})
local payload = harness.BuildPayload(nil, {}, false)
for index = 1, #payload do
    io.write(string.format("%02x", string.byte(payload, index)))
end
io.write("\n")
