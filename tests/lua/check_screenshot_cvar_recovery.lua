local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local mode = arg and arg[1] or ""
assert(mode == "idle" or mode == "active" or mode == "logout",
    "unsupported recovery mode")

local cvars = {
    screenshotFormat = "jpg",
    screenshotQuality = "8",
}
local writes = {}
local timers = {}

GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value)
    cvars[name] = tostring(value)
    writes[#writes + 1] = { name = name, value = tostring(value) }
end
C_Timer.After = function(_delay, callback)
    timers[#timers + 1] = callback
end
print = function() end

ApplicantScoutDB = {
    enabled = mode == "active" or mode == "logout",
    debug = false,
    priorScreenshotQuality = mode == "logout" and nil
        or (mode == "active" and 3.5 or "not-a-quality"),
    priorScreenshotFormat = mode == "logout" and nil
        or (mode == "active" and {} or "bmp"),
}

local harness = env.load_addon()
if mode == "logout" then
    UIParent.GetWidth = function() return 1280 end
    UIParent.GetHeight = function() return 1080 end
    UIParent.GetLeft = function() return 0 end
    UIParent.GetTop = function() return 1080 end
    harness.SetQRFrameForTests({
        GetLeft = function() return 321 end,
        GetTop = function() return 654 end,
        GetWidth = function() return 64 end,
        ClearAllPoints = function() end,
        SetPoint = function() end,
    })

    local function run_logout_case(userChanged)
        cvars.screenshotQuality = "3"
        cvars.screenshotFormat = "png"
        writes = {}
        timers = {}
        ApplicantScoutDB.priorScreenshotQuality = nil
        ApplicantScoutDB.priorScreenshotFormat = nil

        local leaseGeneration = harness.AcquireScreenshotCVarLease()
        harness.ReleaseScreenshotCVarLease(leaseGeneration, 0.05)
        assert(cvars.screenshotQuality == "8"
               and cvars.screenshotFormat == "jpg",
            "capture did not acquire the screenshot CVar lease")
        assert(ApplicantScoutDB.priorScreenshotQuality == 3
               and ApplicantScoutDB.priorScreenshotFormat == "png",
            "capture did not persist the prior screenshot CVars")
        assert(#timers == 1, "capture did not queue one delayed release")

        if userChanged then
            cvars.screenshotQuality = "9"
            cvars.screenshotFormat = "tga"
        end
        local writesBeforeLogout = #writes
        harness.FireEvent("PLAYER_LOGOUT")
        assert(ApplicantScoutDB.qrFramePosition.x == 321
               and ApplicantScoutDB.qrFramePosition.y == -426,
            "logout did not persist the current QR frame position")

        if userChanged then
            assert(#writes == writesBeforeLogout,
                "logout overwrote user-changed screenshot CVars")
            assert(cvars.screenshotQuality == "9"
                   and cvars.screenshotFormat == "tga",
                "logout did not preserve user-changed screenshot CVars")
        else
            assert(#writes == writesBeforeLogout + 2,
                "logout did not synchronously restore both owned CVars")
            assert(cvars.screenshotQuality == "3"
                   and cvars.screenshotFormat == "png",
                "logout did not restore the pre-capture screenshot CVars")
        end
        assert(ApplicantScoutDB.priorScreenshotQuality == nil
               and ApplicantScoutDB.priorScreenshotFormat == nil,
            "logout did not clear the persisted screenshot CVar stash")

        local writesAfterLogout = #writes
        while #timers > 0 do
            table.remove(timers, 1)()
        end
        assert(#writes == writesAfterLogout,
            "stale delayed release wrote CVars after logout invalidation")
    end

    run_logout_case(false)
    run_logout_case(true)
    io.write("ok screenshot-cvar-recovery mode=" .. mode .. "\n")
    return
end

if mode == "active" then
    harness.StartSession()
end

SlashCmdList.APSCOUT("off")
if mode == "active" then
    assert(#writes == 0, "active disable restored CVars before terminal clear delay")
    local guard = 0
    while #timers > 0 do
        guard = guard + 1
        assert(guard < 100, "CVar recovery timer queue did not settle")
        table.remove(timers, 1)()
    end
end

assert(#writes == 0, "malformed CVar stash wrote a global setting")
assert(cvars.screenshotQuality == "8", "malformed quality stash changed CVar")
assert(cvars.screenshotFormat == "jpg", "malformed format stash changed CVar")
assert(ApplicantScoutDB.priorScreenshotQuality == nil, "quality stash was not cleared")
assert(ApplicantScoutDB.priorScreenshotFormat == nil, "format stash was not cleared")

if mode == "idle" then
    local function restore_idle(quality, format)
        cvars.screenshotQuality = "8"
        cvars.screenshotFormat = "jpg"
        writes = {}
        ApplicantScoutDB.priorScreenshotQuality = quality
        ApplicantScoutDB.priorScreenshotFormat = format
        SlashCmdList.APSCOUT("off")
    end

    restore_idle("3", "PNG")
    assert(cvars.screenshotQuality == "3", "legal quality stash was not restored")
    assert(cvars.screenshotFormat == "png", "legal format stash was not normalized")

    restore_idle(1, "TGA")
    assert(cvars.screenshotQuality == "1", "quality lower boundary was not restored")
    assert(cvars.screenshotFormat == "tga", "TGA format was not restored")

    restore_idle(10, "JPEG")
    assert(cvars.screenshotQuality == "10", "quality upper boundary was not restored")
    assert(cvars.screenshotFormat == "jpeg", "JPEG format was not restored")

    restore_idle(0, nil)
    assert(#writes == 0 and cvars.screenshotQuality == "8",
        "quality below legal range wrote a CVar")
    restore_idle(11, nil)
    assert(#writes == 0 and cvars.screenshotQuality == "8",
        "quality above legal range wrote a CVar")

    cvars.screenshotQuality = "9"
    cvars.screenshotFormat = "tga"
    writes = {}
    ApplicantScoutDB.priorScreenshotQuality = "3"
    ApplicantScoutDB.priorScreenshotFormat = "png"
    SlashCmdList.APSCOUT("off")
    assert(#writes == 0, "restore overwrote user-changed screenshot CVars")
    assert(cvars.screenshotQuality == "9", "user quality choice was not preserved")
    assert(cvars.screenshotFormat == "tga", "user format choice was not preserved")
    assert(ApplicantScoutDB.priorScreenshotQuality == nil,
        "owned quality stash was not cleared after user override")
    assert(ApplicantScoutDB.priorScreenshotFormat == nil,
        "owned format stash was not cleared after user override")
end

io.write("ok screenshot-cvar-recovery mode=" .. mode .. "\n")
