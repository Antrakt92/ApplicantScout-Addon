local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local frames = {}

local function new_widget(name)
    local methods = {}
    local widget = {
        name = name,
        events = {},
        scripts = {},
        shown = false,
        unregisterAllCalls = 0,
    }

    function methods:RegisterEvent(event)
        self.events[event] = true
    end

    function methods:UnregisterAllEvents()
        self.events = {}
        self.unregisterAllCalls = self.unregisterAllCalls + 1
    end

    function methods:SetScript(scriptName, callback)
        self.scripts[scriptName] = callback
    end

    function methods:HookScript(scriptName, callback)
        self.scripts[scriptName] = callback
    end

    function methods:GetName()
        return self.name
    end

    function methods:Show()
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end

    function methods:Hide()
        self.shown = false
    end

    function methods:IsShown()
        return self.shown
    end

    function methods:GetText()
        return self.text or ""
    end

    function methods:SetText(text)
        self.text = text
    end

    function methods:SetChecked(checked)
        self.checked = checked
    end

    function methods:GetChecked()
        return self.checked
    end

    function methods:CreateFontString()
        return new_widget(nil)
    end

    function methods:CreateTexture()
        return new_widget(nil)
    end

    setmetatable(widget, {
        __index = function(_, key)
            return methods[key] or function() end
        end,
    })
    return widget
end

CreateFrame = function(_kind, name, _parent, template)
    local frame = new_widget(name)
    frames[#frames + 1] = frame
    if name then
        _G[name] = frame
        if template == "UICheckButtonTemplate" then
            _G[name .. "Text"] = new_widget(name .. "Text")
        end
    end
    return frame
end

PVEFrame = nil
local harness = env.load_addon({})
assert(type(harness.SettingsAttachState) == "function",
    "settings attach state fixture hook is unavailable")

local state = harness.SettingsAttachState()
assert(not state.attached and state.watcher == nil,
    "settings attachment did not start idle")

local framesBeforeConfig = #frames
SlashCmdList.APSCOUT("config")
local firstState = harness.SettingsAttachState()
assert(not firstState.attached and firstState.watcher ~= nil,
    "first config attempt did not create a pending watcher")
assert(#frames == framesBeforeConfig + 1,
    "first config attempt created more than one watcher frame")

SlashCmdList.APSCOUT("config")
local secondState = harness.SettingsAttachState()
assert(secondState.watcher == firstState.watcher,
    "repeated config attempt replaced the pending watcher")
assert(#frames == framesBeforeConfig + 1,
    "repeated config attempt created a duplicate watcher frame")

local watcher = firstState.watcher
assert(watcher.events.ADDON_LOADED == true
       and type(watcher.scripts.OnEvent) == "function",
    "pending watcher is not subscribed to ADDON_LOADED")

PVEFrame = new_widget("PVEFrame")
watcher.scripts.OnEvent(watcher, "ADDON_LOADED", "Blizzard_GroupFinder")

local attachedState = harness.SettingsAttachState()
assert(attachedState.attached and attachedState.watcher == nil,
    "successful attachment did not clear the watcher sentinel")
assert(watcher.events.ADDON_LOADED == nil
       and watcher.scripts.OnEvent == nil
       and watcher.unregisterAllCalls == 1,
    "successful attachment did not retire the pending watcher")
assert(_G.ApplicantScoutSettingsFrame ~= nil,
    "settings frame was not created after PVEFrame loaded")

local framesAfterAttach = #frames
SlashCmdList.APSCOUT("config")
local finalState = harness.SettingsAttachState()
assert(finalState.attached and finalState.watcher == nil,
    "attached settings panel recreated a watcher")
assert(#frames == framesAfterAttach,
    "opening the attached settings panel created another frame")

print("ok settings-attach-watcher singleton=1 retired=1 attached=1")
