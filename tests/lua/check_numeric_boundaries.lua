local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local harness = env.load_addon()

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format(
            "%s: expected %s, got %s",
            label,
            tostring(expected),
            tostring(actual)
        ))
    end
end

local nan = 0 / 0
assert_equal(harness.SafeNumber(nan, 9), 9, "NaN fallback")
assert_equal(harness.SafeNumber(math.huge, 9), 9, "positive infinity fallback")
assert_equal(harness.SafeNumber(-math.huge, 9), 9, "negative infinity fallback")
assert_equal(harness.SafeNumber("1e309", 9), 9, "overflow string fallback")
assert_equal(harness.SafeNumber("42.5", 0), 42.5, "numeric string")

assert_equal(harness.ClampUInt8(math.huge), 0, "uint8 positive infinity")
assert_equal(harness.ClampUInt8("255.9"), 255, "uint8 numeric string")
assert_equal(harness.ClampUInt8("256"), 255, "uint8 upper clamp")
assert_equal(harness.ClampUInt8("-1"), 0, "uint8 lower clamp")
assert_equal(harness.ClampUInt16(-math.huge), 0, "uint16 negative infinity")
assert_equal(harness.ClampUInt16("65535.9"), 65535, "uint16 numeric string")
assert_equal(harness.ClampUInt16("65536"), 65535, "uint16 upper clamp")
assert_equal(harness.ClampUInt16("-1"), 0, "uint16 lower clamp")

assert_equal(
    harness.Uint32BE(math.huge),
    string.char(0, 0, 0, 0),
    "uint32 infinity fallback"
)
assert_equal(
    harness.Uint32BE("4294967297"),
    string.char(0, 0, 0, 1),
    "uint32 numeric string wrap"
)
assert_equal(
    harness.Uint16BE(-math.huge),
    string.char(0, 0),
    "uint16 infinity fallback"
)
assert_equal(
    harness.Uint16BE("65537"),
    string.char(0, 1),
    "uint16 numeric string wrap"
)

io.write("ok numeric-boundaries\n")
