local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local mode = arg and arg[1] or "expiry"
local now = 1000
GetTime = function() return now end
GetNumGroupMembers = function() return 0 end
IsInRaid = function() return false end
ApplicantScoutDB = { enabled = true }
local harness = env.load_addon({})
local memberName = "First-Realm"
local memberSpec = 63
local calls = 0
harness.SetApplicantTransportAdapters(
    function(id)
        return id, { applicantID = id, applicationStatus = "applied", numMembers = 1 }, id
    end,
    function()
        calls = calls + 1
        return true, memberName, "MAGE", 700, "DAMAGER", 2500, memberSpec
    end
)
local entry = { activityIDs = {401}, questID = 0, name = "Cache fixture" }
C_LFGList.HasActiveEntryInfo = function() return true end
C_LFGList.GetActiveEntryInfo = function() return entry end
env.start_session_quietly(harness)
harness.CheckSessionTransition(true)
local first = harness.BuildPayload(entry, {1}, false)
assert(first:find(memberName, 1, true))
memberName = "Second-Realm"
memberSpec = 64
if mode == "expiry" then
    now = now + 0.5
    assert(harness.BuildPayload(entry, {1}, false) == first,
        "normal redundant capture stopped reusing fresh member information")
    assert(calls == 1, "fresh member cache re-read the API")
    now = now + 1.5
elseif mode == "reset" then
    local savedPrint = print
    print = function() end
    SlashCmdList.APSCOUT("reset")
    print = savedPrint
elseif mode == "session" then
    harness.EndSession()
    env.start_session_quietly(harness)
elseif mode == "listing" then
    entry = { activityIDs = {402}, questID = 0, name = "Replacement listing" }
    harness.CheckSessionTransition(true)
else
    error("unknown cache fixture mode")
end
local refreshed = harness.BuildPayload(entry, {1}, false)
assert(refreshed:find(memberName, 1, true),
    "stale applicant identity survived " .. mode)
assert(not refreshed:find("First-Realm", 1, true),
    "old applicant identity leaked after " .. mode)
assert(calls == 2, "refresh did not re-read exactly one member")
assert(harness.BuildPayload(entry, {1}, false) == refreshed and calls == 2,
    "refreshed cache was not reusable")
print("ok applicant-cache-freshness " .. mode)
