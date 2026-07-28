local scenario = arg and arg[1] or "apply-default"
local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local fail = env.fail
local assert_equal = env.assert_equal
local assert_nil = env.assert_nil

if scenario == "disabled-token" then
    ApplicantScoutDB = {
        enabled = true,
        autoMPlusPlaystyle = "disabled",
    }
else
    ApplicantScoutDB = nil
end

local harness = env.load_addon()
if type(SlashCmdList.APSCOUT) ~= "function" then
    fail("missing /apscout slash handler")
end

local real_print = print
print = function() end
local ok, err = pcall(SlashCmdList.APSCOUT, "")
print = real_print
if not ok then fail(tostring(err)) end

if type(harness.MaybeAutoSelectDefaultPlaystyle) ~= "function" then
    fail("missing _MaybeAutoSelectDefaultPlaystyle")
end

Enum = {
    LFGEntryGeneralPlaystyle = {
        None = 0,
        Learning = 101,
        FunRelaxed = 102,
        FunSerious = 103,
        Expert = 104,
    },
}
LFGListEntryCreation_IsEditMode = function(panel)
    return panel and panel.editMode == true
end
local validStateUpdates = 0
LFGListEntryCreation_UpdateValidState = function()
    validStateUpdates = validStateUpdates + 1
end
LFGListEntryCreation_OnPlayStyleSelectedInternal = function(panel, playstyle)
    panel.generalPlaystyle = playstyle
    LFGListEntryCreation_UpdateValidState(panel)
end
local secureCallCount = 0
securecallfunction = function(callable, ...)
    secureCallCount = secureCallCount + 1
    return callable(...)
end
C_LFGList.GetActivityInfoTable = function(activityID)
    if activityID == 100 then
        return { isMythicPlusActivity = true }
    end
    return { isMythicPlusActivity = false }
end

local menuGenerated = false
local panel = {
    selectedActivity = 100,
    PlayStyleDropdown = {
        GenerateMenu = function()
            menuGenerated = true
        end,
    },
}

if scenario == "edit-mode" then
    panel.editMode = true
elseif scenario == "non-mplus" then
    panel.selectedActivity = 200
elseif scenario == "missing-enum" then
    Enum = nil
elseif scenario == "existing-selection" then
    panel.generalPlaystyle = 102
end

local applied = harness.MaybeAutoSelectDefaultPlaystyle(panel, "fixture")

if scenario == "apply-default" then
    assert_equal("applied", applied, true)
    assert_equal("generalPlaystyle", panel.generalPlaystyle, 103)
    assert_equal("validStateUpdates", validStateUpdates, 1)
    assert_equal("menuGenerated", menuGenerated, false)
    assert_equal("secureCallCount", secureCallCount, 1)
elseif scenario == "disabled-token" then
    assert_equal("applied", applied, false)
    assert_nil("generalPlaystyle", panel.generalPlaystyle)
elseif scenario == "edit-mode" then
    assert_equal("applied", applied, false)
    assert_nil("generalPlaystyle", panel.generalPlaystyle)
elseif scenario == "non-mplus" then
    assert_equal("applied", applied, false)
    assert_nil("generalPlaystyle", panel.generalPlaystyle)
elseif scenario == "missing-enum" then
    assert_equal("applied", applied, false)
    assert_nil("generalPlaystyle", panel.generalPlaystyle)
elseif scenario == "existing-selection" then
    assert_equal("applied", applied, false)
    assert_equal("generalPlaystyle", panel.generalPlaystyle, 102)
    assert_equal("secureCallCount", secureCallCount, 0)
else
    fail("unsupported scenario: " .. tostring(scenario))
end

print("ok " .. scenario)
