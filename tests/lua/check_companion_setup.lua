local scenario = assert(arg[1], "scenario required")
local clientLocale = arg[2] or "enUS"
local fallbackLocale = arg[2] or "ruRU"
local blockedFont = {ruRU = "ARIALN", frFR = "ARIALN", koKR = "2002", zhCN = "ARKai_T", zhTW = "arheiuhk_bd"}
local expectedFallback = {ruRU = "Fonts\\2002.TTF", frFR = "Fonts\\FRIZQT__.TTF",
    koKR = "Fonts\\K_Pagetext.ttf", zhCN = "Fonts\\ARKai_C.ttf", zhTW = "Fonts\\ARKai_T.ttf"}
GetLocale = function() return clientLocale end
if scenario == "locale-api-error" then GetLocale = function() error("unavailable") end end
if scenario == "locale-api-missing" then GetLocale = nil end
local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local frames, pending = {}, {}
local fontstrings = {}
local now = 1000
local fontColdUntil
local measuredHeight = 450
local combat = false
local challenge, encounter = false, false
InCombatLockdown = function() return combat end
C_ChallengeMode = { IsChallengeModeActive = function() return challenge end }
C_InstanceEncounter = { IsEncounterInProgress = function() return encounter end }
GetNumGroupMembers = function() return 0 end
IsInGroup = function() return false end
GetTime = function() return now end
C_Timer.After = function(delay, callback)
    pending[#pending + 1] = { due = now + delay, callback = callback }
end
local function koreanFont(path)
    return type(path) == "string" and (path:find("2002", 1, true) or path:find("K_Pagetext", 1, true))
end
local function widget()
    local frame = { scripts = {}, events = {}, shown = true, text = "", focused = false }
    local noop = function() end
    local methods = {
        RegisterEvent = function(self, event) self.events[event] = true end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        HookScript = function(self, name, fn) self.scripts[name] = fn end,
        Show = function(self) self.shown = true end,
        Hide = function(self)
            local wasShown = self.shown
            self.shown = false
            if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end,
        IsShown = function(self) return self.shown end,
        GetWidth = function(self) return self.width or 1920 end,
        GetHeight = function(self) return self.height or 1080 end,
        SetSize = function(self, width, height) self.width, self.height = width, height end,
        SetHeight = function(self, height) self.height = height end,
        SetScale = function(self, scale) self.scale = scale end,
        GetStringHeight = function()
            if scenario == "measurement-invalid" then return math.huge end
            if scenario == "measurement-error" then error("font not ready") end
            if scenario == "measurement-zero" then return 0 end
            if scenario == "measurement-negative" then return -1 end
            return measuredHeight
        end,
        SetScrollChild = function(self, child) self.child = child end,
        SetVerticalScroll = function(self, offset) self.offset = offset end,
        GetVerticalScroll = function(self) return rawget(self, "offset") or 0 end,
        GetEffectiveScale = function() return 1 end,
        GetFrameLevel = function() return 1 end,
        SetText = function(self, text) self.text = text end,
        GetText = function(self) return self.text end,
        SetFont = function(self, path, size, flags)
            if scenario == "font-all-missing" then return false end
            if scenario == "font-compatible-fallback" and path:find(blockedFont[fallbackLocale], 1, true) then return false end
            if (scenario == "font-missing" or scenario == "retry-interaction") and koreanFont(path) then return false end
            if scenario == "font-error" and koreanFont(path) then error("missing font") end
            if scenario == "font-partial" and koreanFont(path) and size == 14 then return false end
            self.font, self.fontSize, self.fontFlags = path, size, flags
            if scenario == "font-cold" and koreanFont(path) and not fontColdUntil then
                fontColdUntil = now + 0.4
            end
            if scenario == "font-nil-return" then return nil end
            return true
        end,
        GetFont = function(self)
            if scenario == "font-cold" and koreanFont(self.font) and now < fontColdUntil then return nil end
            if scenario == "font-false-success" and koreanFont(self.font) then
                return "Fonts\\FRIZQT__.TTF", self.fontSize, self.fontFlags
            end
            return self.font, self.fontSize, self.fontFlags
        end,
        SetFontObject = function(self, font) self.fontObject = font end,
        SetNormalFontObject = function(self, font) self.normalFont = font end,
        SetTextColor = function(self, r, g, b) self.color = {r, g, b} end,
        SetHighlightFontObject = function(self, font) self.highlightFont = font end,
        SetDisabledFontObject = function(self, font) self.disabledFont = font end,
        GetFontString = function(self)
            if not rawget(self, "fontstring") then self.fontstring = widget() end
            return self.fontstring
        end,
        SetFocus = function(self) self.focused = true end,
        ClearFocus = function(self) self.focused = false end,
        HighlightText = function(self) self.selected = true end,
        CreateTexture = function() return widget() end,
        CreateFontString = function()
            local fontstring = widget()
            fontstrings[#fontstrings + 1] = fontstring
            return fontstring
        end,
    }
    setmetatable(frame, { __index = function(_, key) return methods[key] or noop end })
    return frame
end
CreateFrame = function(kind, name, parent, template)
    local frame = widget()
    frame.kind, frame.name, frame.parent, frame.template = kind, name, parent, template
    frames[#frames + 1] = frame
    return frame
end
UIParent = widget()
UISpecialFrames = {}
if scenario == "small-display" then UIParent.width, UIParent.height = 500, 480 end
ApplicantScoutDB = scenario == "disabled" and {enabled = false, autoHiMessage = "hello"}
    or scenario == "dismissed" and {setupDismissed = true}
    or scenario == "corrupt" and {setupDismissed = {}}
    or {}
if scenario == "language-saved" then ApplicantScoutDB.setupLocale = "ruRU" end
if scenario == "language-invalid" then ApplicantScoutDB.setupLocale = {} end
if scenario == "language-invalid-string" then ApplicantScoutDB.setupLocale = "xxXX" end
if scenario == "font-compatible-fallback" then ApplicantScoutDB.setupLocale = fallbackLocale end
local harness = env.load_addon({})
local watcher = frames[#frames]
assert(watcher.events.PLAYER_LOGIN, "setup lifecycle watcher missing")
local function event(name)
    if scenario == "watcher-first" and watcher.events[name] then
        watcher.scripts.OnEvent(watcher, name)
    end
    harness.FireEvent(name)
    if scenario ~= "watcher-first" and watcher.events[name] then
        watcher.scripts.OnEvent(watcher, name)
    end
end
CreateFont = function() return widget() end
local function drain(untilTime)
    local count = 0
    while #pending > 0 do
        count = count + 1
        assert(count < 60, "unbounded setup retry")
        table.sort(pending, function(a, b) return a.due < b.due end)
        if untilTime and pending[1].due > untilTime then
            now = untilTime
            return
        end
        local timer = table.remove(pending, 1)
        now = timer.due
        timer.callback()
    end
end
local function panel()
    for _, f in ipairs(frames) do
        if f.template == "BackdropTemplate" and f.parent == UIParent then return f end
    end
end
local function button(text)
    for _, f in ipairs(frames) do if f.text == text then return f end end
    error("missing button " .. text)
end
local function shown() return panel() and panel().shown end
local function login()
    event("PLAYER_LOGIN")
    event("PLAYER_ENTERING_WORLD")
    drain()
    assert(not shown(), "setup appeared before loading ended")
    event("LOADING_SCREEN_DISABLED")
    drain(now + 0.25)
    assert(not shown(), "setup bypassed the transport's loading-screen grace")
    drain()
end
if scenario == "combat" then combat = true end
login()
if scenario == "font-compatible-fallback" then
    local ns = {}
    assert(loadfile("SetupLocales.lua"))("ApplicantScout", ns)
    local found = false
    for _, f in ipairs(fontstrings) do
        if f.text == ns.CompanionSetupLocales[fallbackLocale].pages[1].body then
            assert(f.fontObject.font == expectedFallback[fallbackLocale], "fallback used an incompatible font")
            found = true
        end
    end
    assert(found and shown() and ApplicantScoutDB.setupLocale == fallbackLocale,
        "compatible font was available but the selected language was lost")
    print("ok " .. scenario)
    return
end
if scenario == "font-all-missing" then
    local found = false
    for _, f in ipairs(frames) do
        if f.text == "Back" and f.parent == panel() then
            assert(f.normalFont == "GameFontNormal" and f.highlightFont == "GameFontHighlight"
                and f.disabledFont == "GameFontDisable", "fallback lost distinct button states")
            found = true
        end
    end
    assert(found and shown(), "failed fonts prevented readable setup")
    print("ok " .. scenario)
    return
end
if scenario == "enabled-transition" then
    assert(shown(), "first-run guide did not open")
    harness.SetEnabled(false)
    assert(not shown(), "disabling idle scouting left the automatic guide open")
    harness.SetEnabled(true)
    drain()
    assert(shown(), "enabling scouting did not restore the unfinished guide")
    button("Later").scripts.OnClick()
    harness.SetEnabled(false)
    harness.SetEnabled(true)
    drain()
    assert(not shown(), "toggle ignored the session postponement")
    harness.SetEnabled(false)
    SlashCmdList.APSCOUT("setup")
    drain()
    assert(shown(), "disabled scouting prevented manually requested setup")
    harness.SetEnabled(false)
    drain()
    assert(shown(), "idempotent disable closed manually requested setup")
    button("Already set up").scripts.OnClick()
    harness.SetEnabled(true)
    drain()
    assert(not shown() and ApplicantScoutDB.setupDismissed, "enabling scouting reopened permanently dismissed setup")
    print("ok " .. scenario)
    return
end
if scenario == "retry-interaction" then
    local picker, menu, korean, scrollFrame, address
    for _, f in ipairs(frames) do
        if f.name == "ApplicantScoutSetupLanguageButton" then picker = f end
        if f.name == "ApplicantScoutSetupLanguage_koKR" then korean, menu = f, f.parent end
        if f.template == "UIPanelScrollFrameTemplate" then scrollFrame = f end
        if f.kind == "EditBox" and f.parent == panel() then address = f end
    end
    korean.scripts.OnClick()
    button("Illustrated guide").scripts.OnClick()
    local selected = address.text
    scrollFrame:SetVerticalScroll(150)
    picker.scripts.OnClick()
    drain()
    assert(address.text == selected and address.focused and address.selected,
        "font retries replaced the selected link or interrupted copying")
    assert(scrollFrame.offset == 150, "font retries reset reading position")
    assert(menu.shown, "font retries closed the open language picker")
    korean.scripts.OnClick()
    scrollFrame:SetVerticalScroll(150)
    measuredHeight = 300
    drain()
    assert(scrollFrame.offset == 22, "font retries did not clamp scroll after content became shorter")
    print("ok " .. scenario)
    return
end
if scenario == "parent-hide" then
    assert(shown(), "guide did not open")
    panel().scripts.OnHide(panel()) -- Parent hiding fires OnHide without clearing IsShown.
    event("PLAYER_REGEN_ENABLED")
    drain()
    assert(shown(), "hiding the parent incorrectly postponed the guide")
    print("ok " .. scenario)
    return
end
if scenario:find("measurement-", 1, true) then
    for _, f in ipairs(frames) do
        if f.template == "UIPanelScrollFrameTemplate" then
            assert(f.child.height == 600, "bad font measurement poisoned scroll content geometry")
        end
    end
    assert(shown(), "measurement failure prevented setup")
    print("ok " .. scenario)
    return
end
if scenario == "escape" then
    assert(shown(), "guide did not open")
    local registered = 0
    for _, name in ipairs(UISpecialFrames) do
        if name == panel().name and name == "ApplicantScoutCompanionSetup" then registered = registered + 1 end
    end
    assert(registered == 1, "setup is not registered once for global Escape")
    SlashCmdList.APSCOUT("setup") -- Queue a reopen, then close before its timer runs.
    panel():Hide() -- Blizzard CloseSpecialWindows calls Hide on registered frames.
    event("PLAYER_REGEN_ENABLED")
    drain()
    assert(not shown() and not ApplicantScoutDB.setupDismissed, "Escape closed permanently or immediately reopened")
    SlashCmdList.APSCOUT("setup")
    drain()
    assert(shown(), "Escape prevented manual reopening")
    frames, pending, fontstrings = {}, {}, {}
    harness = env.load_addon({})
    watcher = frames[#frames]
    login()
    assert(shown(), "Escape did not postpone until reload")
    assert(#UISpecialFrames == 1, "reload registered duplicate Escape entries")
    print("ok " .. scenario)
    return
end
if scenario == "resize" then
    button("Next").scripts.OnClick()
    local before = panel()
    UIParent.width, UIParent.height = 500, 480
    event("DISPLAY_SIZE_CHANGED")
    assert(panel().scale == 500 / 720, "display resize retained stale scale")
    UIParent.width, UIParent.height = 1920, 1080
    event("UI_SCALE_CHANGED")
    assert(panel().scale == 1 and panel() == before, "UI scale change replaced or failed to resize the panel")
    UIParent.width = 0 / 0
    event("UI_SCALE_CHANGED")
    assert(panel().scale == 1, "invalid dimensions poisoned the scale")
    assert(button("Back") and shown(), "resize lost guide state")
    print("ok " .. scenario)
    return
end
if scenario:find("font-", 1, true) then
    local function named(name)
        for _, f in ipairs(frames) do if f.name == name then return f end end
        error("missing control " .. name)
    end
    named("ApplicantScoutSetupLanguage_koKR").scripts.OnClick()
    if scenario == "font-cold" or scenario == "font-false-success" then drain() end
    if scenario == "font-cold" then
        local choice = named("ApplicantScoutSetupLanguage_koKR")
        assert(type(choice.normalFont) == "table" and choice.normalFont.font == "Fonts\\2002.TTF",
            "cold font recovered in the body but not in the language picker")
    end
    assert(ApplicantScoutDB.setupLocale == "koKR", "font handling lost language preference")
    local found = false
    for _, f in ipairs(fontstrings) do
        if (scenario == "font-switch" or scenario == "font-nil-return" or scenario == "font-cold") and f.text:find("Companion", 1, true) and rawget(f, "fontObject") then
            assert(f.fontObject.font == "Fonts\\2002.TTF", "Korean text kept the client font")
            found = true
        elseif scenario ~= "font-switch" and scenario ~= "font-nil-return" and scenario ~= "font-cold" and f.text:find("could not load", 1, true) then
            assert(f.fontObject.font == "Fonts\\ARIALN.TTF", "fallback text did not get a readable font")
            found = true
        end
    end
    assert(found, "selected font or readable fallback missing")
    assert(named("ApplicantScoutSetupLanguage_koKR").text:find("Korean", 1, true), "picker has no readable alias")
    if scenario == "font-switch" then
        for code, path in pairs({zhCN = "Fonts\\ARKai_T.ttf", zhTW = "Fonts\\arheiuhk_bd.TTF"}) do
            named("ApplicantScoutSetupLanguage_" .. code).scripts.OnClick()
            for _, f in ipairs(fontstrings) do
                if rawget(f, "fontObject") then
                    assert(f.fontObject.font == path, "Chinese text kept the previous language's font")
                end
            end
        end
    end
    named("ApplicantScoutSetupLanguage_ruRU").scripts.OnClick()
    drain() -- A stale fallback retry must not replace the newer language choice.
    for _, f in ipairs(frames) do
        if type(rawget(f, "normalFont")) == "table" and f.parent == panel() then
            assert(f.normalFont.font == f.highlightFont.font and f.normalFont.font == f.disabledFont.font,
                "button interaction states revert to the client font")
            assert(f.normalFont.font == "Fonts\\ARIALN.TTF", "button did not switch font")
            assert(f.normalFont.color[2] == 0.82 and f.disabledFont.color[1] == 0.5,
                "font switch erased enabled/disabled button contrast")
        end
    end
    for _, f in ipairs(fontstrings) do
        if rawget(f, "fontObject") then
            assert(f.fontObject.font == "Fonts\\ARIALN.TTF", "switch did not refresh every text region")
            assert(not f.text:find("could not load", 1, true), "font warning remained after recovery")
        end
    end
    print("ok " .. scenario)
    return
end
if scenario:find("language", 1, true) or scenario:find("locale-api", 1, true) then
    local namespace = {}
    assert(loadfile("SetupLocales.lua"))("ApplicantScout", namespace)
    local locales = namespace.CompanionSetupLocales
    local automatic = clientLocale == "enGB" and "enUS" or clientLocale
    if not locales[automatic] or scenario:find("locale-api", 1, true) then automatic = "enUS" end
    local code = scenario == "language-saved" and "ruRU" or automatic
    local function named(name)
        for _, f in ipairs(frames) do if f.name == name then return f end end
        error("missing named control " .. name)
    end
    local function hasText(text)
        for _, f in ipairs(fontstrings) do if f.text == text then return true end end
        return false
    end
    assert(shown() and hasText(locales[code].pages[1].title), "client or saved language was not selected")
    local initialPanel = panel()
    button(locales[code].ui.next).scripts.OnClick()
    local picker = named("ApplicantScoutSetupLanguageButton")
    picker.scripts.OnClick()
    local target = code == "ruRU" and "deDE" or "ruRU"
    local choice = named("ApplicantScoutSetupLanguage_" .. target)
    assert(choice.parent.shown, "language menu did not open")
    choice.scripts.OnClick()
    assert(not choice.parent.shown and ApplicantScoutDB.setupLocale == target, "language choice was not saved or menu stayed open")
    assert(hasText(locales[target].pages[2].title), "language switch reset or failed to translate the current step")
    assert(panel() == initialPanel, "language switch allocated another panel")
    for step = 2, 5 do
        assert(hasText(locales[target].pages[step].body), "step body did not switch language")
        if step < 5 then button(locales[target].ui.next).scripts.OnClick() end
    end
    -- Reload must keep the explicit language even when the client differs.
    frames, pending, fontstrings = {}, {}, {}
    harness = env.load_addon({})
    watcher = frames[#frames]
    login()
    assert(hasText(locales[target].pages[1].title), "reload lost the selected language")
    named("ApplicantScoutSetupLanguage_auto").scripts.OnClick()
    assert(ApplicantScoutDB.setupLocale == nil, "automatic language preference was not restored")
    assert(hasText(locales[automatic].pages[1].title), "automatic language did not follow the client or fallback")
    print("ok " .. scenario .. " " .. clientLocale)
    return
end
if scenario == "postponed" then
    button("Later").scripts.OnClick()
    assert(not ApplicantScoutDB.setupDismissed and not shown(), "Later persisted dismissal")
    frames, pending = {}, {}
    harness = env.load_addon({})
    watcher = frames[#frames]
    login()
    assert(shown(), "postponed guide did not return after reload")
end
if scenario == "dismissed" or scenario == "disabled" then
    assert(not shown(), "dismissed or disabled install was nagged")
    SlashCmdList.APSCOUT("setup")
    drain()
    assert(shown(), "manual setup cannot reopen")
    if scenario == "disabled" then
        assert(ApplicantScoutDB.enabled == false, "setup enabled the addon")
        assert(ApplicantScoutDB.autoHiMessage == "hello", "setup changed user preferences")
    end
elseif scenario == "combat" then
    assert(not shown(), "combat login opened setup")
    SlashCmdList.APSCOUT("setup")
    drain()
    assert(not shown(), "manual setup bypassed combat")
    combat = false
    event("PLAYER_REGEN_ENABLED")
    drain()
    assert(shown(), "setup failed to resume after combat")
else
    assert(shown(), "first login did not show setup")
end
local initialPanel = panel()
if scenario == "small-display" then
    assert(initialPanel.width * initialPanel.scale < UIParent.width, "guide exceeds narrow screen")
    assert(initialPanel.height * initialPanel.scale < UIParent.height, "guide exceeds short screen")
end
local scroll
for _, f in ipairs(frames) do
    if f.kind == "ScrollFrame" and f.parent == initialPanel then scroll = f end
end
assert(scroll and scroll.child.height > scroll.height, "long instructions cannot scroll")
scroll:SetVerticalScroll(80)
local url
for _, f in ipairs(frames) do if f.kind == "EditBox" and f.parent == initialPanel then url = f end end
assert(url and not url.focused, "automatic panel stole keyboard focus")
local downloadURL = "https://github.com/Antrakt92/ApplicantScout-Companion/releases/latest"
assert(url.text == "https://github.com/Antrakt92/ApplicantScout-Companion", "source address is incorrect")
button("Select download link").scripts.OnClick()
assert(url.text == downloadURL and url.focused and url.selected, "copy action did not select the address")
url:SetText("bad pasted address")
url.scripts.OnTextChanged(url, true)
assert(url.text == downloadURL, "download address remained editable")
local curseforgeURL = "https://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"
for _ = 1, 4 do button("Next").scripts.OnClick() end
local hasCurseForgeLabel = false
for _, fontstring in ipairs(fontstrings) do
    if fontstring.text and fontstring.text:find(curseforgeURL, 1, true) then
        hasCurseForgeLabel = true
        break
    end
end
assert(hasCurseForgeLabel, "setup panel is missing the CurseForge update label")
for _ = 1, 4 do button("Back").scripts.OnClick() end
-- Navigation keeps one panel and never silently completes account setup.
local priorDismissal = ApplicantScoutDB.setupDismissed
button("Next").scripts.OnClick()
assert(scroll.offset == 0, "navigation retained previous page's scroll offset")
assert(ApplicantScoutDB.setupDismissed == priorDismissal, "navigation changed setup dismissal")
button("Illustrated guide").scripts.OnClick()
local guideURL = "https://github.com/Antrakt92/ApplicantScout-Companion/blob/main/docs/GETTING_STARTED.md"
assert(url.text == guideURL and url.focused and url.selected, "illustrated guide was not selectable")
url:SetText("bad pasted guide")
url.scripts.OnTextChanged(url, true)
assert(url.text == guideURL, "guide address remained editable")
button("Select download link").scripts.OnClick()
assert(url.text == downloadURL and url.selected, "download action did not restore official address")
button("Back").scripts.OnClick()
button("Later").scripts.OnClick()
assert(ApplicantScoutDB.setupDismissed == priorDismissal and not shown(), "Later changed persistent dismissal")
event("PLAYER_REGEN_ENABLED")
drain()
assert(not shown(), "postponed setup nagged again in the same session")
SlashCmdList.APSCOUT("setup")
drain()
assert(shown(), "postponed guide could not be reopened manually")
for _ = 1, 4 do button("Next").scripts.OnClick() end
button("Finish guide").scripts.OnClick()
assert(ApplicantScoutDB.setupDismissed and not shown(), "Finish did not persist guide dismissal")
SlashCmdList.APSCOUT("setup")
drain()
button("Next").scripts.OnClick()
button("Next").scripts.OnClick()
assert(url.text == "https://www.warcraftlogs.com/api/clients/", "WCL step did not expose API Clients link")
local resumedURL = url.text
local languageButton, languageMenu
for _, f in ipairs(frames) do
    if f.name == "ApplicantScoutSetupLanguageButton" then languageButton = f end
    if f.name == "ApplicantScoutSetupLanguage_auto" then languageMenu = f.parent end
end
for _, pair in ipairs({ {"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"},
    {"ENCOUNTER_START", "ENCOUNTER_END"}, {"CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED"},
    {"LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED"} }) do
    languageButton.scripts.OnClick()
    assert(languageMenu.shown, "language menu cannot open on a later step")
    event(pair[1])
    assert(not shown() and not url.focused, "gameplay/loading left setup visible or focused")
    assert(not languageMenu.shown, "gameplay left the language menu visible")
    drain()
    assert(not shown(), "queued work reopened setup during gameplay/loading")
    event(pair[2])
    drain()
    assert(shown(), "setup did not resume after gameplay/loading")
    assert(panel() == initialPanel, "setup allocated a duplicate panel")
    assert(url.text == resumedURL, "gameplay resume lost the current guide step")
end
for _, activity in ipairs({ "challenge", "encounter" }) do
    if activity == "challenge" then challenge = true else encounter = true end
    event(activity == "challenge" and "CHALLENGE_MODE_START" or "ENCOUNTER_START")
    drain()
    assert(not shown(), "active gameplay left setup visible")
    -- A missing end event is recovered by the existing current-state resolver.
    -- An unreadable API must preserve the active state until clean evidence.
    if activity == "challenge" then challenge = nil else encounter = nil end
    event("PLAYER_REGEN_ENABLED")
    drain()
    assert(not shown() and harness.QRTransportState().suppressedByGameplay,
        "an unreadable activity API prematurely reopened setup")
    if activity == "challenge" then challenge = false else encounter = false end
    event("PLAYER_REGEN_ENABLED")
    drain()
    assert(not harness.QRTransportState().suppressedByGameplay,
        "transport did not reconcile the missed activity end")
    assert(shown(), "setup retained a stale activity latch after transport recovery")
end
button("Already set up").scripts.OnClick()
assert(ApplicantScoutDB.setupDismissed == true and not shown(), "explicit close did not persist")
for _ = 1, 3 do
    event("PLAYER_ENTERING_WORLD")
    event("LOADING_SCREEN_DISABLED")
    drain()
    assert(not shown(), "world transition reopened dismissed setup")
end
SlashCmdList.APSCOUT("setup")
drain()
assert(shown(), "setup command cannot reopen after dismissal")
url.scripts.OnEscapePressed(url)
assert(not shown(), "Escape in address field did not close")
-- A fresh addon chunk represents a reload with the same account SavedVariables.
frames, pending = {}, {}
harness = env.load_addon({})
watcher = frames[#frames]
login()
assert(not shown(), "reload forgot account-wide dismissal")
print("ok " .. scenario)
