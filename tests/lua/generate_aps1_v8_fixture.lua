local fixture_mode = arg and arg[1] or ""
if fixture_mode ~= "" and fixture_mode ~= "leader-key"
   and fixture_mode ~= "placeholder-roster"
   and fixture_mode ~= "placeholder-applicant"
   and fixture_mode ~= "secret-applicant-token"
   and fixture_mode ~= "secret-unit-apis"
   and fixture_mode ~= "secret-leader-owned-key"
   and fixture_mode ~= "secret-leader-keystone" then
    error("unsupported fixture mode: " .. tostring(fixture_mode))
end

local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local notifyInspectCalled = false
local secretBool = nil
local secretGUID = nil
local secretApplicantToken = nil
local originalIsSecretValue = issecretvalue

local function InstallSecretFixtures()
    if secretBool then return secretBool, secretGUID end
    secretBool = {}
    secretGUID = {}
    issecretvalue = function(value)
        if value == secretGUID then error("secret GUID probe failed") end
        if value == secretBool then return true end
        return originalIsSecretValue and originalIsSecretValue(value) or false
    end
    return secretBool, secretGUID
end

if fixture_mode == "placeholder-roster" then
    env.unit_data.party1.unitFullName = { "", "" }
    env.unit_data.party1.unitName = "Unknown-Realm"
end
if fixture_mode == "placeholder-applicant" then
    local originalGetApplicantMemberInfo = C_LFGList.GetApplicantMemberInfo
    C_LFGList.GetApplicantMemberInfo = function(id, memberIndex)
        if id == 42 and memberIndex == 1 then
            return "Unknown-Realm", "WARRIOR", nil, nil, 710.2, nil, nil, nil, nil,
                "TANK", nil, 3210, nil, nil, nil, 73
        end
        return originalGetApplicantMemberInfo(id, memberIndex)
    end
end
if fixture_mode == "secret-applicant-token" then
    secretApplicantToken = {}
    local originalIsSecret = issecretvalue
    issecretvalue = function(value)
        if value == secretApplicantToken then return true end
        return originalIsSecret and originalIsSecret(value) or false
    end
    env.secret_applicant_token = secretApplicantToken
end
if fixture_mode == "secret-unit-apis" then
    local secretBoolValue, secretGUIDValue = InstallSecretFixtures()

    local originalUnitExists = UnitExists
    UnitExists = function(unit)
        if unit == "party1" then return secretBoolValue end
        return originalUnitExists(unit)
    end

    local originalUnitIsUnit = UnitIsUnit
    UnitIsUnit = function(left, right)
        if left == "player" and right == "player" then return secretBoolValue end
        return originalUnitIsUnit(left, right)
    end

    local originalUnitGUID = UnitGUID
    UnitGUID = function(unit)
        if unit == "party2" then return secretGUIDValue end
        return originalUnitGUID(unit)
    end

    env.unit_data.party3.specID = 0
    CanInspect = function(unit)
        if unit == "party3" then return secretBoolValue end
        return true
    end
    NotifyInspect = function()
        notifyInspectCalled = true
    end
end
if fixture_mode == "secret-leader-owned-key"
   or fixture_mode == "secret-leader-keystone" then
    local secretBoolValue = InstallSecretFixtures()
    IsInGroup = function() return true end
    UnitIsGroupLeader = function(unit)
        if unit == "player" then return secretBoolValue end
        return false
    end
end
if fixture_mode == "secret-leader-owned-key" then
    C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel = function()
        return 401, 399, 18
    end
end

if fixture_mode == "leader-key" or fixture_mode == "secret-leader-keystone" then
    ApplicantScoutDB = {
        enabled = true,
        debug = false,
    }
end

local harness = env.load_addon()

local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "+16 Fixture Halls",
    comment = "bring kicks",
}
if fixture_mode == "secret-leader-owned-key" then
    entry.name = "Fixture Halls"
end
if fixture_mode == "leader-key" then
    assert(harness.OnLeaderKeystoneData)(
        17,
        503,
        0,
        "Host-Realm",
        "PARTY"
    )
end
if fixture_mode == "secret-leader-keystone" then
    assert(harness.OnLeaderKeystoneData)(
        17,
        556,
        0,
        "Host-Realm",
        "PARTY"
    )
end
local applicantIDs = secretApplicantToken and { secretApplicantToken } or { 42 }
local payload = assert(harness.BuildPayload)(entry, applicantIDs, false)
if fixture_mode == "secret-unit-apis" and notifyInspectCalled then
    error("NotifyInspect called for secret CanInspect")
end
if fixture_mode == "secret-unit-apis" then
    if not (harness.LastPayloadRosterIncomplete and harness.LastPayloadRosterIncomplete()) then
        error("secret UnitExists did not mark roster payload incomplete")
    end
end
for i = 1, #payload do
    io.write(string.format("%02x", string.byte(payload, i)))
end
io.write("\n")
