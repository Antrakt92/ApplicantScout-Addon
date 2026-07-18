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
        qrAlwaysVisible = "false",
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
        qrAlwaysVisible = {},
        debugDefaultMigrated = 2,
    }
elseif scenario == "qr-visible" then
    ApplicantScoutDB = {
        qrAlwaysVisible = "yes",
    }
else
    fail("unsupported scenario: " .. tostring(scenario))
end

local qrShown = false
local baseCreateFrame = CreateFrame
if scenario == "qr-visible" then
    UIParent.GetWidth = function() return 1920 end
    UIParent.GetHeight = function() return 1080 end
    CreateFrame = function(frameType, name, ...)
        local frame = baseCreateFrame(frameType, name, ...)
        if name == "ApplicantScoutQRFrame" then
            frame.SetIgnoreParentScale = function() end
            frame.SetClampedToScreen = function() end
            frame.SetAlpha = function() end
            frame.GetWidth = function() return 64 end
            frame.ClearAllPoints = function() end
            local baseCreateTexture = frame.CreateTexture
            frame.CreateTexture = function(...)
                local texture = baseCreateTexture(...)
                texture.SetAllPoints = function() end
                return texture
            end
            frame.Show = function() qrShown = true end
            frame.Hide = function() qrShown = false end
            frame.IsShown = function() return qrShown end
        end
        return frame
    end
end

local harness = env.load_addon()
if type(SlashCmdList.APSCOUT) ~= "function" then
    fail("missing /apscout slash handler")
end

local real_print = print
print = function() end
local ok, err
if scenario == "qr-visible" then
    harness.FireEvent("PLAYER_LOGIN")
    harness.FireEvent("PLAYER_ENTERING_WORLD")
    assert_equal("persisted QR visibility", qrShown, true)
    assert_equal("persisted runtime visibility", harness.QRTransportState().alwaysVisible, true)
    assert_equal("normalized qrAlwaysVisible", ApplicantScoutDB.qrAlwaysVisible, true)

    SlashCmdList.APSCOUT("qrvisible")
    assert_equal("toggled QR visibility", qrShown, false)
    assert_equal("toggled runtime visibility", harness.QRTransportState().alwaysVisible, false)
    assert_equal("disabled qrAlwaysVisible", ApplicantScoutDB.qrAlwaysVisible, false)

    SlashCmdList.APSCOUT("qrvisible")
    assert_equal("re-enabled QR visibility", qrShown, true)
    assert_equal("re-enabled runtime visibility", harness.QRTransportState().alwaysVisible, true)
    assert_equal("re-enabled qrAlwaysVisible", ApplicantScoutDB.qrAlwaysVisible, true)

    SlashCmdList.APSCOUT("off")
    assert_equal("disabled addon QR visibility", qrShown, false)
    assert_equal("disabled addon runtime visibility", harness.QRTransportState().alwaysVisible, false)
    assert_equal("disabled addon qrAlwaysVisible", ApplicantScoutDB.qrAlwaysVisible, false)
    ok = true
else
    ok, err = pcall(SlashCmdList.APSCOUT, "")
end
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
    assert_equal("qrAlwaysVisible", ApplicantScoutDB.qrAlwaysVisible, false)
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
    assert_equal("qrAlwaysVisible", ApplicantScoutDB.qrAlwaysVisible, false)
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
    assert_equal("qrAlwaysVisible", ApplicantScoutDB.qrAlwaysVisible, false)
elseif scenario == "qr-visible" then
    -- Assertions run around the live toggle transitions above.
end

io.write("ok " .. scenario .. "\n")
