local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local scanTick
C_Timer.NewTicker = function(period, callback)
    if period == 0.25 then scanTick = callback end
    return { Cancel = function() end }
end

local title = { scripts = {} }
function title:EnableMouse(enabled) self.mouseEnabled = enabled end
function title:RegisterForDrag(button) self.dragButton = button end
function title:HookScript(script, callback) self.scripts[script] = callback end

local frame = {
    TitleContainer = title,
    shown = true,
    point = "TOPLEFT",
    relativePoint = "TOPLEFT",
    x = 100,
    y = -84,
    startCount = 0,
    stopCount = 0,
    restoreCount = 0,
}
function frame:IsShown() return self.shown end
function frame:SetMovable(enabled) self.movable = enabled end
function frame:SetClampedToScreen(enabled) self.clamped = enabled end
function frame:StartMoving()
    self.startCount = self.startCount + 1
    self.userPlaced = true
end
function frame:StopMovingOrSizing() self.stopCount = self.stopCount + 1 end
function frame:GetPoint()
    return self.point, UIParent, self.relativePoint, self.x, self.y
end
function frame:ClearAllPoints() self.point = nil end
function frame:SetPoint(point, relativeTo, relativePoint, x, y)
    if self.rejectNextSavedPoint and x == 420 then
        self.rejectNextSavedPoint = false
        error("simulated protected SetPoint rejection")
    end
    assert(relativeTo == UIParent, "movement must anchor only to UIParent")
    self.point, self.relativePoint, self.x, self.y = point, relativePoint, x, y
    self.restoreCount = self.restoreCount + 1
end
function frame:SetUserPlaced(placed)
    if self.rejectUserPlaced then error("simulated SetUserPlaced rejection") end
    self.userPlaced = placed
end
function frame:IsUserPlaced() return self.userPlaced == true end

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

local harness = env.load_addon({})
ApplicantScoutDB = { enabled = false }
harness.SetupPVEFrameMovement()
assert(scanTick and frame.apsMovementSetup and frame.movable and frame.clamped,
    "Group Finder movement did not initialize")
assert(title.mouseEnabled and title.dragButton == "LeftButton",
    "the title bar did not register left-button dragging")
assert(type(title.scripts.OnDragStart) == "function"
       and type(title.scripts.OnDragStop) == "function",
    "the title bar lacks drag handlers")

-- Plain title dragging should work without knowing an undocumented modifier.
title.scripts.OnDragStart(title)
assert(frame.startCount == 1, "plain title drag did not start")
assert(not frame:IsUserPlaced(),
    "dragging Group Finder changed Blizzard's user-placed flag")
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 420, -165)
title.scripts.OnDragStop(title)
assert(frame.stopCount == 1 and not frame.apsMoving,
    "title drag did not stop")
assert(not frame:IsUserPlaced(),
    "stopping Group Finder drag changed Blizzard's user-placed flag")
assert(ApplicantScoutDB.pveFramePosition
       and ApplicantScoutDB.pveFramePosition.x == 420
       and ApplicantScoutDB.pveFramePosition.y == -165,
    "the dragged Group Finder position was not saved")

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
    "a reopened Group Finder window did not restore its position")
assertCompanionPanelsUnchanged()

-- A rejected SetPoint must not leave the panel unanchored or crash the ticker.
blizzardRelayout()
frame.rejectNextSavedPoint = true
scanTick()
assert(frame.point == "TOPLEFT" and frame.x == 100,
    "rejected restore lost the previous Blizzard anchor")
scanTick()
assert(frame.x == 420, "restore did not recover after a transient rejection")

-- A relayout between a drag and logout must not overwrite the saved position.
blizzardRelayout()
harness.FireEvent("PLAYER_LOGOUT")
assert(ApplicantScoutDB.pveFramePosition.x == 420
       and ApplicantScoutDB.pveFramePosition.y == -165,
    "logout saved Blizzard's temporary panel slot over the dragged position")
scanTick()

title.scripts.OnDragStart(title)
frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", -540, -125)
scanTick()
assert(frame.relativePoint == "TOPRIGHT" and frame.x == -540,
    "the ticker interrupted an active Group Finder drag")
title.scripts.OnDragStop(title)
assert(ApplicantScoutDB.pveFramePosition.relativePoint == "TOPRIGHT",
    "the dragged anchor's relative point was not saved")
blizzardRelayout()
scanTick()
assert(frame.point == "TOPLEFT" and frame.relativePoint == "TOPRIGHT"
       and frame.x == -540 and frame.y == -125,
    "a nonmatching anchor pair did not restore accurately")
assertCompanionPanelsUnchanged()

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

ApplicantScoutDB.pveFramePosition = {
    point = "TOPLEFT", relativePoint = "INVALID", x = 0, y = 0,
}
local beforeInvalid = frame.restoreCount
scanTick()
assert(ApplicantScoutDB.pveFramePosition == nil
       and frame.restoreCount == beforeInvalid,
    "an invalid saved anchor was applied instead of discarded")

print("ok pve-frame-movement plain-drag=1 repeated-relayout=2 combat=guarded")
