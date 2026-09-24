local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local scanTick
C_Timer.NewTicker = function(period, callback)
    if period == 0.25 then scanTick = callback end
    return { Cancel = function() end }
end

local function newFrame()
    local function newSurface(name, objectType, mouseEnabled)
        local surface = {
            name = name,
            objectType = objectType or "Frame",
            mouseEnabled = mouseEnabled == true,
            shown = true,
            scripts = {},
            children = {},
        }
        function surface:GetName() return self.name end
        function surface:GetParent() return self.parent end
        function surface:GetChildren() return unpack(self.children) end
        function surface:IsShown() return self.shown end
        function surface:IsObjectType(kind)
            return self.objectType == kind or kind == "Frame"
                   and (self.objectType == "Button"
                        or self.objectType == "EditBox"
                        or self.objectType == "Slider")
        end
        function surface:IsMouseEnabled() return self.mouseEnabled end
        function surface:EnableMouse(enabled) self.mouseEnabled = enabled end
        function surface:RegisterForDrag(button) self.dragButton = button end
        function surface:GetScript(script) return self.scripts[script] end
        function surface:HasScript(script) return self.scripts[script] ~= nil end
        function surface:HookScript(script, callback) self.scripts[script] = callback end
        function surface:addChild(child)
            child.parent = self
            self.children[#self.children + 1] = child
            return child
        end
        return surface
    end

    local title = newSurface("PVEFrameTitleContainer", "Frame", false)
    local body = newSurface("PVEFrameBody", "Frame", true)
    local nested = newSurface("PVEFrameNestedButton", "Button", true)
    local nativeDrag = newSurface("PVEFrameNativeDragButton", "Button", true)
    nativeDrag.scripts.OnDragStart = function() end
    local receiveDrag = newSurface("PVEFrameDropTarget", "Frame", true)
    receiveDrag.scripts.OnReceiveDrag = function() end
    receiveDrag:addChild(newSurface("PVEFrameDropTargetChild", "Button", true))
    local editBox = newSurface("PVEFrameSearchEditBox", "EditBox", true)
    local slider = newSurface("PVEFrameScrollBar", "Slider", true)
    slider:addChild(newSurface("PVEFrameScrollThumb", "Button", true))
    local modernScroll = newSurface("PVEFrameModernScrollBar", "Frame", true)
    local modernThumb = modernScroll:addChild(
        newSurface("PVEFrameModernScrollThumb", "Button", true))
    function modernScroll:GetThumb() return modernThumb end
    function modernScroll:OnThumbMouseDown() end
    local inputHost = newSurface("PVEFrameInputHost", "Frame", true)
    inputHost.EditBox = inputHost:addChild(
        newSurface("PVEFrameInputHostEditBox", "EditBox", true))
    local settings = newSurface("ApplicantScoutSettingsFrame", "Frame", true)
    settings:addChild(newSurface("ApplicantScoutSettingsButton", "Button", true))
    local clickCount = 0
    nested.scripts.OnClick = function() clickCount = clickCount + 1 end
    body:addChild(nested)
    body:addChild(nativeDrag)
    body:addChild(receiveDrag)
    body:addChild(editBox)
    body:addChild(slider)
    body:addChild(modernScroll)
    body:addChild(inputHost)

    local frame = {
        name = "PVEFrame",
        objectType = "Frame",
        TitleContainer = title,
        shown = true,
        point = "TOPLEFT",
        relativeTo = UIParent,
        relativePoint = "TOPLEFT",
        x = 100,
        y = -84,
        startCount = 0,
        stopCount = 0,
        restoreCount = 0,
        mouseEnabled = true,
        scripts = {},
        children = {},
    }
    for key, value in pairs(newSurface("PVEFrame", "Frame", true)) do
        if type(value) == "function" then frame[key] = value end
    end
    frame:addChild(title)
    frame:addChild(body)
    frame:addChild(settings)
    ApplicantScoutSettingsFrame = settings
    function frame:IsShown() return self.shown end
    function frame:SetMovable(enabled) self.movable = enabled end
    function frame:SetClampedToScreen(enabled) self.clamped = enabled end
    function frame:StartMoving()
        self.startCount = self.startCount + 1
        self.userPlaced = true
    end
    function frame:StopMovingOrSizing() self.stopCount = self.stopCount + 1 end
    function frame:GetPoint()
        return self.point, self.relativeTo, self.relativePoint, self.x, self.y
    end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        if self.rejectNextSavedPoint and x == 420 then
            self.rejectNextSavedPoint = false
            error("simulated protected SetPoint rejection")
        end
        assert(relativeTo == UIParent, "movement must anchor only to UIParent")
        self.point, self.relativeTo, self.relativePoint, self.x, self.y =
            point, relativeTo, relativePoint, x, y
        self.restoreCount = self.restoreCount + 1
    end
    function frame:SetUserPlaced(placed)
        if self.rejectUserPlaced then error("simulated SetUserPlaced rejection") end
        self.userPlaced = placed
    end
    function frame:IsUserPlaced() return self.userPlaced == true end
    return frame, title, body, nested, nativeDrag, receiveDrag, editBox, slider,
           modernScroll, inputHost, settings,
           function() return clickCount end, newSurface
end

local frame, title, body, nested, nativeDrag, receiveDrag, editBox, slider,
      modernScroll, inputHost, settings,
      clickCount, newSurface = newFrame()
local nativeDragStart = nativeDrag.scripts.OnDragStart
PVEFrame = frame
local companionPanels = {
    CharacterFrame = { x = 85, y = -84, calls = 0 },
    PlayerSpellsFrame = { x = 640, y = -84, calls = 0 },
}
for name, panel in pairs(companionPanels) do
    function panel:GetPoint()
        return "TOPLEFT", UIParent, "TOPLEFT", self.x, self.y
    end
    function panel:ClearAllPoints() self.calls = self.calls + 1 end
    function panel:SetPoint(_, _, _, x, y)
        self.calls = self.calls + 1
        self.x, self.y = x, y
    end
    _G[name] = panel
end
SetUIPanelAttribute = function()
    error("ApplicantScout must not alter Blizzard's shared panel layout")
end
local inCombat = false
InCombatLockdown = function() return inCombat end
IsAltKeyDown = function() return false end

-- This key exists in older SavedVariables. A new session must discard it
-- before any shown Group Finder can visibly jump to the old location.
ApplicantScoutDB = {
    enabled = false,
    pveFramePosition = { point = "TOPLEFT", x = 420, y = -165 },
}
local harness = env.load_addon({})
harness.FireEvent("ADDON_LOADED", "ApplicantScout")
assert(ApplicantScoutDB.pveFramePosition == nil,
    "legacy cross-reload Group Finder position was not migrated away")
harness.SetupPVEFrameMovement()
assert(scanTick and frame.apsMovementSetup and frame.movable and frame.clamped,
    "Group Finder movement did not initialize")
assert(title.mouseEnabled and title.dragButton == "LeftButton",
    "the title bar did not register left-button dragging")
assert(type(title.scripts.OnDragStart) == "function"
       and type(title.scripts.OnDragStop) == "function",
    "the title bar lacks drag handlers")
assert(type(frame.scripts.OnDragStart) == "function"
       and type(frame.scripts.OnDragStop) == "function",
    "Group Finder body did not register its own drag handlers")
assert(type(body.scripts.OnDragStart) == "function"
       and type(nested.scripts.OnDragStart) == "function",
    "mouse-enabled nested content did not receive drag handlers")
assert(nativeDrag.scripts.OnDragStart == nativeDragStart
       and nativeDrag.dragButton == nil,
    "a native drag control was taken over")
assert(receiveDrag.dragButton == nil
       and receiveDrag.children[1].dragButton == nil,
    "a native drop target subtree was taken over")
assert(editBox.dragButton == nil and editBox.scripts.OnDragStart == nil,
    "search EditBox should retain its text-selection behavior")
assert(slider.dragButton == nil and slider.children[1].dragButton == nil,
    "scrollbar thumb must retain its native drag behavior")
assert(modernScroll.dragButton == nil
       and modernScroll.children[1].dragButton == nil,
    "modern scrollbar thumb must retain its native drag behavior")
assert(inputHost.dragButton == nil and inputHost.EditBox.dragButton == nil,
    "input host must retain text selection and focus behavior")
assert(settings.dragButton == nil and settings.children[1].dragButton == nil,
    "ApplicantScout settings controls should not move Group Finder")
local beforeClick = clickCount()
nested.scripts.OnClick(nested)
assert(clickCount() == beforeClick + 1,
    "drag registration broke an ordinary nested button click")

local startsBeforeRoot = frame.startCount
frame.scripts.OnDragStart(frame)
assert(frame.startCount == startsBeforeRoot + 1 and frame.apsMoving,
    "dragging an exposed Group Finder root area did not start")
frame.scripts.OnDragStop(frame)
local startsBeforeBody = frame.startCount
body.scripts.OnDragStart(body)
assert(frame.startCount == startsBeforeBody + 1 and frame.apsMoving,
    "dragging Group Finder body did not move the root panel")
body.scripts.OnDragStop(body)
local startsBeforeNested = frame.startCount
nested.scripts.OnDragStart(nested)
assert(frame.startCount == startsBeforeNested + 1 and frame.apsMoving,
    "dragging a nested mouse surface did not move Group Finder")
nested.scripts.OnDragStop(nested)

local dynamic = newSurface("PVEFrameDynamicTextHost", "Button", true)
body:addChild(dynamic)
scanTick()
assert(type(dynamic.scripts.OnDragStart) == "function",
    "a dynamically created nested mouse surface was missed")
local startsBeforeReparent = frame.startCount
dynamic.parent = UIParent
dynamic.scripts.OnDragStart(dynamic)
assert(frame.startCount == startsBeforeReparent and not frame.apsMoving,
    "a reparented surface could still move Group Finder")
local hidden = newSurface("PVEFramePooledRow", "Button", true)
hidden.shown = false
body:addChild(hidden)
scanTick()
assert(hidden.dragButton == nil,
    "a hidden pooled row was registered before it became visible")
hidden.shown = true
scanTick()
assert(type(hidden.scripts.OnDragStart) == "function",
    "a newly visible pooled row was not registered")
local initialRestoreCount = frame.restoreCount
scanTick()
assert(frame.point == "TOPLEFT" and frame.x == 100 and frame.y == -84
       and frame.restoreCount == initialRestoreCount,
    "old SavedVariables moved Group Finder during a fresh session")

-- Plain title dragging should work without knowing an undocumented modifier.
local pointsBeforeDragStart = frame.restoreCount
local startsBeforeTitle = frame.startCount
local stopsBeforeTitle = frame.stopCount
title.scripts.OnDragStart(title)
assert(frame.startCount == startsBeforeTitle + 1,
    "plain title drag did not start")
assert(frame.restoreCount == pointsBeforeDragStart,
    "drag start reanchored Group Finder before Blizzard began movement")
assert(not frame:IsUserPlaced(),
    "dragging Group Finder changed Blizzard's user-placed flag")
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 420, -165)
title.scripts.OnDragStop(title)
assert(frame.stopCount == stopsBeforeTitle + 1 and not frame.apsMoving,
    "title drag did not stop")
assert(not frame:IsUserPlaced(),
    "stopping Group Finder drag changed Blizzard's user-placed flag")
assert(frame.point == "TOPLEFT" and frame.relativePoint == "TOPLEFT"
       and frame.x == 420 and frame.y == -165,
    "dragging did not keep the Group Finder's point")
assert(ApplicantScoutDB.pveFramePosition == nil,
    "dragged Group Finder position leaked into SavedVariables")

-- Existing Blizzard/user state must also survive a drag.
frame.userPlaced = true
title.scripts.OnDragStart(title)
title.scripts.OnDragStop(title)
assert(frame:IsUserPlaced(), "a pre-existing user-placed flag was cleared")
frame.userPlaced = false

local function blizzardRelayout()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -84)
end

local function assertCompanionPanelsUnchanged()
    for name, panel in pairs(companionPanels) do
        assert(panel.calls == 0 and panel.y == -84
               and panel.x == (name == "CharacterFrame" and 85 or 640),
            name .. " was moved with Group Finder")
    end
end

-- QR capture may be disabled while the user still uses Group Finder.
ApplicantScoutDB.enabled = false
for _ = 1, 2 do
    blizzardRelayout()
    scanTick()
    assert(frame.x == 420 and frame.y == -165,
        "Blizzard relayout was not corrected while transport was disabled")
    assertCompanionPanelsUnchanged()
end
local stableCount = frame.restoreCount
scanTick()
assert(frame.restoreCount == stableCount,
    "a stable Group Finder position was rewritten on every ticker call")

frame.shown = false
blizzardRelayout()
scanTick()
assert(frame.x == 100 and frame.y == -84,
    "a hidden Group Finder window was repositioned")
frame.shown = true
scanTick()
assert(frame.x == 420 and frame.y == -165,
    "a reopened Group Finder window did not restore its session position")
assertCompanionPanelsUnchanged()

-- A rejected SetPoint must not leave the panel unanchored or crash the ticker.
blizzardRelayout()
frame.rejectNextSavedPoint = true
scanTick()
assert(frame.point == "TOPLEFT" and frame.x == 100,
    "rejected restore lost the previous Blizzard anchor")
scanTick()
assert(frame.x == 420, "restore did not recover after a transient rejection")

-- Repeated SavedVariables normalization must preserve in-memory placement.
harness.FireEvent("ADDON_LOADED", "ApplicantScout")
blizzardRelayout()
scanTick()
assert(frame.x == 420 and frame.y == -165,
    "repeated DB initialization lost the session position")
assert(ApplicantScoutDB.pveFramePosition == nil,
    "repeated DB initialization persisted Group Finder placement")

title.scripts.OnDragStart(title)
frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", -540, -125)
scanTick()
assert(frame.relativePoint == "TOPRIGHT" and frame.x == -540,
    "the ticker interrupted an active Group Finder drag")
title.scripts.OnDragStop(title)
assert(frame.relativePoint == "TOPRIGHT" and frame.x == -540,
    "dragging lost the Group Finder's relative point")
blizzardRelayout()
scanTick()
assert(frame.point == "TOPLEFT" and frame.relativePoint == "TOPRIGHT"
       and frame.x == -540 and frame.y == -125,
    "a nonmatching anchor pair did not restore within the session")
assertCompanionPanelsUnchanged()

-- If another addon supplies an anchor relative to a different panel, do not
-- save that relationship as if it were a UIParent coordinate.
title.scripts.OnDragStart(title)
frame.point, frame.relativeTo, frame.relativePoint, frame.x, frame.y =
    "TOPLEFT", CharacterFrame, "TOPLEFT", 500, -125
title.scripts.OnDragStop(title)
blizzardRelayout()
scanTick()
assert(frame.point == "TOPLEFT" and frame.relativeTo == UIParent
       and frame.relativePoint == "TOPRIGHT"
       and frame.x == -540 and frame.y == -125,
    "an external relative anchor overwrote the last valid session position")

-- A combat tick must leave a protected panel alone, then restore it afterward.
blizzardRelayout()
inCombat = true
scanTick()
assert(frame.x == 100 and frame.y == -84,
    "Group Finder position was changed in combat")
local startsBeforeCombat = frame.startCount
title.scripts.OnDragStart(title)
assert(frame.startCount == startsBeforeCombat,
    "Group Finder drag started in combat")
nested.scripts.OnDragStart(nested)
assert(frame.startCount == startsBeforeCombat,
    "nested Group Finder drag started in combat")
inCombat = false
scanTick()
assert(frame.x == -540 and frame.y == -125
       and frame.relativePoint == "TOPRIGHT",
    "Group Finder position did not recover after combat")
assertCompanionPanelsUnchanged()

-- If combat interrupts a drag, restore StartMoving's native flag even when
-- StopMovingOrSizing and SetUserPlaced are temporarily rejected.
frame.userPlaced = false
title.scripts.OnDragStart(title)
frame.userPlaced = true
local normalStop = frame.StopMovingOrSizing
frame.StopMovingOrSizing = function() error("simulated protected stop") end
frame.rejectUserPlaced = true
inCombat = true
title.scripts.OnDragStop(title)
assert(not frame.apsMoving and frame.apsWasUserPlaced == false,
    "interrupted drag lost the original user-placed state")
frame.StopMovingOrSizing = normalStop
inCombat = false
frame.rejectUserPlaced = false
scanTick()
assert(not frame:IsUserPlaced() and frame.apsWasUserPlaced == nil,
    "native panel flag did not recover after combat")

-- If the immediate flag reset fails, abort movement and retry on the ticker.
local stopsBeforeRejectedStart = frame.stopCount
frame.rejectUserPlaced = true
title.scripts.OnDragStart(title)
assert(not frame.apsMoving and frame.apsWasUserPlaced == false
       and frame.stopCount == stopsBeforeRejectedStart + 1,
    "drag continued after the native flag could not be restored")
frame.rejectUserPlaced = false
scanTick()
assert(not frame:IsUserPlaced() and frame.apsWasUserPlaced == nil,
    "native flag did not recover after a rejected drag start")

-- A protected native start failure must not leave the active drag source set.
local normalStart = frame.StartMoving
local stopsBeforeFailedStart = frame.stopCount
frame.StartMoving = function() error("simulated protected start") end
nested.scripts.OnDragStart(nested)
assert(not frame.apsMoving and frame.stopCount == stopsBeforeFailedStart + 1,
    "failed native start left Group Finder moving")
frame.StartMoving = normalStart
local startsAfterFailedStart = frame.startCount
nested.scripts.OnDragStop(nested)
assert(frame.startCount == startsAfterFailedStart and not frame.apsMoving,
    "failed drag acquired a stale nested active surface")

harness.FireEvent("PLAYER_LOGOUT")
assert(ApplicantScoutDB.pveFramePosition == nil,
    "logout persisted a Group Finder position across reload")

-- /reload creates a fresh addon state and Blizzard frame while SavedVariables
-- persist. The old session's moved position must never cause a visible jump.
frame, title = newFrame()
PVEFrame = frame
scanTick = nil
local reloadedHarness = env.load_addon({})
reloadedHarness.FireEvent("ADDON_LOADED", "ApplicantScout")
reloadedHarness.SetupPVEFrameMovement()
assert(scanTick and frame.apsMovementSetup,
    "reloaded Group Finder movement did not initialize")
local reloadRestoreCount = frame.restoreCount
scanTick()
assert(frame.point == "TOPLEFT" and frame.x == 100 and frame.y == -84
       and frame.restoreCount == reloadRestoreCount
       and ApplicantScoutDB.pveFramePosition == nil,
    "Group Finder jumped to the previous session's position after reload")
assertCompanionPanelsUnchanged()

-- BlizzMove owns this panel when loaded; no additional surface is registered.
local originalIsAddOnLoaded = C_AddOns.IsAddOnLoaded
C_AddOns.IsAddOnLoaded = function(name)
    return name == "BlizzMove"
end
frame, title, body, nested = newFrame()
PVEFrame = frame
local blizzMoveHarness = env.load_addon({})
blizzMoveHarness.FireEvent("ADDON_LOADED", "ApplicantScout")
blizzMoveHarness.SetupPVEFrameMovement()
assert(not frame.apsMovementSetup and not frame.scripts.OnDragStart
       and not title.scripts.OnDragStart and not body.scripts.OnDragStart
       and not nested.scripts.OnDragStart,
    "ApplicantScout competed with BlizzMove for Group Finder drag")
C_AddOns.IsAddOnLoaded = originalIsAddOnLoaded

-- Other addons may anchor CharacterFrame to PVEFrame; this fixture verifies
-- ApplicantScout's own panel calls, not third-party docking behavior in game.
print("ok pve-frame-movement surfaces=root/body/nested controls=preserved combat=guarded blizzmove=skipped")
