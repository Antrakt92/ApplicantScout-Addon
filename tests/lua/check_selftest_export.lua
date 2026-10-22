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
local reject_all_report_text = false
local reject_non_ascii = false
local reject_everything = false
local invalid_native = "[%z\1-\8\11\12\14-\31\255]"
local function escape_invalid(text)
    return (text:gsub(invalid_native, function(char)
        return string.format("\\%03d", string.byte(char))
    end))
end
local native_font_missing = arg and arg[1] == "font-missing"
GameFontHighlightSmall = {}
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
    f.SetPoint = function(self, ...) self.__point = { ... } end
    f.SetJustifyV = function(self, justify) self.__justifyV = justify end
    f.SetVerticalScroll = function(self, value) self.__verticalscroll = value end
    f.SetFrameStrata = function() end
    f.SetAlpha = function(self, alpha) self.__alpha = alpha end
    f.SetTextColor = function(self, ...) self.__color = { ... } end
    f.SetClampedToScreen = function() end
    f.EnableMouse = function() end
    f.SetBackdrop = function() end
    f.SetBackdropColor = function() end
    f.SetBackdropBorderColor = function() end
    f.SetScript = function(self, ev, fn) self.__scripts[ev] = fn end
    f.Show = function(self) self.__shown = true end
    f.Hide = function(self) self.__shown = false end
    f.IsShown = function(self) return self.__shown end
    f.IsVisible = function(self) return self.__shown end
    f.RegisterEvent = function() end
    f.UnregisterAllEvents = function() end
    f.__labels = {}
    f.CreateFontString = function()
        local label = {
            SetPoint = function() end,
            SetSize = function() end,
            SetJustifyH = function() end,
            SetJustifyV = function() end,
            SetText = function(self, text) self.__text = text end,
        }
        f.__labels[#f.__labels + 1] = label
        return label
    end
    f.SetScrollChild = function(self, child) self.__scrollchild = child end
    f.SetMultiLine = function() end
    f.SetFontObject = function(self, font) self.__font = font end
    f.GetFont = function(self)
        if self.__fontPath then return self.__fontPath, self.__fontSize, "" end
        if not native_font_missing and self.__font == GameFontHighlightSmall then
            return "Fonts\\ARIALN.TTF", 11, ""
        end
    end
    f.SetFont = function(self, path, size) self.__fontPath, self.__fontSize = path, size end
    f.GetText = function(self) return self.__text end
    f.SetWidth = function() end
    f.SetHeight = function(self, height) self.__height = height end
    f.SetAutoFocus = function() end
    f.SetMaxLetters = function(self, limit) self.__maxletters = limit end
    f.SetText = function(self, text)
        if reject_everything or text:find(invalid_native) or (reject_non_ascii and text:find("[\128-\255]"))
            or (reject_all_report_text and not text:find("Report display failed", 1, true)) then
            self.__text = ""
        else
            self.__text = self.__maxletters and text:sub(1, self.__maxletters) or text
        end
    end
    f.SetCursorPosition = function() end
    f.SetFocus = function() end
    f.HighlightText = function(self) self.__highlighted = true end
    f.ClearFocus = function() end
    frames[#frames + 1] = f
    return f
end
CreateFrame = function(_kind, _name, parent)
    local frame = stub_frame()
    frame.__parent = parent
    return frame
end

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
        if f.__shown and f.__parent == UIParent then out[#out + 1] = f end
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

-- Detailed status shares the copy panel without overwriting the saved selftest.
local saved_report = ApplicantScoutSelfTest
local selftest_text = box_text()
captured = {}
SlashCmdList.APSCOUT("status diag")
assert(#captured <= 2, "diagnostics flooded chat instead of the copy window")
assert(#shown_panels() == 1, "diagnostics did not open the shared copy panel")
local diagnostic_text = box_text()
assert(diagnostic_text:find("roster inspect batch:", 1, true),
    "copy report omitted nested inspect diagnostics")
assert(diagnostic_text:find("listing cache decision:", 1, true),
    "copy report omitted nested listing diagnostics")
assert(not diagnostic_text:find("|cff", 1, true), "copy report retained chat colors")
assert(ApplicantScoutSelfTest == saved_report, "diagnostics replaced saved selftest")
captured = {}
run_timers()
assert(contains(captured, "copy UI: bytes="), "diagnostics omitted its bounded presentation trace")
assert(not contains(captured, "Friend") and not contains(captured, "roster inspect batch:"),
    "presentation trace leaked report content or character identity")
for _, f in ipairs(frames) do
    if f.__scrollchild then
        assert(f.__shown and f.__scrollchild.__shown,
            "diagnostic scroll viewport or edit box remains hidden")
        assert(f.__scrollchild.__font == GameFontHighlightSmall,
            "copy text did not receive the native FontObject")
        assert(f.__scrollchild.__alpha == 1 and f.__scrollchild.__color[4] == 1,
            "copy text is transparent")
        assert(f.__scrollchild.__point and f.__scrollchild.__point[1] == "TOPLEFT"
            and f.__scrollchild.__point[2] == f,
            "copy text has no top-left anchor in its scroll viewport")
        assert(f.__scrollchild.__justifyV == "TOP",
            "tall diagnostic copy text is vertically centered below the viewport")
        assert(f.__verticalscroll == 0, "fresh diagnostic report did not reset scroll")
        local line_count = 0
        for _ in diagnostic_text:gmatch("[^\n]+") do line_count = line_count + 1 end
        assert(f.__scrollchild:GetText() == diagnostic_text and line_count > 50,
            "diagnostic copy readback lost report lines")
        f.__scrollchild.__scripts.OnTextChanged(f.__scrollchild, true)
        assert(f.__scrollchild.__text == diagnostic_text,
            "editing diagnostics restored the wrong report")
    end
end
local originalGetCVar = GetCVar
GetCVar = function(name)
    if name == "screenshotFormat" then return string.rep("x", 18000) .. "REPORT-END" end
    return originalGetCVar(name)
end
SlashCmdList.APSCOUT("status diag")
GetCVar = originalGetCVar
assert(#box_text() > 18000 and box_text():find("REPORT-END", 1, true),
    "copy window truncated a diagnostic report above the old text limit")
-- Unknown group API values must not masquerade as a confirmed solo count.
local savedGroupCount, savedSecretCheck = GetNumGroupMembers, issecretvalue
local secretCount = {}
issecretvalue = function(value) return value == secretCount end
for _, readCount in ipairs({
    function() return secretCount end,
    function() error("temporary group API failure") end,
}) do
    GetNumGroupMembers = readCount
    SlashCmdList.APSCOUT("status diag")
    assert(box_text():find("group members: unavailable", 1, true),
        "unreadable group count was reported as zero")
end
GetNumGroupMembers = function() return 0 end
SlashCmdList.APSCOUT("status diag")
assert(box_text():find("group members: 0", 1, true), "confirmed solo count was lost")
GetNumGroupMembers, issecretvalue = savedGroupCount, savedSecretCheck

-- Model native rejection at the boundary for group-only raw listing fields.
local oldHas, oldEntry = C_LFGList.HasActiveEntryInfo, C_LFGList.GetActiveEntryInfo
local oldCount = GetNumGroupMembers
GetNumGroupMembers = function() return 3 end
C_LFGList.HasActiveEntryInfo = function() return true end
local rawComment = ""
C_LFGList.GetActiveEntryInfo = function()
    return { activityIDs = {}, name = "group|title", comment = rawComment }
end
for _, clientAPI in ipairs({ true, false }) do
    C_StringUtil = clientAPI and { EscapeDecimalNonPrintables = escape_invalid } or nil
    for _, byte in ipairs({ 0, 31, 255 }) do
        rawComment = "BEGIN" .. string.char(byte) .. "END"
        SlashCmdList.APSCOUT("status diag")
        assert(box_text():find("BEGIN" .. string.format("\\%03d", byte) .. "END", 1, true),
            "group diagnostic rejected/lost raw byte " .. byte)
        assert(box_text():find("group\\124title", 1, true), "raw UI markup was not literalized")
        assert(box_text():find("listing cache decision:", 1, true), "encoding lost report tail")
    end
end
-- A native rejection despite sanitization retries exactly one ASCII form.
C_StringUtil = { EscapeDecimalNonPrintables = escape_invalid }
rawComment = "valid UTF8 " .. string.char(195, 169)
SlashCmdList.APSCOUT("status diag")
assert(box_text():find(string.char(195, 169), 1, true), "client sanitizer damaged valid UTF-8")
reject_non_ascii = true
SlashCmdList.APSCOUT("status diag")
assert(box_text():find("\\195\\169", 1, true), "native rejection did not recover ASCII bytes")
reject_non_ascii = false
-- Failure after both representations must leave an explicit visible error.
reject_all_report_text = true
SlashCmdList.APSCOUT("status diag")
assert(box_text():find("Report display failed", 1, true), "persistent rejection left a blank window")
reject_all_report_text = false
reject_everything = true
SlashCmdList.APSCOUT("status diag")
run_timers()
local visibleFailure = false
for _, frame in ipairs(frames) do
    -- FontStrings below are recorded independently of the rejecting EditBox.
    for _, label in ipairs(frame.__labels or {}) do
        if (label.__text or ""):find("Report display failed", 1, true) then visibleFailure = true end
    end
end
assert(visibleFailure, "rejecting every EditBox write left no independent visible error")
reject_everything = false
-- Deferred clearing on Show/next frame also gets one bounded recovery.
SlashCmdList.APSCOUT("status diag")
for _, frame in ipairs(frames) do
    if frame.__scrollchild then frame.__scrollchild.__text = "" end
end
run_timers()
assert(box_text() ~= "" and box_text():find("listing cache decision:", 1, true),
    "post-show native clearing was not recovered")
C_StringUtil = nil
C_LFGList.HasActiveEntryInfo, C_LFGList.GetActiveEntryInfo = oldHas, oldEntry
GetNumGroupMembers = oldCount

run_selftest("show")
assert(box_text() == selftest_text, "selftest show did not restore its own report")
click_all()
in_combat = true
captured = {}
SlashCmdList.APSCOUT("status diag")
assert(#shown_panels() == 0, "diagnostic window opened in combat")
assert(#captured <= 2 and contains(captured, "deferred"),
    "combat diagnostic request lost its short deferral hint")
in_combat = false
run_timers()
assert(#shown_panels() == 1, "diagnostic window did not open after combat")
assert(box_text():find("roster inspect batch:", 1, true),
    "deferred diagnostic request reopened selftest instead")

print = real_print
print("ok selftest-export lines=" .. #wlines)
