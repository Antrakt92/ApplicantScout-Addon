local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local fail = env.fail
local assert_equal = env.assert_equal

-- Silence slash status output around normalization (existing per-check pattern).
local saved_print = print
print = function() end

local function load_with_db(db)
    ApplicantScoutDB = db
    local harness = env.load_addon()
    local ok, err = pcall(SlashCmdList.APSCOUT, "")
    if not ok then fail("slash normalization failed: " .. tostring(err)) end
    return harness
end

local function position_case(label, pos, expectNil, expectX, expectY)
    load_with_db({
        enabled = true,
        debug = false,
        qrFramePosition = pos,
        someFutureFlag = "keep-me",
        futureTable = { nested = 1 },
    })
    assert_equal(label .. " future scalar", ApplicantScoutDB.someFutureFlag, "keep-me")
    assert_equal(label .. " future table", ApplicantScoutDB.futureTable.nested, 1)
    if expectNil then
        if ApplicantScoutDB.qrFramePosition ~= nil then
            fail(label .. " kept an invalid QR position")
        end
        return
    end
    local kept = ApplicantScoutDB.qrFramePosition
    if type(kept) ~= "table" then fail(label .. " dropped a valid QR position") end
    assert_equal(label .. " x", kept.x, expectX)
    assert_equal(label .. " y", kept.y, expectY)
end

position_case("nil stays nil", nil, true)
position_case("valid pair", { x = 12, y = -34 }, false, 12, -34)
position_case("default zeroes", { x = 0, y = 0 }, false, 0, 0)
position_case("string", "12,-34", true)
position_case("number", 42, true)
position_case("empty table", {}, true)
position_case("missing y", { x = 12 }, true)
position_case("missing x", { y = -34 }, true)
position_case("string coords", { x = "12", y = "-34" }, true)
position_case("nan", { x = 0 / 0, y = 0 }, true)
position_case("infinite", { x = math.huge, y = 0 }, true)
position_case("out of range", { x = 1000000, y = 0 }, true)

print = saved_print
io.write("ok db-qr-position-canonicalization\n")
