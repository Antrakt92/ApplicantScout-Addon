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
local fontstrings, textures = {}, {}
local now = 1000
local fontColdUntil
local measuredHeight = scenario == "design-export" and (tonumber(arg[4]) or 450) or 450
if scenario == "scrollbar" then measuredHeight = 180 end
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
        SetShown = function(self, value) if value then self:Show() else self:Hide() end end,
        Hide = function(self)
            local wasShown = self.shown
            self.shown = false
            if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end,
        IsShown = function(self) return self.shown end,
        GetWidth = function(self) return self.width or 1920 end,
        GetHeight = function(self) return self.height or 1080 end,
        SetSize = function(self, width, height) self.width, self.height = width, height end,
        SetPoint = function(self, ...) self.point = {...} end,
        SetBackdrop = function(self, value) self.backdrop = value end,
        SetBackdropColor = function(self, ...) self.background = {...} end,
        SetBackdropBorderColor = function(self, ...) self.border = {...} end,
        SetColorTexture = function(self, ...) self.background = {...} end,
        SetTexture = function(self, path) self.texture = path end,
        SetHeight = function(self, height) self.height = height end,
        SetWidth = function(self, width) self.width = width end,
        SetChecked = function(self, value) self.checked = value end,
        GetChecked = function(self) return self.checked end,
        HasFocus = function(self) return self.focused end,
        SetEnabled = function(self, enabled) self.enabled = enabled end,
        IsEnabled = function(self) return self.enabled ~= false end,
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
        SetText = function(self, text)
            self.text = text
            if rawget(self, "fontstring") then self.fontstring.text = text end
        end,
        GetText = function(self) return self.text end,
        SetFont = function(self, path, size, flags)
            if scenario == "font-all-missing" then return false end
            if scenario == "font-compatible-fallback" and path:find(blockedFont[fallbackLocale], 1, true) then return false end
            if (scenario == "font-missing" or scenario == "retry-interaction" or scenario == "settings-font") and koreanFont(path) then return false end
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
        SetFontString = function(self, fontstring) self.fontstring = fontstring end,
        SetFocus = function(self) self.focused = true end,
        ClearFocus = function(self) self.focused = false end,
        HighlightText = function(self) self.selected = true end,
        CreateTexture = function(self, _, layer)
            local texture = widget()
            texture.parent, texture.layer = self, layer
            textures[#textures + 1] = texture
            return texture
        end,
        CreateFontString = function(self)
            local fontstring = widget()
            fontstring.parent = self
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
    if template == "UIPanelScrollFrameTemplate" then frame.ScrollBar = widget() end
    frames[#frames + 1] = frame
    return frame
end
UIParent = widget()
UISpecialFrames = {}
if scenario == "small-display" then UIParent.width, UIParent.height = 500, 480 end
ApplicantScoutDB = scenario == "disabled" and {enabled = false, autoHiMessage = "hello"}
    or scenario == "dismissed" and {setupDismissed = true, setupAutoHidden = true}
    or scenario == "legacy-dismissed" and {setupDismissed = true}
    or scenario == "corrupt" and {setupDismissed = {}}
    or {}
if scenario == "language-saved" then ApplicantScoutDB.setupLocale = "ruRU" end
if scenario == "language-invalid" then ApplicantScoutDB.setupLocale = {} end
if scenario == "language-invalid-string" then ApplicantScoutDB.setupLocale = "xxXX" end
if scenario == "font-compatible-fallback" then ApplicantScoutDB.setupLocale = fallbackLocale end
if scenario == "saved-step" then ApplicantScoutDB.setupStep = 3 end
if scenario == "saved-step-zero" then ApplicantScoutDB.setupStep = 0 end
if scenario == "saved-step-high" then ApplicantScoutDB.setupStep = 6 end
if scenario == "saved-step-fraction" then ApplicantScoutDB.setupStep = 2.5 end
if scenario == "saved-step-nan" then ApplicantScoutDB.setupStep = 0 / 0 end
if scenario == "saved-step-string" then ApplicantScoutDB.setupStep = "3" end
if scenario == "saved-step-table" then ApplicantScoutDB.setupStep = {} end
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
local function named(name)
    for _, f in ipairs(frames) do if f.name == name then return f end end
    error("missing control " .. name)
end
local function shown() return panel() and panel().shown end
local function hasText(text)
    for _, f in ipairs(fontstrings) do if f.text == text then return true end end
    return false
end
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
if scenario == "scrollbar" then
    local viewport
    for _, f in ipairs(frames) do
        if f.template == "UIPanelScrollFrameTemplate" then viewport = f end
    end
    assert(viewport and not viewport.ScrollBar.shown, "fitting instructions display an empty scrollbar")
    assert(viewport.child.height == viewport.height, "bottom padding creates unnecessary scrolling")
    measuredHeight = 450
    named("ApplicantScoutSetupDetails").scripts.OnClick()
    assert(viewport.ScrollBar.shown, "long details have no scrollbar")
    viewport:SetVerticalScroll(120)
    measuredHeight = viewport.height
    named("ApplicantScoutSetupDetails").scripts.OnClick()
    assert(not viewport.ScrollBar.shown and viewport.offset == 0, "collapsing to an exact fit keeps scrolling")
    measuredHeight = viewport.height + 1
    button("Next").scripts.OnClick()
    assert(viewport.ScrollBar.shown, "one-pixel overflow is inaccessible")
    viewport.scripts.OnScrollRangeChanged(viewport, 0, 0)
    assert(not viewport.ScrollBar.shown, "range update restores an empty scrollbar")
    viewport.scripts.OnScrollRangeChanged(viewport, 0, 13)
    assert(viewport.ScrollBar.shown, "range update hides overflowing content")
    print("ok " .. scenario)
    return
end
if scenario == "legacy-dismissed" or scenario == "explicit-reminder" then
    assert(shown(), "old completion flag blocked first explicit-preference onboarding")
    assert(not ApplicantScoutDB.setupAutoHidden, "old dismissal was treated as explicit consent")
    local choice = named("ApplicantScoutSetupNoAuto")
    assert(not choice.shown, "automatic-opening control leaked into installation")
    named("ApplicantScoutSetupSettingsTab").scripts.OnClick()
    assert(choice.shown, "automatic-opening control missing from settings")
    choice:SetChecked(true)
    choice.scripts.OnClick(choice)
    assert(ApplicantScoutDB.setupAutoHidden and shown(), "checkbox failed to save without closing")
    event("PLAYER_REGEN_ENABLED")
    drain()
    assert(shown(), "saving preference unexpectedly closed the active guide")
    named("ApplicantScoutSetupStep1").scripts.OnClick()
    button("Close").scripts.OnClick()
    frames, pending, fontstrings = {}, {}, {}
    harness = env.load_addon({})
    watcher = frames[#frames]
    login()
    assert(not shown(), "explicit opt-out was ignored on reload")
    SlashCmdList.APSCOUT("setup")
    drain()
    assert(shown() and named("ApplicantScoutSetupNoAuto").checked, "manual reopening lost preference")
    choice = named("ApplicantScoutSetupNoAuto")
    named("ApplicantScoutSetupSettingsTab").scripts.OnClick()
    assert(choice.shown, "manual opening did not expose the preference in settings")
    choice:SetChecked(false)
    choice.scripts.OnClick(choice)
    button("Close").scripts.OnClick()
    frames, pending, fontstrings = {}, {}, {}
    harness = env.load_addon({})
    watcher = frames[#frames]
    login()
    assert(shown(), "unchecking failed to restore automatic reminder")
    print("ok " .. scenario)
    return
end
if scenario == "settings-font" then
    ApplicantScoutDB.setupLocale = "koKR"
    local root = panel()
    named("ApplicantScoutSetupSettingsTab").scripts.OnClick()
    drain()
    assert(panel() == root and shown() and named("ApplicantScoutSetupSettings").shown, "font fallback changed the settings window")
    assert(ApplicantScoutDB.setupLocale == "koKR", "font fallback discarded selected settings language")
    assert(hasText("Font unavailable; showing English"), "hidden guide body concealed the settings font fallback")
    print("ok " .. scenario)
    return
end
if scenario == "menu" or scenario == "menu-export" then
    SlashCmdList.APSCOUT("")
    drain()
    local root = panel()
    assert(shown(), "bare command did not open the shared guide")
    ApplicantScoutDB.autoHiGreetNewPartyMembers = true
    named("ApplicantScoutSetupSettingsTab").scripts.OnClick()
    drain()
    local hub = named("ApplicantScoutSetupSettings")
    assert(hub.parent == root and hub.shown and shown(), "settings are not inside the shared guide")
    for _, frame in ipairs(frames) do
        assert(frame.name ~= "ApplicantScoutMenu" and frame.name ~= "ApplicantScoutSettingsFrame", "an old settings window was created")
    end
    local ns = {}
    assert(loadfile("SetupLocales.lua"))("ApplicantScout", ns)
    local language = ns.CompanionSetupLocales[clientLocale]
    assert(hasText(language.menu[14]), "menu explanation was not localized")
    assert(named("ApplicantScoutMenuCheck6").checked, "settings did not initialize the saved greeting preference")
    for _, f in ipairs(frames) do
        if f.parent == hub then
            assert(f.point[2] >= 24 and -f.point[3] >= 0
                and f.point[2] + f.width <= 736 and -f.point[3] + f.height <= hub.height,
                "settings control exceeds its shared content area")
        end
    end
    if scenario == "menu-export" then
        local items = {}
        local function visible(f)
            local current = f
            while current and current ~= UIParent do
                if not current.shown then return false end
                if current == root then return true end
                current = rawget(current, "parent")
            end
            return false
        end
        local function rectangle(f)
            if f == root then return 0, 0, f.width, f.height end
            local parent = f.parent
            local x, y, width, height = rectangle(parent)
            local p = f.point
            if p[1] == "TOPLEFT" then return x + (p[2] or 0), y - (p[3] or 0), f.width, f.height end
            if p[1] == "BOTTOMLEFT" then return x + p[2], y + height - p[3] - f.height, f.width, f.height end
            if p[1] == "CENTER" then return x + (width - f.width) / 2, y + (height - f.height) / 2, f.width, f.height end
            error("unsupported settings anchor " .. p[1])
        end
        local function export(f, kind)
            local x, y, width, height = rectangle(f)
            local font = rawget(f, "fontObject") or rawget(f, "normalFont")
            local text = rawget(f, "text") or ""
            if kind == "CheckButton" and f.checked then text = "✓" end
            items[#items + 1] = {kind, x, y, width, height, text,
                type(font) == "table" and font.fontSize or 12,
                rawget(f, "background") or {}, rawget(f, "border") or {}, "", true, rawget(f, "name") or ""}
        end
        for _, f in ipairs(textures) do
            if visible(f) and f.layer == "BACKGROUND" then export(f, "texture") end
        end
        for _, f in ipairs(frames) do
            if f ~= root and visible(f) and f.template ~= "UIPanelCloseButton" then export(f, f.kind) end
        end
        for _, f in ipairs(fontstrings) do
            if visible(f) and f.parent.kind ~= "Button" then export(f, "text") end
        end
        local function json(value)
            if type(value) == "string" then
                return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
            elseif type(value) == "number" then return tostring(value)
            elseif type(value) == "boolean" then return value and "true" or "false"
            elseif type(value) == "table" then
                local entries = {}
                for _, item in ipairs(value) do entries[#entries + 1] = json(item) end
                return "[" .. table.concat(entries, ",") .. "]"
            end
            return "null"
        end
        print(json(items))
        return
    end
    for index, key in pairs({[3] = "enabled", [6] = "autoHiGreetNewPartyMembers",
        [7] = "qrAlwaysVisible", [8] = "debug"}) do
        local control = named("ApplicantScoutMenuCheck" .. index)
        for _, value in ipairs({true, false}) do
            control:SetChecked(value)
            control.scripts.OnClick(control)
            assert(ApplicantScoutDB[key] == value, "menu setting did not save: " .. key)
        end
    end
    button(language.menu[4] .. ": " .. language.menu[18]).scripts.OnClick()
    assert(ApplicantScoutDB.autoMPlusPlaystyle == "Expert", "menu style skipped canonical setting helper")
    local edit = named("ApplicantScoutMenuGreeting")
    edit:SetFocus()
    edit:SetText("pending greeting")
    local choice = named("ApplicantScoutSetupNoAuto")
    choice:SetChecked(false)
    choice.scripts.OnClick(choice)
    assert(edit.text == "pending greeting", "changing settings discarded the focused greeting")
    edit:SetText("hello menu")
    edit.scripts.OnEnterPressed(edit)
    assert(ApplicantScoutDB.autoHiMessage == "hello menu", "menu greeting was not saved")
    edit:SetText("discard me")
    edit.scripts.OnEscapePressed(edit)
    assert(edit.text == "hello menu" and ApplicantScoutDB.autoHiMessage == "hello menu", "escape saved canceled greeting")
    button(language.ui.back).scripts.OnClick()
    assert(shown() and not hub.shown and panel() == root, "back changed the window instead of the section")
    named("ApplicantScoutSetupStep5").scripts.OnClick()
    named("ApplicantScoutSetupNext").scripts.OnClick()
    drain()
    assert(hub.shown and panel() == root, "last install step did not lead to settings in the same window")
    SlashCmdList.APSCOUT("config")
    drain()
    assert(not shown(), "legacy config did not close the active settings section")
    SlashCmdList.APSCOUT("config")
    drain()
    assert(hub.shown and panel() == root, "legacy config created a separate window")
    SlashCmdList.APSCOUT("menu")
    drain()
    assert(not hub.shown and shown() and panel() == root, "menu alias did not reopen the shared guide")
    named("ApplicantScoutSetupSettingsTab").scripts.OnClick()
    drain()
    combat = true
    event("PLAYER_REGEN_DISABLED")
    assert(not shown(), "combat left shared settings visible")
    SlashCmdList.APSCOUT("")
    assert(not shown(), "manual menu bypassed combat restriction")
    SlashCmdList.APSCOUT("config")
    drain()
    assert(not shown(), "deferred settings opened in combat")
    combat = false
    event("PLAYER_REGEN_ENABLED")
    drain()
    assert(shown() and hub.shown and panel() == root, "deferred settings lost their section or window")
    edit:SetText("focus lost greeting")
    edit.scripts.OnEditFocusLost(edit)
    assert(ApplicantScoutDB.autoHiMessage == "focus lost greeting", "losing focus did not save greeting")
    print("ok " .. scenario)
    return
end
if scenario:find("saved-step", 1, true) then
    local expected = scenario == "saved-step" and 3 or 1
    local ns = {}
    assert(loadfile("SetupLocales.lua"))("ApplicantScout", ns)
    local language = ns.CompanionSetupLocales[clientLocale]
    assert(ApplicantScoutDB.setupStep == expected, "saved step was lost or unsafe input was accepted")
    assert(named("ApplicantScoutSetupStep" .. expected).setupSelected, "saved progress differs from current page")
    assert(hasText(language.pages[expected].title), "saved step did not translate")
    print("ok " .. scenario)
    return
end
if scenario == "resume-step" then
    button("Next").scripts.OnClick()
    button("Next").scripts.OnClick()
    button("Close").scripts.OnClick()
    assert(ApplicantScoutDB.setupStep == 3 and not ApplicantScoutDB.setupDismissed,
        "postponing forgot current progress or completed setup")
    frames, pending, fontstrings = {}, {}, {}
    harness = env.load_addon({})
    watcher = frames[#frames]
    login()
    assert(shown() and named("ApplicantScoutSetupStep3").setupSelected, "reload did not resume the postponed step")
    SlashCmdList.APSCOUT("setup")
    drain()
    assert(ApplicantScoutDB.setupStep == 1, "manual help did not restart the guide")
    button("Close").scripts.OnClick()
    assert(ApplicantScoutDB.setupStep == 1, "closing lost guide progress")
    print("ok " .. scenario)
    return
end
if scenario == "design" or scenario == "design-export" then
    assert(not named("ApplicantScoutSetupNoAuto").shown, "guide exposes unrelated automatic-opening preference")
    for _, f in ipairs(frames) do
        assert(f.text ~= "Already set up" and f.text ~= "Menu", "redundant guide action was created")
    end
    local ns = {}
    assert(loadfile("SetupLocales.lua"))("ApplicantScout", ns)
    local language = ns.CompanionSetupLocales[clientLocale]
    local link = named("ApplicantScoutSetupLink")
    local details = named("ApplicantScoutSetupDetails")
    local address
    for _, f in ipairs(frames) do if f.kind == "EditBox" and f.parent == panel() then address = f end end
    local desiredPage = tonumber(arg[3]) or 2
    named("ApplicantScoutSetupStep" .. desiredPage).scripts.OnClick()
    local quickDownload = named("ApplicantScoutSetupQuickDownload")
    assert(quickDownload.shown == (desiredPage == 1), "download shortcut appears outside the introduction")
    if desiredPage == 1 then
        quickDownload.scripts.OnClick()
        assert(address.text == "https://github.com/Antrakt92/ApplicantScout-Companion/releases/latest"
            and address.focused and address.selected, "intro download shortcut did not select the latest release")
    end
    assert(ApplicantScoutDB.setupStep == desiredPage and not ApplicantScoutDB.setupDismissed, "step navigation completed setup")
    local expectedLinks = {
        "https://github.com/Antrakt92/ApplicantScout-Companion",
        "https://github.com/Antrakt92/ApplicantScout-Companion/releases/latest",
        "https://www.warcraftlogs.com/api/clients/",
        "https://github.com/Antrakt92/ApplicantScout-Companion/blob/main/docs/GETTING_STARTED.md",
    }
    local expectedURL = expectedLinks[math.min(desiredPage, 4)]
    link.scripts.OnClick()
    assert(address.text == expectedURL and address.focused and address.selected, "step action selected the wrong URL")
    details.scripts.OnClick()
    assert(hasText(language.pages[desiredPage].body), "details did not reveal the complete translated instructions")
    assert(address.text == expectedURL and address.focused, "details interrupted copying")
    details.scripts.OnClick()
    assert(hasText(language.pages[desiredPage].summary), "short steps were not restored")
    assert(address.text == expectedURL and address.focused, "collapsing details interrupted copying")
    assert(named("ApplicantScoutSetupStep" .. desiredPage).setupSelected, "detail toggle moved the current step")
    assert(panel().width == 1000, "sidebar has no dedicated space")
    for index = 1, 5 do
        local item = named("ApplicantScoutSetupStep" .. index)
        assert(item.point[2] >= 752 and item.width == 192 and item.height == 56, "installation navigation is not in the right sidebar")
    end
    assert(named("ApplicantScoutSetupSettingsTab").point[2] >= 752, "settings are outside the shared sidebar")
    local backgrounds, example = 0, nil
    for _, texture in ipairs(textures) do
        if texture.parent == panel() and texture.width == 712 and texture.shown then
            assert(texture.layer == "BACKGROUND", "card background can cover parent text")
            backgrounds = backgrounds + 1
        elseif texture.parent and texture.parent.parent and texture.parent.parent.kind == "ScrollFrame" then
            example = texture
        end
    end
    assert(backgrounds == 2, "instruction and link cards are missing or redundant hint card remains")
    assert(example and example.shown == true, "example image is missing or leaked into later steps")
    assert(example.texture:find(({"setup-preview", "setup-download", "setup-wcl", "setup-settings", "setup-preview"})[desiredPage], 1, true), "wrong illustration for guide step")
    if desiredPage > 1 then
        assert(example.point[1] == "TOPLEFT" and -example.point[3] == measuredHeight + 16,
            "illustration overlaps instruction text")
        assert(example.width == 624 and example.parent.height >= -example.point[3] + example.height,
            "illustration is outside scrollable content")
    end
    do
        details.scripts.OnClick()
        assert(not example.shown, "example covered expanded instructions")
        details.scripts.OnClick()
        assert(example.shown, "example was not restored with short steps")
    end
    -- Main controls must fit their parent and leave separate header/content/action/footer bands.
    local function rectangle(f)
        local p = assert(rawget(f, "point"), "missing point")
        local width, height = rawget(f, "width") or 0, rawget(f, "height") or 0
        if f.parent and f.parent.parent and f.parent.parent.kind == "ScrollFrame" then
            local x, y = 40, 236
            if p[1] == "TOPRIGHT" then return x + 664 - width + (p[2] or 0), y - (p[3] or 0), width, height end
            return x + (p[2] or 0), y - (p[3] or 0), width, height
        end
        if p[1] == "TOPLEFT" then return p[2], -p[3], width, height end
        if p[1] == "BOTTOMLEFT" then return p[2], panel().height - p[3] - height, width, height end
        error("unsupported main control anchor " .. p[1])
    end
    local bounds = {}
    for _, f in ipairs(frames) do
        if f.shown and f.parent == panel() and f.kind == "Button" and f.template ~= "UIPanelCloseButton" then
            local x, y, width, height = rectangle(f)
            assert(x >= 0 and y >= 0 and x + width <= panel().width and y + height <= panel().height,
                "control exceeds setup bounds: " .. f.text)
            assert(f.fontstring.width == width - 16 and f.fontstring.height <= height,
                "button has no bounded wrapping area")
            for _, prior in ipairs(bounds) do
                assert(x + width <= prior[1] or prior[1] + prior[3] <= x
                    or y + height <= prior[2] or prior[2] + prior[4] <= y,
                    "interactive controls overlap")
            end
            bounds[#bounds + 1] = {x, y, width, height}
        end
    end
    if scenario == "design-export" then
        local function json(value)
            if type(value) == "string" then
                return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
            elseif type(value) == "number" then return tostring(value)
            elseif type(value) == "boolean" then return value and "true" or "false"
            elseif type(value) == "table" then
                local entries = {}
                for _, item in ipairs(value) do entries[#entries + 1] = json(item) end
                return "[" .. table.concat(entries, ",") .. "]"
            end
            return "null"
        end
        local items = {}
        local function export(f, kind)
            local x, y, width, height = rectangle(f)
            local font = rawget(f, "fontObject") or rawget(f, "normalFont")
            local size = type(font) == "table" and font.fontSize or 12
            items[#items + 1] = {kind, x, y, width, height, rawget(f, "text") or "", size,
                rawget(f, "background") or {}, rawget(f, "border") or {}, rawget(f, "texture") or "",
                rawget(f, "enabled") ~= false, rawget(f, "name") or ""}
        end
        for _, f in ipairs(textures) do
            if f.parent == panel() and f.shown and f.layer == "BACKGROUND" then export(f, "texture") end
        end
        for _, f in ipairs(frames) do
            if f.parent == panel() and f.shown and f.template ~= "UIPanelCloseButton" then export(f, f.kind) end
        end
        for _, f in ipairs(fontstrings) do if f.parent == panel() and f.shown then export(f, "text") end end
        for _, f in ipairs(textures) do
            if f.parent == panel() and f.shown and f.layer ~= "BACKGROUND" then export(f, "texture") end
        end
        for _, f in ipairs(fontstrings) do
            if f.shown and f.parent ~= panel() and rawget(f, "fontObject") then
                local parent = rawget(f, "parent")
                if parent and parent.parent and parent.parent.kind == "ScrollFrame" then
                    if f.text == language.pages[desiredPage].summary then
                        local x, y, _, height = rectangle(parent.parent)
                        items[#items + 1] = {"body", x, y, f.width, height, f.text, f.fontObject.fontSize, {}, {}, "", true, ""}
                    else export(f, "text") end
                end
            end
        end
        for _, f in ipairs(textures) do
            if f.shown and f.parent and f.parent.parent and f.parent.parent.kind == "ScrollFrame" then export(f, "texture") end
        end
        print(json(items))
    else print("ok " .. scenario) end
    return
end
if scenario == "font-compatible-fallback" then
    local ns = {}
    assert(loadfile("SetupLocales.lua"))("ApplicantScout", ns)
    local found = false
    for _, f in ipairs(fontstrings) do
        if f.text == ns.CompanionSetupLocales[fallbackLocale].pages[1].summary then
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
    button("Close").scripts.OnClick()
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
    button("Close").scripts.OnClick()
    harness.SetEnabled(true)
    drain()
    assert(not shown() and not ApplicantScoutDB.setupAutoHidden, "completion changed reminder preference or reopened this session")
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
    scrollFrame:SetVerticalScroll(120)
    picker.scripts.OnClick()
    drain()
    assert(address.text == selected and address.focused and address.selected,
        "font retries replaced the selected link or interrupted copying")
    assert(scrollFrame.offset == 120, "font retries reset reading position")
    assert(menu.shown, "font retries closed the open language picker")
    korean.scripts.OnClick()
    scrollFrame:SetVerticalScroll(120)
    measuredHeight = 300
    drain()
    assert(scrollFrame.offset == math.max(0, 312 - scrollFrame.height), "font retries did not clamp scroll after content became shorter")
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
    assert(panel().scale == math.min(500 / (panel().width + 40), 480 / (panel().height + 40)), "display resize retained stale scale")
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
            assert(f.normalFont.color[2] == 0.94 and f.disabledFont.color[1] == 0.5,
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
        assert(hasText(locales[target].pages[step].summary), "short steps did not switch language")
        button(locales[target].ui.details).scripts.OnClick()
        assert(hasText(locales[target].pages[step].body), "full instructions did not switch language")
        button(locales[target].ui.less).scripts.OnClick()
        if step < 5 then button(locales[target].ui.next).scripts.OnClick() end
    end
    -- Reload must keep the explicit language even when the client differs.
    frames, pending, fontstrings = {}, {}, {}
    harness = env.load_addon({})
    watcher = frames[#frames]
    login()
    assert(hasText(locales[target].pages[5].title), "reload lost the selected language or saved step")
    named("ApplicantScoutSetupLanguage_auto").scripts.OnClick()
    assert(ApplicantScoutDB.setupLocale == nil, "automatic language preference was not restored")
    assert(hasText(locales[automatic].pages[5].title), "automatic language did not follow the client or fallback")
    print("ok " .. scenario .. " " .. clientLocale)
    return
end
if scenario == "postponed" then
    button("Close").scripts.OnClick()
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
local sourceURL = "https://github.com/Antrakt92/ApplicantScout-Companion"
button("Project on GitHub").scripts.OnClick()
assert(url.text == sourceURL and url.focused and url.selected, "source action did not select the address")
url:SetText("bad pasted address")
url.scripts.OnTextChanged(url, true)
assert(url.text == sourceURL, "source address remained editable")
button("Next").scripts.OnClick()
button("Select download link").scripts.OnClick()
assert(url.text == downloadURL and url.focused and url.selected, "installer action did not select the address")
button("Back").scripts.OnClick()
local curseforgeURL = "https://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"
for _ = 1, 4 do button("Next").scripts.OnClick() end
local hasCurseForgeLabel = false
for _, fontstring in ipairs(fontstrings) do
    if fontstring.text and fontstring.text:find(curseforgeURL, 1, true) then
        hasCurseForgeLabel = true
        break
    end
end
assert(not hasCurseForgeLabel, "removed explanatory strip still renders an unrelated update address")
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
button("Close").scripts.OnClick()
assert(ApplicantScoutDB.setupDismissed == priorDismissal and not shown(), "Later changed persistent dismissal")
event("PLAYER_REGEN_ENABLED")
drain()
assert(not shown(), "postponed setup nagged again in the same session")
SlashCmdList.APSCOUT("setup")
drain()
assert(shown(), "postponed guide could not be reopened manually")
for _ = 1, 4 do button("Next").scripts.OnClick() end
named("ApplicantScoutSetupNext").scripts.OnClick()
drain()
assert(shown() and named("ApplicantScoutSetupSettings").shown, "last guide step did not open integrated settings")
assert(ApplicantScoutDB.setupDismissed == priorDismissal, "settings changed explicit reminder preference")
button("Close").scripts.OnClick()
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
button("Close").scripts.OnClick()
assert(ApplicantScoutDB.setupDismissed == priorDismissal and not shown(), "completion changed reminder preference")
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
assert((not not shown()) == (not ApplicantScoutDB.setupAutoHidden and ApplicantScoutDB.enabled), "reload ignored explicit reminder preference")
print("ok " .. scenario)
