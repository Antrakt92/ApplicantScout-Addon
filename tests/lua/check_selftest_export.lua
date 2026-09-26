local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

GetCVar = function(name)
    if name == "screenshotQuality" then return "8" end
    if name == "screenshotFormat" then return "jpg" end
    return nil
end

-- Recording frame stub for the copy window: the shared fixture stub has no
-- EditBox/ScrollFrame/Show semantics, so this check overrides CreateFrame
-- (globals resolve at call time) and C_Timer.After (captured, run manually
-- to model the deferred presentation path).
local frames = {}
local timers = {}
local in_combat = false
InCombatLockdown = function() return in_combat end
C_Timer.After = function(_delay, fn)
    timers[#timers + 1] = fn
end

local function stub_frame()
    local f = {
        __shown = false,
        __scripts = {},
        __text = nil,
        __highlighted = false,
    }
    f.SetSize = function() end
    f.SetPoint = function() end
    f.SetFrameStrata = function() end
    f.SetClampedToScreen = function() end
    f.EnableMouse = function() end
    f.SetBackdrop = function() end
    f.SetBackdropColor = function() end
    f.SetBackdropBorderColor = function() end
    f.SetScript = function(self, ev, fn) self.__scripts[ev] = fn end
    f.Show = function(self) self.__shown = true end
    f.Hide = function(self) self.__shown = false end
    f.IsShown = function(self) return self.__shown end
    f.RegisterEvent = function() end
    f.UnregisterAllEvents = function() end
    f.CreateFontString = function()
        return {
            SetPoint = function() end,
            SetSize = function() end,
            SetJustifyH = function() end,
            SetJustifyV = function() end,
            SetText = function() end,
        }
    end
    f.SetScrollChild = function(self, child) self.__scrollchild = child end
    f.SetMultiLine = function() end
    f.SetFontObject = function() end
    f.SetWidth = function() end
    f.SetHeight = function() end
    f.SetAutoFocus = function() end
    f.SetMaxLetters = function() end
    f.SetText = function(self, text) self.__text = text end
    f.SetCursorPosition = function() end
    f.SetFocus = function() end
    f.HighlightText = function(self) self.__highlighted = true end
    f.ClearFocus = function() end
    frames[#frames + 1] = f
    return f
end
CreateFrame = function() return stub_frame() end

ApplicantScoutDB = { enabled = true, debug = false }
ApplicantScoutSelfTest = nil

local harness = env.load_addon()
assert(type(harness.StartSession) == "function", "session harness is unavailable")
assert(type(SlashCmdList.APSCOUT) == "function", "slash dispatcher is unavailable")

local captured = {}
local real_print = print
print = function(message)
    captured[#captured + 1] = tostring(message)
end

local function run_selftest(argument)
    captured = {}
    if argument then
        SlashCmdList.APSCOUT("selftest " .. argument)
    else
        SlashCmdList.APSCOUT("selftest")
    end
    return captured
end

local function contains(lines, fragment)
    for _, line in ipairs(lines) do
        if string.find(line, fragment, 1, true) then return true end
    end
    return false
end

local function box_text()
    for _, f in ipairs(frames) do
        if f.__scrollchild and f.__scrollchild.__text then
            return f.__scrollchild.__text
        end
        if f.__text and string.find(f.__text, "ASCOUT1: v=1", 1, true) then
            return f.__text
        end
    end
    return nil
end

local function shown_panels()
    local out = {}
    for _, f in ipairs(frames) do
        if f.__shown then out[#out + 1] = f end
    end
    return out
end

local function click_all()
    for _, f in ipairs(frames) do
        local onclick = f.__scripts["OnClick"]
        if onclick then pcall(onclick) end
    end
end

local function run_timers()
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
end

-- show with no finished run stays a one-line control message.
local idle_show = run_selftest("show")
assert(#idle_show == 1, "idle show must print exactly one line")
assert(contains(idle_show, "no finished run yet"), "idle show lost the hint")

-- Stop with no active run stays a control message, never an export.
local idle_stop = run_selftest("stop")
assert(#idle_stop == 1, "idle stop must print exactly one line")
assert(contains(idle_stop, "no run active"), "idle stop lost the hint")

-- Unknown subcommand prints usage.
local bogus = run_selftest("frobnicate")
assert(#bogus == 1, "unknown arg must print exactly one line")
assert(contains(bogus, "[start|stop|show|cancel]"), "unknown arg lost the usage hint")

-- Start arms a run with one control line.
local started = run_selftest()
assert(#started == 1, "start must print exactly one line")
assert(contains(started, "started"), "start lost the started signal")
assert(ApplicantScoutSelfTest == nil, "start must not persist")

-- Finish out of combat: short chat, window opens with the full block.
run_selftest("start")
captured = {}
env.start_session_quietly(harness)
assert(#captured == 0, "quiet session start leaked print output")
local finished = run_selftest()
harness.EndSession()

assert(#finished == 6, "finish chat must be 6 lines, got " .. #finished)
assert(contains(finished, "finished"), "finish lost the summary line")
assert(contains(finished, "copy window opened"), "finish lost the copy hint")
assert(contains(finished, "/apscout selftest show"), "finish lost the reopen hint")
assert(not contains(finished, "ASCOUT1:"), "finish chat must not carry the export block")

local visible = shown_panels()
assert(#visible == 1, "copy window must open out of combat")
local text = box_text()
assert(text ~= nil, "copy window has no report text")
local wlines = {}
for line in string.gmatch(text, "[^\n]+") do wlines[#wlines + 1] = line end
assert(#wlines >= 40, "window block too small: " .. #wlines)
assert(#wlines <= 96, "window block exceeded cap: " .. #wlines)

local keys = {}
for index, line in ipairs(wlines) do
    local key, value = string.match(line, "^ASCOUT1: ([A-Za-z0-9-]+)=(.+)$")
    assert(key ~= nil, "window line " .. index .. " broke shape: " .. line)
    assert(string.find(value, "=", 1, true) == nil,
        "window line " .. index .. " value breaks parsing: " .. line)
    keys[key] = value
end

for _, required in ipairs({
    "v", "addon", "game", "build", "iface", "region",
    "enabled", "debug", "session", "session-gen",
    "scan-ticker", "poll-age", "shot-age", "snapshot", "delivery-sends",
    "transport", "shot-result", "shot-fail",
    "gameplay-suppressed", "suppress-reason", "interaction-defer",
    "qr-visible", "chat-lockdown",
    "inspect-pending", "inspect-age", "inspect-skipped", "inspect-exhausted",
    "payload-bytes", "payload-applicants", "payload-roster",
    "tex-pool", "qr-encode", "autohi", "libks", "leader-key",
    "encode-ok", "encode-bytes", "encode-version", "encode-ms", "encode-skip",
    "hooks", "term-clear-dispatch",
    "run-dur", "d-sends", "d-recoveries", "d-shot-fail", "done",
}) do
    assert(keys[required] ~= nil, "export lost required key: " .. required)
end

assert(keys["v"] == "1", "export version must be 1")
assert(keys["transport"] == "one-way", "transport must stay one-way")
assert(keys["session"] == "active", "export under session must say active")
assert(keys["done"] == "lines-" .. tostring(#wlines),
    "done line must carry the exact line count")

-- SavedVariable shape: separate SV, one last run, bounded report.
local sv = ApplicantScoutSelfTest
assert(type(sv) == "table", "selftest SV was not persisted")
assert(sv.version == 1, "selftest SV version must be 1")
assert(type(sv.finishedAt) == "number", "selftest SV finishedAt must be a number")
assert(type(sv.report) == "table", "selftest SV report must be a table")
assert(#sv.report == #wlines, "SV report must match the window block")
for index, line in ipairs(wlines) do
    assert(sv.report[index] == string.match(line, "^ASCOUT1: (.+)$"),
        "SV report line " .. index .. " differs from window export")
end

-- Secret-safety: no fixture identities, GUIDs, payload content, or keys.
local blob = text
for _, forbidden in ipairs({
    "Tankone", "Mageone", "Host", "Friend", "Healer", "Feral", "Ret",
    "Realm", "Player-", "secret", "payload=", "|c", "|H", "|T",
}) do
    assert(string.find(blob, forbidden, 1, true) == nil,
        "export leaked forbidden surface: " .. forbidden)
end

-- Closing the window hides it; show reopens the same last report.
click_all()
assert(#shown_panels() == 0, "close must hide the copy window")
local reshown = run_selftest("show")
assert(#reshown == 1, "show must print exactly one line")
assert(contains(reshown, "copy window opened"), "show lost the hint")
assert(#shown_panels() == 1, "show must reopen the window")
assert(box_text() == text, "show must present the same last report")

-- In combat: finish prints the short chat, defers the window, auto-opens after.
click_all()
run_timers()
timers = {}
in_combat = true
run_selftest("start")
local combat_finished = run_selftest()
assert(#combat_finished == 6, "combat finish chat must stay 6 lines")
assert(contains(combat_finished, "deferred"), "combat finish lost the deferral hint")
assert(contains(combat_finished, "/apscout selftest show"), "combat finish lost the reopen hint")
assert(#shown_panels() == 0, "window must stay hidden in combat")
assert(#timers >= 1, "deferred window must queue a presentation retry")
in_combat = false
run_timers()
assert(#shown_panels() == 1, "window must auto-open after combat")
assert(box_text() ~= nil, "auto-opened window has no report text")
local reopened = {}
for line in string.gmatch(box_text(), "[^\n]+") do reopened[#reopened + 1] = line end
assert(#reopened == #ApplicantScoutSelfTest.report, "auto-opened report size mismatch")
for index, line in ipairs(reopened) do
    assert(ApplicantScoutSelfTest.report[index] == string.match(line, "^ASCOUT1: (.+)$"),
        "auto-opened line " .. index .. " differs from SV")
end

-- show while deferred-but-combat reports deferral instead of opening.
click_all()
in_combat = true
run_selftest("start")
run_selftest()
assert(#shown_panels() == 0, "window must stay hidden in combat")
local combat_show = run_selftest("show")
assert(#combat_show == 1, "combat show must print exactly one line")
assert(contains(combat_show, "deferred"), "combat show lost the deferral hint")
assert(#shown_panels() == 0, "combat show must not open the window")
in_combat = false
run_timers()
assert(#shown_panels() == 1, "window must auto-open after combat")

-- Cancel drops the run without exporting or persisting.
click_all()
run_selftest("start")
local cancelled = run_selftest("cancel")
assert(#cancelled == 1, "cancel must print exactly one line")
assert(contains(cancelled, "cancelled"), "cancel lost the signal")

-- ApplicantScoutDB stays the addon's own store: no selftest keys in it.
assert(type(ApplicantScoutDB) == "table", "addon DB must stay a table")
assert(ApplicantScoutDB.ApplicantScoutSelfTest == nil,
    "selftest must not nest inside ApplicantScoutDB")
assert(ApplicantScoutDB.enabled == true, "selftest changed the enabled flag")
assert(ApplicantScoutDB.debug == false, "selftest changed the debug flag")

print = real_print
print("ok selftest-export lines=" .. #wlines)
