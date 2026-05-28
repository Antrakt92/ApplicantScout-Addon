local fixture_mode = arg and arg[1] or ""
if fixture_mode ~= "" and fixture_mode ~= "leader-key"
   and fixture_mode ~= "placeholder-roster" then
    error("unsupported fixture mode: " .. tostring(fixture_mode))
end

local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

if fixture_mode == "placeholder-roster" then
    env.unit_data.party1.unitFullName = { "", "" }
    env.unit_data.party1.unitName = "Unknown-Realm"
end

local harness = env.load_addon()

local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "+16 Fixture Halls",
    comment = "bring kicks",
}
if fixture_mode == "leader-key" then
    assert(harness.OnLeaderKeystoneData)(
        17,
        503,
        0,
        "Host-Realm",
        "PARTY"
    )
end
local payload = assert(harness.BuildPayload)(entry, { 42 }, false)
for i = 1, #payload do
    io.write(string.format("%02x", string.byte(payload, i)))
end
io.write("\n")
