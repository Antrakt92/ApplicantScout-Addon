local scenario = assert(arg[1], "scenario required")
local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local frames, pending = {}, {}
local fontstrings = {}
local now = 1000
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
local function widget()
    local frame = { scripts = {}, events = {}, shown = true, text = "", focused = false }
    local noop = function() end
    local methods = {
        RegisterEvent = function(self, event) self.events[event] = true end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        HookScript = function(self, name, fn) self.scripts[name] = fn end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsShown = function(self) return self.shown end,
        GetWidth = function() return 1920 end,
        GetHeight = function() return 1080 end,
        GetEffectiveScale = function() return 1 end,
        SetText = function(self, text) self.text = text end,
        GetText = function(self) return self.text end,
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
CreateFrame = function(kind, _, parent, template)
    local frame = widget()
    frame.kind, frame.parent, frame.template = kind, parent, template
    frames[#frames + 1] = frame
    return frame
end
UIParent = widget()
ApplicantScoutDB = scenario == "disabled" and {enabled = false, autoHiMessage = "hello"}
    or scenario == "dismissed" and {setupDismissed = true}
    or scenario == "corrupt" and {setupDismissed = {}}
    or {}
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
local url
for _, f in ipairs(frames) do if f.kind == "EditBox" and f.parent == initialPanel then url = f end end
assert(url and not url.focused, "automatic panel stole keyboard focus")
local downloadURL = "https://github.com/Antrakt92/ApplicantScout-Companion/releases/latest"
assert(url.text == downloadURL, "download address is incorrect")
button("Select download link").scripts.OnClick()
assert(url.focused and url.selected, "copy action did not select the address")
url:SetText("bad pasted address")
url.scripts.OnTextChanged(url, true)
assert(url.text == downloadURL, "download address remained editable")
local curseforgeURL = "https://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"
local hasCurseForgeLabel = false
for _, fontstring in ipairs(fontstrings) do
    if fontstring.text and fontstring.text:find(curseforgeURL, 1, true) then
        hasCurseForgeLabel = true
        break
    end
end
assert(hasCurseForgeLabel, "setup panel is missing the CurseForge update label")
for _, pair in ipairs({ {"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"},
    {"ENCOUNTER_START", "ENCOUNTER_END"}, {"CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED"},
    {"LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED"} }) do
    event(pair[1])
    assert(not shown() and not url.focused, "gameplay/loading left setup visible or focused")
    drain()
    assert(not shown(), "queued work reopened setup during gameplay/loading")
    event(pair[2])
    drain()
    assert(shown(), "setup did not resume after gameplay/loading")
    assert(panel() == initialPanel, "setup allocated a duplicate panel")
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
