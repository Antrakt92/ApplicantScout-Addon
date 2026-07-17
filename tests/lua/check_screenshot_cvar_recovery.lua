local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local mode = arg and arg[1] or ""
assert(mode == "idle" or mode == "active", "unsupported recovery mode")

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
    enabled = mode == "active",
    debug = false,
    priorScreenshotQuality = mode == "active" and 3.5 or "not-a-quality",
    priorScreenshotFormat = mode == "active" and {} or "bmp",
}

local harness = env.load_addon()
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
