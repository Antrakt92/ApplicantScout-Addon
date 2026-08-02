local env = dofile("tests/lua/appscout_fixture_env.lua")

ApplicantScoutFixtureHarness = { sentinel = true }

local first = env.load_addon()
local second = env.load_addon()

assert(first ~= second, "successive addon loads must receive isolated harness tables")
assert(type(first.BuildPayload) == "function", "private harness must receive exports")
assert(type(second.BuildPayload) == "function", "second private harness must receive exports")
assert(
    first.ClearQROverflowTransport == nil,
    "unused QR overflow clear helper must not remain exported"
)
assert(
    ApplicantScoutFixtureHarness.sentinel == true
        and ApplicantScoutFixtureHarness.BuildPayload == nil,
    "addon load must not mutate the shared WoW global namespace"
)

print("fixture harness namespace: PASS")
