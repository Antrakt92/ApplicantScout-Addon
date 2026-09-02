local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local pending = {}
local challengeReads = 0
C_ChallengeMode = {
    IsChallengeModeActive = function()
        challengeReads = challengeReads + 1
        return true
    end,
}
C_Timer.After = function(delay, callback)
    pending[#pending + 1] = { delay = delay, callback = callback }
end

local harness = env.load_addon()
harness.FireEvent("CHALLENGE_MODE_START")
assert(#pending == 0, "challenge start scheduled background recovery work")
assert(harness.QRTransportState().challengeDormant
       and not harness.QRTransportState().scanTickerActive,
    "active challenge did not stop the scanner")

harness.FireEvent("CHALLENGE_MODE_COMPLETED")
local retries = 0
local totalDelay = 0
while #pending > 0 do
    assert(#pending == 1, "challenge end queued parallel recovery checks")
    local nextCheck = table.remove(pending, 1)
    retries = retries + 1
    totalDelay = totalDelay + nextCheck.delay
    assert(retries <= 4, "challenge end recovery exceeded its bounded budget")
    nextCheck.callback()
end
assert(retries == 4 and totalDelay == 3.75,
    "challenge end recovery did not use the expected bounded backoff")
assert(harness.QRTransportState().challengeDormant
       and not harness.QRTransportState().scanTickerActive,
    "still-active API allowed transport to resume after retry exhaustion")

harness.FireEvent("CHALLENGE_MODE_RESET")
assert(#pending == 1, "challenge reset did not queue one recovery check")
local staleCheck = table.remove(pending, 1).callback
harness.FireEvent("CHALLENGE_MODE_START")
local readsBefore = challengeReads
staleCheck()
assert(challengeReads == readsBefore and #pending == 0,
    "old challenge recovery performed work after a new start event")

print("ok challenge-resume-retry bounded=4 stale-cancelled=1")
