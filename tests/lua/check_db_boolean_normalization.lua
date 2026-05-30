local scenario = arg and arg[1] or "corrupt"
local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local function fail(message)
    io.stderr:write(message .. "\n")
    os.exit(1)
end

local function assert_equal(name, actual, expected)
    if actual ~= expected then
        fail(name .. " expected " .. tostring(expected)
             .. " (" .. type(expected) .. ") but got "
             .. tostring(actual) .. " (" .. type(actual) .. ")")
    end
end

local function assert_nil(name, actual)
    if actual ~= nil then
        fail(name .. " expected nil but got " .. tostring(actual)
             .. " (" .. type(actual) .. ")")
    end
end

if scenario == "corrupt" then
    ApplicantScoutDB = {
        enabled = "false",
        debug = "true",
        autoHiGreetNewPartyMembers = 0,
        debugDefaultMigrated = "false",
        autoMPlusPlaystyle = "FunSerious",
    }
elseif scenario == "defaults" then
    ApplicantScoutDB = nil
elseif scenario == "legacy-false" then
    ApplicantScoutDB = {
        autoCompetitivePlaystyle = "false",
    }
elseif scenario == "legacy-true" then
    ApplicantScoutDB = {
        autoCompetitivePlaystyle = "yes",
    }
elseif scenario == "wrong-types" then
    ApplicantScoutDB = {
        enabled = {},
        debug = function() end,
        autoHiGreetNewPartyMembers = "maybe",
        debugDefaultMigrated = 2,
    }
else
    fail("unsupported scenario: " .. tostring(scenario))
end

env.load_addon()
if type(SlashCmdList.APSCOUT) ~= "function" then
    fail("missing /apscout slash handler")
end

local real_print = print
print = function() end
local ok, err = pcall(SlashCmdList.APSCOUT, "")
print = real_print
if not ok then fail(tostring(err)) end

if scenario == "corrupt" then
    assert_equal("enabled", ApplicantScoutDB.enabled, false)
    assert_equal("debug", ApplicantScoutDB.debug, false)
    assert_equal(
        "autoHiGreetNewPartyMembers",
        ApplicantScoutDB.autoHiGreetNewPartyMembers,
        false
    )
    assert_equal("debugDefaultMigrated", ApplicantScoutDB.debugDefaultMigrated, true)
    assert_equal("autoMPlusPlaystyle", ApplicantScoutDB.autoMPlusPlaystyle, "FunSerious")
    assert_nil("autoCompetitivePlaystyle", ApplicantScoutDB.autoCompetitivePlaystyle)
elseif scenario == "defaults" then
    assert_equal("enabled", ApplicantScoutDB.enabled, true)
    assert_equal("debug", ApplicantScoutDB.debug, false)
    assert_equal("autoMPlusPlaystyle", ApplicantScoutDB.autoMPlusPlaystyle, "FunSerious")
    assert_nil("autoCompetitivePlaystyle", ApplicantScoutDB.autoCompetitivePlaystyle)
    assert_equal(
        "autoHiGreetNewPartyMembers",
        ApplicantScoutDB.autoHiGreetNewPartyMembers,
        false
    )
    assert_equal("debugDefaultMigrated", ApplicantScoutDB.debugDefaultMigrated, true)
elseif scenario == "legacy-false" then
    assert_equal("autoMPlusPlaystyle", ApplicantScoutDB.autoMPlusPlaystyle, "disabled")
    assert_nil("autoCompetitivePlaystyle", ApplicantScoutDB.autoCompetitivePlaystyle)
elseif scenario == "legacy-true" then
    assert_equal("autoMPlusPlaystyle", ApplicantScoutDB.autoMPlusPlaystyle, "FunSerious")
    assert_nil("autoCompetitivePlaystyle", ApplicantScoutDB.autoCompetitivePlaystyle)
elseif scenario == "wrong-types" then
    assert_equal("enabled", ApplicantScoutDB.enabled, false)
    assert_equal("debug", ApplicantScoutDB.debug, false)
    assert_equal(
        "autoHiGreetNewPartyMembers",
        ApplicantScoutDB.autoHiGreetNewPartyMembers,
        false
    )
    assert_equal("debugDefaultMigrated", ApplicantScoutDB.debugDefaultMigrated, true)
end

io.write("ok " .. scenario .. "\n")
