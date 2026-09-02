local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local mode = assert(arg[1], "pause mode required")
assert(mode == "disabled" or mode == "reenable-in-challenge"
       or mode == "resume-disabled", "unsupported pause mode")

local memberCount = 2
local secretGUID = {}
local partyGUIDs = { party1 = "Party-A" }
local guidReads, groupReads, sent = 0, 0, 0
local challengeActive = false
local scheduled = {}
local fixturePrint = print
print = function() end

GetNumGroupMembers = function()
    groupReads = groupReads + 1
    return memberCount
end
UnitGUID = function(unit)
    guidReads = guidReads + 1
    return partyGUIDs[unit] or ""
end
issecretvalue = function(value) return value == secretGUID end
IsInGroup = function() return false end -- keep unrelated key-provider work idle
C_ChallengeMode = { IsChallengeModeActive = function() return challengeActive end }
C_Timer.After = function(delay, callback)
    scheduled[#scheduled + 1] = { delay = delay, callback = callback }
end
C_ChatInfo = {
    InChatMessagingLockdown = function() return false end,
    SendChatMessage = function() sent = sent + 1 end,
}
ApplicantScoutDB = {
    enabled = true,
    autoHiGreetNewPartyMembers = true,
    autoHiMessage = "hi",
}

-- Challenge exit creates the ordinary QR container; no QR encoding is needed.
local noop = function() end
local createFrame = CreateFrame
CreateFrame = function(...)
    local frame = createFrame(...)
    frame.SetIgnoreParentScale = noop
    frame.SetClampedToScreen = noop
    frame.ClearAllPoints = noop
    frame.SetUserPlaced = noop
    frame.GetWidth = function() return 64 end
    frame.GetHeight = function() return 64 end
    local createTexture = frame.CreateTexture
    frame.CreateTexture = function(...)
        local texture = createTexture(...)
        texture.SetAllPoints = noop
        return texture
    end
    return frame
end
UIParent.GetWidth = function() return 1920 end
UIParent.GetHeight = function() return 1080 end

local function countTimers(delay)
    local count = 0
    for _, timer in ipairs(scheduled) do
        if timer.delay == delay then count = count + 1 end
    end
    return count
end
local function takeTimer(delay)
    for index, timer in ipairs(scheduled) do
        if timer.delay == delay then
            table.remove(scheduled, index)
            return timer.callback
        end
    end
    error("missing timer at delay " .. tostring(delay))
end
local function assertNoTrackingWork(action, label)
    local oldGUIDReads, oldGroupReads = guidReads, groupReads
    local oldTimerCount = #scheduled
    action()
    assert(guidReads == oldGUIDReads and groupReads == oldGroupReads,
        label .. " read party identities while Auto Hi was paused")
    assert(#scheduled == oldTimerCount,
        label .. " scheduled background work while Auto Hi was paused")
end

local harness = env.load_addon()
harness.SyncAutoHiInitialGroupState()
partyGUIDs.party1 = secretGUID
harness.ScheduleAutoHiForNewPartyMembers()
local staleSample = takeTimer(0.5)

if mode ~= "disabled" then
    challengeActive = true
    harness.FireEvent("CHALLENGE_MODE_START")
end
harness.SetEnabled(false)
scheduled = {}
if mode == "reenable-in-challenge" then
    assertNoTrackingWork(function() harness.SetEnabled(true) end, "enable in M+")
elseif mode == "resume-disabled" then
    challengeActive = false
    harness.FireEvent("CHALLENGE_MODE_COMPLETED")
    assert(countTimers(0.5) == 0,
        "challenge exit started Auto Hi sampling while the addon remained disabled")
end

assertNoTrackingWork(harness.SyncAutoHiInitialGroupState, "baseline sync")
assertNoTrackingWork(harness.PrimeAutoHiPartyMembers, "baseline prime")
assertNoTrackingWork(harness.ScheduleAutoHiForNewPartyMembers, "new-member sample")
assertNoTrackingWork(staleSample, "retired sample callback")

-- Group events may update transport bookkeeping, but must not restart Auto Hi.
harness.FireEvent("GROUP_ROSTER_UPDATE")
harness.FireEvent("GROUP_LEFT")
assert(countTimers(0.5) == 0 and countTimers(5) == 0 and countTimers(10) == 0,
    "group events scheduled Auto Hi timers while paused")
assert(sent == 0, "paused Auto Hi sent a greeting")
if mode == "reenable-in-challenge" then
    local state = harness.QRTransportState()
    assert(state.challengeDormant and not state.scanTickerActive,
        "manual enable woke the M+ scanner")
end

-- Resume adopts the current party without greeting players who joined while
-- paused. The next genuine join still produces exactly one greeting.
partyGUIDs.party1 = "Party-A"
partyGUIDs.party2 = "Party-B"
memberCount = 3
if mode == "reenable-in-challenge" then
    challengeActive = false
    harness.FireEvent("CHALLENGE_MODE_COMPLETED")
else
    harness.SetEnabled(true)
end
assert(countTimers(0.5) == 0 and countTimers(5) == 0 and countTimers(10) == 0,
    "resume greeted or resampled the complete existing party")
partyGUIDs.party3 = "Party-C"
memberCount = 4
harness.ScheduleAutoHiForNewPartyMembers()
harness.ScheduleAutoHiForNewPartyMembers()
assert(countTimers(10) == 1, "post-resume join was lost or scheduled twice")
assertNoTrackingWork(staleSample, "retired callback after resume")
takeTimer(10)()
assert(sent == 1, "post-resume join did not send exactly one greeting")

fixturePrint("ok auto-hi-tracking-pause mode=" .. mode .. " resumed-greetings=1")
