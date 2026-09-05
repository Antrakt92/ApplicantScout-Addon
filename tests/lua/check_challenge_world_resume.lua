local unavailable = assert(arg[1], "unavailable API mode required")
local outcome = arg[2] or "ended"
assert(unavailable == "nil" or unavailable == "error"
       or unavailable == "secret" or unavailable == "missing", "unsupported API mode")
assert(outcome == "ended" or outcome == "unreadable"
       or outcome == "active" or outcome == "new-start", "unsupported outcome")
local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
ApplicantScoutDB = nil
ApplicantScoutQRFrame = nil
PVEFrame = nil
GetNumGroupMembers = function() return 0 end
IsInGroup = function() return false end

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

local now, pending, callbacks = 0, {}, 0
GetTime = function() return now end
C_Timer.After = function(delay, callback)
    pending[#pending + 1] = { at = now + delay, callback = callback }
end
local function advance(target)
    while true do
        table.sort(pending, function(left, right) return left.at < right.at end)
        if not pending[1] or pending[1].at > target then break end
        local timer = table.remove(pending, 1)
        now = timer.at
        callbacks = callbacks + 1
        assert(callbacks <= 20, "world resume scheduled unbounded timer work")
        timer.callback()
    end
    now = target
end

local apiState, apiReads = true, 0
local secret = {}
issecretvalue = function(value) return value == secret end
local function activityAPI()
    apiReads = apiReads + 1
    if apiState == "error" then error("challenge state temporarily unavailable") end
    if apiState == "secret" then return secret end
    return apiState
end
C_ChallengeMode = { IsChallengeModeActive = activityAPI }
local harness = env.load_addon()
harness.FireEvent("ADDON_LOADED", "ApplicantScout")
harness.FireEvent("CHALLENGE_MODE_START")
assert(harness.QRTransportState().challengeDormant,
    "active challenge did not stop optional background work")
local startsBefore = harness.QRTransportState().scanTickerStartCount

harness.FireEvent("PLAYER_LEAVING_WORLD")
if unavailable == "missing" then
    C_ChallengeMode.IsChallengeModeActive = nil
elseif unavailable == "nil" then
    apiState = nil
else
    apiState = unavailable
end
harness.FireEvent("PLAYER_ENTERING_WORLD")
harness.FireEvent("LOADING_SCREEN_DISABLED")
advance(0.35)
assert(harness.QRTransportState().challengeDormant,
    "an unreadable arrival must retain trusted activity suppression")

-- No second world-arrival/end event follows a delayed API update. The scanner
-- is intentionally stopped, so the world edge itself must own bounded recovery.
if outcome ~= "unreadable" then
    apiState = outcome == "active"
    C_ChallengeMode.IsChallengeModeActive = activityAPI
end
if outcome == "new-start" then
    -- A new start owns the transition even before the API catches up.
    harness.FireEvent("CHALLENGE_MODE_START")
end
local readsBeforeRetry = apiReads
advance(5)
local resumed = harness.QRTransportState()
if outcome == "ended" then
    assert(not resumed.challengeDormant and resumed.scanTickerActive,
        "challenge dormancy never recovered after the arrival API became inactive")
    assert(not resumed.gameplayChallengeActive and not resumed.suppressedByGameplay,
        "the new world's clean inactive state did not release gameplay suppression")
    assert(resumed.scanTickerStartCount == startsBefore + 1,
        "world recovery must restart exactly one scanner")
else
    assert(resumed.challengeDormant and not resumed.scanTickerActive,
        "world recovery must not wake an active or unconfirmed challenge")
    assert(resumed.scanTickerStartCount == startsBefore,
        "suppressed world recovery restarted the scanner")
    assert(apiReads - readsBeforeRetry <= 4,
        "world recovery exceeded the existing four-attempt budget")
    if outcome == "new-start" then
        assert(apiReads == readsBeforeRetry, "a new challenge must cancel stale retries")
    end
end
local settledReads = apiReads
advance(60)
assert(apiReads == settledReads, "world recovery must not leave periodic API polling")
print("ok challenge-world-resume unavailable=" .. unavailable .. " outcome=" .. outcome)
