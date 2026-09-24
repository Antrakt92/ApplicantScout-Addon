local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

-- Optional read-only baseline probe loads an old addon file from a temp path.
local baselineSourcePath = os.getenv("APPSCOUT_BASELINE_LUA")
if baselineSourcePath then
    local originalLoadfile = loadfile
    loadfile = function(path)
        if path == "ApplicantScout.lua" then
            return originalLoadfile(baselineSourcePath)
        end
        return originalLoadfile(path)
    end
end

local screenWidth, screenHeight = 1600, 1000
GetScreenWidth = function() return screenWidth end
GetScreenHeight = function() return screenHeight end

local inCombat = false
InCombatLockdown = function() return inCombat end

local function nearlyEqual(a, b)
    return math.abs(a - b) < 0.01
end

local function pointOffset(point, width, height)
    local x = point:find("RIGHT", 1, true) and width
        or point:find("LEFT", 1, true) and 0 or width / 2
    local y = point:find("BOTTOM", 1, true) and -height
        or point:find("TOP", 1, true) and 0 or -height / 2
    return x, y
end

local function makeFrame(name, width, height, parent)
    local frame = {
        name = name,
        width = width,
        height = height,
        scale = 1,
        protected = name == "UIParent" or name == "PVEFrame"
                    or name == "CharacterFrame" or name == "PlayerSpellsFrame",
        parent = parent or UIParent,
        shown = false,
        point = "TOPLEFT",
        relativeTo = UIParent,
        relativePoint = "TOPLEFT",
        x = 0,
        y = 0,
        scripts = {},
        setPointCalls = 0,
        secureSetPointCalls = 0,
        secureClearCount = 0,
    }
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetScale() return self.scale end
    function frame:GetEffectiveScale() return self.scale end
    function frame:IsShown() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:GetPoint()
        return self.point, self.relativeTo, self.relativePoint, self.x, self.y
    end
    function frame:GetNumPoints() return self.point and 1 or 0 end
    function frame:GetLeft()
        assert(self.point and self.relativeTo, self.name .. " has no anchor")
        local referenceScale = self.relativeTo:GetEffectiveScale()
        local anchorX = pointOffset(self.relativePoint,
                                    self.relativeTo:GetWidth(), self.relativeTo:GetHeight())
        local ownX = pointOffset(self.point, self.width, self.height)
        local physicalLeft = (self.relativeTo:GetLeft() + anchorX) * referenceScale
                             + (self.x - ownX) * self.scale
        return physicalLeft / self.scale
    end
    function frame:GetTop()
        assert(self.point and self.relativeTo, self.name .. " has no anchor")
        local referenceScale = self.relativeTo:GetEffectiveScale()
        local _, anchorY = pointOffset(self.relativePoint,
                                       self.relativeTo:GetWidth(), self.relativeTo:GetHeight())
        local _, ownY = pointOffset(self.point, self.width, self.height)
        local physicalTop = (self.relativeTo:GetTop() + anchorY) * referenceScale
                            + (self.y - ownY) * self.scale
        return physicalTop / self.scale
    end
    function frame:GetRight() return self:GetLeft() + self.width end
    function frame:GetBottom() return self:GetTop() - self.height end
    function frame:GetCenter()
        return (self:GetLeft() + self:GetRight()) / 2,
               (self:GetTop() + self:GetBottom()) / 2
    end
    function frame:ClearAllPoints() self.point = nil end
    function frame:NativeClearAllPoints() self.point = nil end
    function frame:NativeSetPoint(point, relativeTo, relativePoint, x, y)
        self.point = point
        self.relativeTo = relativeTo or UIParent
        self.relativePoint = relativePoint or point
        self.x, self.y = x or 0, y or 0
    end
    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        self:NativeSetPoint(point, relativeTo, relativePoint, x, y)
        self.setPointCalls = self.setPointCalls + 1
    end
    function frame:SetMovable(enabled) self.movable = enabled end
    function frame:SetClampedToScreen(enabled) self.clamped = enabled end
    function frame:IsUserPlaced() return self.userPlaced == true end
    function frame:SetUserPlaced(placed) self.userPlaced = placed end
    function frame:StartMoving()
        self.moving = true
        self.userPlaced = true
        self.startCount = (self.startCount or 0) + 1
    end
    function frame:StopMovingOrSizing()
        self.moving = false
        self.stopCount = (self.stopCount or 0) + 1
    end
    function frame:HookScript(event, fn) self.scripts[event] = fn end
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    function frame:EnableMouse(enabled) self.mouseEnabled = enabled end
    function frame:RegisterForDrag(button) self.dragButton = button end
    return frame
end

-- Secure snippets use restricted frame proxies, whose geometry writes call
-- native methods without invoking a normal frame's SetPoint hooks.
local rejectSecureSetPoint = false
local persistentlyRejectSecureSetPoint = false
local proxyFrames = setmetatable({}, { __mode = "k" })
local function secureProxy(frame)
    local proxy = setmetatable({}, {
        __index = function(_, key)
            if key == "ClearAllPoints" then
                return function()
                    frame.secureClearCount = frame.secureClearCount + 1
                    frame:NativeClearAllPoints()
                end
            end
            if key == "SetPoint" then
                return function(_, point, relativeTo, relativePoint, x, y)
                    if persistentlyRejectSecureSetPoint then
                        error("simulated persistent secure SetPoint rejection")
                    end
                    if rejectSecureSetPoint then
                        rejectSecureSetPoint = false
                        error("simulated secure SetPoint rejection after ClearAllPoints")
                    end
                    local relativeFrame = proxyFrames[relativeTo] or relativeTo
                    assert(relativeFrame and relativeFrame.protected,
                        "restricted SetPoint requires a protected relative frame")
                    frame.secureSetPointCalls = frame.secureSetPointCalls + 1
                    frame:NativeSetPoint(point, relativeFrame,
                                         relativePoint, x, y)
                end
            end
            local value = frame[key]
            if type(value) == "function" then
                return function(_, ...) return value(frame, ...) end
            end
            return value
        end,
    })
    proxyFrames[proxy] = frame
    return proxy
end

local helpers = {}
local baseCreateFrame = CreateFrame
CreateFrame = function(frameType, name, parent, template)
    if template == "SecureHandlerBaseTemplate" then
        local handler = { refs = {}, attrs = {} }
        function handler:SetFrameRef(key, frame)
            self.refs[key] = secureProxy(frame)
        end
        function handler:GetFrameRef(key) return self.refs[key] end
        function handler:SetAttribute(key, value) self.attrs[key] = value end
        function handler:GetAttribute(key) return self.attrs[key] end
        function handler:Execute(snippet)
            local chunk = assert(loadstring(snippet))
            setfenv(chunk, { self = self, tonumber = tonumber, math = math })
            return chunk()
        end
        return handler
    end
    local helper = baseCreateFrame(frameType, name, parent, template)
    helper.scripts = {}
    helper.shown = false
    helper.Show = function(self) self.shown = true end
    helper.Hide = function(self) self.shown = false end
    helper.IsShown = function(self) return self.shown end
    helper.SetScript = function(self, event, fn)
        self.scripts[event] = fn
        if event == "OnUpdate" then helpers[#helpers + 1] = self end
    end
    helper.HookScript = function(self, event, fn)
        self.scripts[event] = fn
        if event == "OnUpdate" then helpers[#helpers + 1] = self end
    end
    return helper
end

hooksecurefunc = function(target, method, callback)
    assert(type(target) == "table" and type(method) == "string"
           and type(callback) == "function", "unsupported secure hook")
    local original = assert(target[method])
    target[method] = function(self, ...)
        local results = { original(self, ...) }
        callback(self, ...)
        return unpack(results)
    end
end

local scanTick
C_Timer.NewTicker = function(period, callback)
    if period == 0.25 then scanTick = callback end
    return { Cancel = function() end }
end

local function renderFrame()
    for _, helper in ipairs(helpers) do
        if helper:IsShown() and helper.scripts.OnUpdate then
            helper.scripts.OnUpdate(helper, 0.016)
        end
    end
end

local function newWorld()
    helpers = {}
    local root = makeFrame("UIParent", screenWidth, screenHeight)
    root.parent, root.relativeTo = nil, nil
    root.GetLeft = function() return 0 end
    root.GetTop = function(self) return screenHeight / self.scale end
    root.shown = true
    UIParent = root

    local pve = makeFrame("PVEFrame", 563, 428)
    pve:NativeSetPoint("TOPLEFT", root, "TOPLEFT", 100, -84)
    local character = makeFrame("CharacterFrame", 338, 424)
    character:NativeSetPoint("TOPLEFT", root, "TOPLEFT", 85, -84)
    local spellbook = makeFrame("PlayerSpellsFrame", 380, 480)
    spellbook:NativeSetPoint("TOPLEFT", root, "TOPLEFT", 640, -84)
    local settings = makeFrame("ApplicantScoutSettingsFrame", 280, 120, pve)
    settings:NativeSetPoint("TOPLEFT", pve, "TOPLEFT", 20, -20)
    local tooltip = makeFrame("RaiderIO_ProfileTooltip", 160, 280)
    tooltip:NativeSetPoint("TOPLEFT", pve, "TOPRIGHT", 0, 0)

    local title = makeFrame("PVEFrameTitleContainer", 563, 30, pve)
    pve.TitleContainer = title
    PVEFrame, CharacterFrame, PlayerSpellsFrame = pve, character, spellbook
    ApplicantScoutSettingsFrame, RaiderIO_ProfileTooltip = settings, tooltip
    UIPanelWindows = {
        PVEFrame = { area = "left" },
        CharacterFrame = { area = "left" },
        PlayerSpellsFrame = { area = "left" },
    }

    local dockBusy = false
    local dockViaTooltip = false
    local function dockCharacter()
        if dockBusy or not (pve:IsShown() and character:IsShown()) then return end
        local host = dockViaTooltip and tooltip or pve
        local desiredLeft = host:GetRight() * host:GetEffectiveScale()
                            + 4 * character:GetEffectiveScale()
        local desiredTop = host:GetTop() * host:GetEffectiveScale()
        if math.abs(character:GetLeft() * character:GetEffectiveScale()
                    - desiredLeft) < 1
           and math.abs(character:GetTop() * character:GetEffectiveScale()
                    - desiredTop) < 1 then return end
        dockBusy = true
        character:ClearAllPoints()
        character:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
        dockBusy = false
    end
    hooksecurefunc(character, "Show", dockCharacter)
    hooksecurefunc(character, "SetPoint", dockCharacter)
    hooksecurefunc(pve, "SetPoint", dockCharacter)

    return {
        pve = pve,
        character = character,
        spellbook = spellbook,
        settings = settings,
        tooltip = tooltip,
        title = title,
        dockCharacter = dockCharacter,
        useTooltip = function(enabled) dockViaTooltip = enabled end,
    }
end

local function assertStill(frame, left, top, label)
    assert(nearlyEqual(frame:GetLeft(), left)
           and nearlyEqual(frame:GetTop(), top),
        label .. " moved with Group Finder")
end

local function dragAndCheck(world, newLeft)
    local pve, character, title = world.pve, world.character, world.title
    local charLeft, charTop = character:GetLeft(), character:GetTop()
    local spellLeft, spellTop = world.spellbook:GetLeft(), world.spellbook:GetTop()
    local settingsPoint, settingsRelative = world.settings:GetPoint()
    local tooltipPoint, tooltipRelative = world.tooltip:GetPoint()
    title.scripts.OnDragStart(title)
    assert(pve.moving and pve.apsMoving, "Group Finder title drag did not start")
    assert(select(2, character:GetPoint()) == UIParent,
        "dependent CharacterFrame was still anchored to Group Finder at drag start")
    assertStill(character, charLeft, charTop, "CharacterFrame at drag start")
    local skinRedocks = character.setPointCalls
    pve:SetPoint("TOPLEFT", UIParent, "TOPLEFT", newLeft, -150)
    assert(character.setPointCalls > skinRedocks,
        "skin SetPoint hook did not re-dock CharacterFrame during movement")
    renderFrame()
    assertStill(character, charLeft, charTop, "CharacterFrame during drag")
    assert(nearlyEqual(pve:GetLeft(), newLeft), "Group Finder did not move")
    title.scripts.OnDragStop(title)
    renderFrame()
    assertStill(character, charLeft, charTop, "CharacterFrame after drag")
    assertStill(world.spellbook, spellLeft, spellTop, "PlayerSpellsFrame")
    assert(world.spellbook.secureSetPointCalls == 0,
        "ordinary PlayerSpellsFrame was unnecessarily detached")
    assert(world.settings.secureSetPointCalls == 0
           and world.tooltip.secureSetPointCalls == 0,
        "settings or Raider.IO companion was directly repositioned")
    assert(world.settings:GetPoint() == settingsPoint
           and select(2, world.settings:GetPoint()) == settingsRelative,
        "ApplicantScout settings anchor was changed")
    assert(world.tooltip:GetPoint() == tooltipPoint
           and select(2, world.tooltip:GetPoint()) == tooltipRelative,
        "Raider.IO tooltip anchor was changed")
end

ApplicantScoutDB = { enabled = false }
local world = newWorld()
local harness = env.load_addon({})
harness.FireEvent("ADDON_LOADED", "ApplicantScout")
harness.SetupPVEFrameMovement()
assert(type(world.title.scripts.OnDragStart) == "function",
    "Group Finder title drag was not initialized")

-- Both opening orders must be handled after the skin docks CharacterFrame.
world.pve:Show()
world.character:Show()
assert(world.character:GetPoint() == "TOPLEFT"
       and select(2, world.character:GetPoint()) == world.pve,
    "skin did not dock CharacterFrame to Group Finder")
dragAndCheck(world, 370)

-- Blizzard's native panel layout can re-anchor PVEFrame after a completed
-- drag. The subsequent addon SetPoint invokes the skin's docking hook even
-- though CharacterFrame was independent before the ticker ran.
assert(type(scanTick) == "function", "Group Finder relayout ticker is missing")
world.pve:NativeSetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -84)
local relayoutCharacterLeft = world.character:GetLeft()
local relayoutCharacterTop = world.character:GetTop()
scanTick()
assert(nearlyEqual(world.pve:GetLeft(), 370),
    "ticker did not restore the session Group Finder position")
assertStill(world.character, relayoutCharacterLeft, relayoutCharacterTop,
    "CharacterFrame during ticker restore")

world.character:Hide()
world.pve:Hide()
world.character:NativeSetPoint("TOPLEFT", UIParent, "TOPLEFT", 85, -84)
world.character:Show()
world.pve:Show()
world.pve:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 150, -84)
assert(select(2, world.character:GetPoint()) == world.pve,
    "reverse opening order did not dock CharacterFrame")
dragAndCheck(world, 420)

-- Raider.IO can sit between the skin's CharacterFrame anchor and PVEFrame.
world.useTooltip(true)
world.dockCharacter()
assert(select(2, world.character:GetPoint()) == world.tooltip,
    "skin did not dock through Raider.IO tooltip")
dragAndCheck(world, 510)

-- Repeated drags must not accumulate an anchor back to the moved panel.
world.dockCharacter()
dragAndCheck(world, 590)

world.dockCharacter()
local rejectedLeft, rejectedTop = world.character:GetLeft(), world.character:GetTop()
local rejectedRelative = select(2, world.character:GetPoint())
local clearsBeforeRejectedStart = world.character.secureClearCount
rejectSecureSetPoint = true
world.title.scripts.OnDragStart(world.title)
assert(world.character.secureClearCount == clearsBeforeRejectedStart + 1,
    "secure failure was not exercised after clearing CharacterFrame anchors")
assert(not world.pve.apsMoving and not world.pve.moving,
    "Group Finder drag continued after dependent panel detachment failed")
assert(select(2, world.character:GetPoint()) == rejectedRelative,
    "failed secure positioner did not restore CharacterFrame's old anchor")
assertStill(world.character, rejectedLeft, rejectedTop,
    "CharacterFrame after failed secure detachment")

world.dockCharacter()
local abortLeft, abortTop = world.character:GetLeft(), world.character:GetTop()
world.title.scripts.OnDragStart(world.title)
world.pve:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 620, -150)
rejectSecureSetPoint = true
renderFrame()
assert(not world.pve.apsMoving and not world.pve.moving,
    "watcher continued movement after dependent panel repair failed")
assertStill(world.character, abortLeft, abortTop,
    "CharacterFrame after failed repair")
for _, helper in ipairs(helpers) do
    assert(not helper:IsShown(), "watcher stayed active after failed repair")
end

-- A persistent secure failure must retain the first screen snapshot. Neither
-- the ticker nor a second drag may adopt the displaced, skin-docked pixels.
world.dockCharacter()
local originalLeft, originalTop = world.character:GetLeft(), world.character:GetTop()
world.title.scripts.OnDragStart(world.title)
world.pve:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 520, -150)
persistentlyRejectSecureSetPoint = true
renderFrame()
assert(not world.pve.apsMoving and not world.pve.moving,
    "persistent repair failure did not stop the drag")
assert(not nearlyEqual(world.character:GetLeft(), originalLeft),
    "persistent failure scenario did not displace CharacterFrame")
local startsBeforeBlockedRetry = world.pve.startCount
scanTick()
world.title.scripts.OnDragStart(world.title)
assert(world.pve.startCount == startsBeforeBlockedRetry and not world.pve.apsMoving,
    "a new drag started while the old CharacterFrame snapshot was unrepaired")
persistentlyRejectSecureSetPoint = false
scanTick()
assertStill(world.character, originalLeft, originalTop,
    "CharacterFrame after persistent failure recovery")

world.dockCharacter()
local combatLeft, combatTop = world.character:GetLeft(), world.character:GetTop()
world.title.scripts.OnDragStart(world.title)
assert(world.pve.apsMoving, "mid-drag combat scenario did not start")
local writesBeforeCombat = world.character.secureSetPointCalls
local normalStop = world.pve.StopMovingOrSizing
world.pve.StopMovingOrSizing = function()
    error("simulated protected native stop during combat")
end
inCombat = true
renderFrame()
assert(world.character.secureSetPointCalls == writesBeforeCombat,
    "combat watcher issued a protected CharacterFrame position write")
assert(not world.pve.apsMoving,
    "Group Finder watcher kept a drag active after combat began")
assert(world.pve.apsStopPending and world.pve.moving,
    "rejected native stop was not deferred until after combat")
for _, helper in ipairs(helpers) do
    assert(not helper:IsShown(), "Group Finder drag watcher stayed active in combat")
end
inCombat = false
world.pve.StopMovingOrSizing = normalStop
scanTick()
assert(not world.pve.apsStopPending and not world.pve.moving,
    "native drag did not stop after combat ended")
assertStill(world.character, combatLeft, combatTop,
    "CharacterFrame after combat recovery")

local startsBeforeCombat = world.pve.startCount
inCombat = true
world.title.scripts.OnDragStart(world.title)
assert(world.pve.startCount == startsBeforeCombat,
    "protected Group Finder drag started in combat")
inCombat = false

-- Reload resets session placement and creates a fresh UI without old hooks.
harness.FireEvent("PLAYER_LOGOUT")
assert(ApplicantScoutDB.pveFramePosition == nil,
    "Group Finder placement was persisted across reload")
world = newWorld()
scanTick = nil
local reloadedHarness = env.load_addon({})
reloadedHarness.FireEvent("ADDON_LOADED", "ApplicantScout")
reloadedHarness.SetupPVEFrameMovement()
world.pve:Show()
world.character:Show()
assert(nearlyEqual(world.pve:GetLeft(), 100),
    "fresh session restored the previous Group Finder position")
dragAndCheck(world, 330)

-- Saved positions are screen pixels; frame anchor offsets use local units.
-- Different effective scales catch use of a raw GetLeft/GetTop offset.
world = newWorld()
UIParent.scale = 0.8
UIParent.width, UIParent.height = screenWidth / UIParent.scale,
                                  screenHeight / UIParent.scale
world.character.scale = 1.25
local scaledHarness = env.load_addon({})
scaledHarness.FireEvent("ADDON_LOADED", "ApplicantScout")
scaledHarness.SetupPVEFrameMovement()
world.pve:Show()
world.character:Show()
assert(select(2, world.character:GetPoint()) == world.pve,
    "scaled CharacterFrame did not dock before movement")
dragAndCheck(world, 290)

print("ok pve-frame-docking direct=1 reverse=1 raiderio=1 repeat=1 combat=guarded reload=fresh scale=mixed")
