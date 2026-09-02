local activity = assert(arg[1], "activity required")
local unavailable = assert(arg[2], "unavailable API mode required")
local config = assert(({
    challenge = { start = "CHALLENGE_MODE_START", stop = "CHALLENGE_MODE_COMPLETED", field = "gameplayChallengeActive" },
    combat = { start = "PLAYER_REGEN_DISABLED", stop = "PLAYER_REGEN_ENABLED", field = "gameplayCombatActive" },
    encounter = { start = "ENCOUNTER_START", stop = "ENCOUNTER_END", field = "gameplayEncounterActive" },
})[activity], "unsupported activity")
assert(unavailable == "nil" or unavailable == "error"
       or unavailable == "secret" or unavailable == "missing", "unsupported API mode")

local cases = 0
for _, evidence in ipairs({ "confirmed-event", "event-only", "api-only", "inactive" }) do
    local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
    ApplicantScoutDB = nil
    ApplicantScoutQRFrame = nil
    C_InstanceEncounter = nil
    C_ChallengeMode = nil
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

    local pending = {}
    C_Timer.After = function(_, callback) pending[#pending + 1] = callback end
    local function drain()
        local callbacks = 0
        while #pending > 0 do
            callbacks = callbacks + 1
            assert(callbacks <= 20, "world transition scheduled unbounded recovery")
            table.remove(pending, 1)()
        end
    end

    local secret = {}
    issecretvalue = function(value) return value == secret end
    local apiState = evidence == "confirmed-event" or evidence == "api-only"
    local function activityAPI()
        if apiState == "error" then error("injected unavailable activity API") end
        if apiState == "secret" then return secret end
        return apiState
    end
    local function setAPI(api)
        if activity == "challenge" then
            C_ChallengeMode = { IsChallengeModeActive = api }
        elseif activity == "encounter" then
            C_InstanceEncounter = { IsEncounterInProgress = api }
        else
            InCombatLockdown = api
        end
    end
    setAPI(activityAPI)

    local harness = env.load_addon()
    harness.FireEvent("ADDON_LOADED", "ApplicantScout")
    if evidence == "confirmed-event" or evidence == "event-only" then
        harness.FireEvent(config.start)
    end
    local wasActive = evidence ~= "inactive"
    assert(harness.QRTransportState()[config.field] == wasActive,
        "fixture did not establish its initial activity evidence")

    local tickerStarts = harness.QRTransportState().scanTickerStartCount
    if unavailable == "nil" then
        apiState = nil
    elseif unavailable == "missing" then
        setAPI(nil)
    else
        apiState = unavailable
    end

    -- World arrival and loading-screen completion are not activity end events.
    for _ = 1, 2 do
        harness.FireEvent("PLAYER_LEAVING_WORLD")
        harness.FireEvent("PLAYER_ENTERING_WORLD")
        harness.FireEvent("LOADING_SCREEN_DISABLED")
        drain()
        local state = harness.QRTransportState()
        assert(state[config.field] == wasActive,
            activity .. "/" .. evidence .. "/" .. unavailable
                .. ": world transition discarded trusted activity state")
        assert(state.suppressedByGameplay == wasActive,
            "loading-screen completion changed activity suppression")
        if activity == "challenge" and wasActive then
            assert(state.challengeDormant and not state.scanTickerActive
                   and not state.challengeDormantOptionalEventsRegistered,
                "unreadable world transition woke optional M+ work")
            assert(state.scanTickerStartCount == tickerStarts,
                "unreadable world transition restarted the scanner")
        end
    end

    -- A clean false in the new world clears even an unconfirmed old start edge.
    apiState = false
    setAPI(activityAPI)
    harness.FireEvent("PLAYER_ENTERING_WORLD")
    local ended = harness.QRTransportState()
    assert(not ended[config.field] and not ended.suppressedByGameplay,
        "authoritative inactive world did not release suppression")
    assert(not ended.challengeDormant and ended.scanTickerActive,
        "authoritative inactive world did not restore the scanner")
    local resumedStarts = ended.scanTickerStartCount
    harness.FireEvent("PLAYER_ENTERING_WORLD")
    assert(harness.QRTransportState().scanTickerStartCount == resumedStarts,
        "repeated world arrival duplicated the scanner")
    drain()

    -- A matching end remains authoritative if the API is still unavailable.
    apiState = true
    harness.FireEvent(config.start)
    apiState = nil
    harness.FireEvent("PLAYER_ENTERING_WORLD")
    harness.FireEvent(config.stop)
    assert(not harness.QRTransportState()[config.field],
        "matching end did not clear the retained activity")
    drain()
    cases = cases + 1
end

print(string.format("ok gameplay-world-transition activity=%s unavailable=%s cases=%d",
    activity, unavailable, cases))
