local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
env.load_addon()

local cases = {
    { "weekly in 15 minutes", 0 },
    { "15", 0 },
    { "+15", 15 },
    { "  +15 Competitive  ", 15 },
    { "＋15", 15 },
    { "﹢15 Competitive", 15 },
    { "➕ 15", 15 },
    { "weekly ＋15", 0 },
}

for _, case in ipairs(cases) do
    local actual = ApplicantScout_GetListingKeystoneLevel(0, 0, case[1], "", nil)
    assert(
        actual == case[2],
        string.format("listing title %q: expected %d, got %d", case[1], case[2], actual)
    )
end

print("listing-key-title-shapes-ok")
