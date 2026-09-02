local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local challengeMode = arg and arg[1] == "challenge"
local challengeActive = false
C_ChallengeMode = {
    IsChallengeModeActive = function() return challengeActive end,
}
if challengeMode then
    -- Challenge completion also restores the QR UI; this payload-only fixture
    -- does not render it, but must provide its normal frame methods.
    local noop = function() end
    local originalCreateFrame = CreateFrame
    CreateFrame = function(...)
        local frame = originalCreateFrame(...)
        frame.SetIgnoreParentScale = noop
        frame.SetClampedToScreen = noop
        frame.ClearAllPoints = noop
        frame.SetMouseClickEnabled = noop
        frame.SetMouseMotionEnabled = noop
        frame.GetWidth = function() return 64 end
        local originalCreateTexture = frame.CreateTexture
        frame.CreateTexture = function(...)
            local texture = originalCreateTexture(...)
            texture.SetAllPoints = noop
            return texture
        end
        return frame
    end
    UIParent.GetWidth = function() return 1920 end
    UIParent.GetHeight = function() return 1080 end
end

local groupCount = 5
GetNumGroupMembers = function() return groupCount end
C_PaperDollInfo.GetInspectItemLevel = function(unit)
    local data = env.unit_data[unit]
    return data and data.ilvl or 0
end

env.unit_data.party1.class = "PRIEST"
env.unit_data.party1.classID = 5
env.unit_data.party1.specID = 256
env.unit_data.party1.role = "NONE"
env.unit_data.party1.ilvl = 704.4

local harness = env.load_addon()
local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "+16 Fixture Halls",
    comment = "bring kicks",
}

local function WritePayload(payload)
    for i = 1, #payload do
        io.write(string.format("%02x", string.byte(payload, i)))
    end
    io.write("\n")
end

assert(harness.StartSession)()
WritePayload(assert(harness.BuildPayload)(entry, {}, false))

if challengeMode then
    challengeActive = true
    assert(harness.FireEvent)("CHALLENGE_MODE_START")
    assert(harness.QRTransportState().challengeDormant,
        "challenge start did not enter dormancy")
else
    env.unit_data.party1 = nil
    groupCount = 4
    assert(harness.FireEvent)("GROUP_ROSTER_UPDATE")
end

env.unit_data.party1 = {
    name = "Friend",
    realm = "Realm",
    guid = "Party-1",
    class = "PRIEST",
    classID = 5,
    specID = 258,
    role = "NONE",
    ilvl = 798.6,
}
groupCount = 5
if challengeMode then
    -- No roster/spec notification is delivered while those events are paused.
    challengeActive = false
    assert(harness.FireEvent)("CHALLENGE_MODE_COMPLETED")
    assert(not harness.QRTransportState().challengeDormant,
        "challenge completion did not leave dormancy")
else
    assert(harness.FireEvent)("GROUP_ROSTER_UPDATE")
end

WritePayload(assert(harness.BuildPayload)(entry, {}, false))
