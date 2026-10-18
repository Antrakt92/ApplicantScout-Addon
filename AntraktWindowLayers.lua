-- Shared by independent addons; loading another copy reuses the same window order.
if _G.AntraktWindowLayers then return end
local Layers = { version = 1 }
local entries, order = {}, {}
local owners = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local busy = false

local function invoke(object, method, ...)
    if object and type(object[method]) == "function" then
        local ok, value = pcall(object[method], object, ...)
        if ok then return value end
    end
end

local function level(frame)
    local value = invoke(frame, "GetFrameLevel")
    if type(_G.issecretvalue) == "function" then
        local ok, secret = pcall(_G.issecretvalue, value)
        if not ok or secret then return 0 end
    end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return 0 end
    return value
end

local function visible(frame)
    if type(frame.IsVisible) == "function" then return invoke(frame, "IsVisible") == true end
    return invoke(frame, "IsShown") == true
end

local function walk(frame, visit, seen)
    if not frame or seen[frame] then return end
    seen[frame] = true
    visit(frame)
    if type(frame.GetChildren) == "function" then
        local children = { pcall(frame.GetChildren, frame) }
        if children[1] then
            for index = 2, #children do walk(children[index], visit, seen) end
        end
    end
end

local function focusOwner(frame)
    local root = owners[frame]
    if root then Layers.Focus(root) end
end

local function bind(root, frame, showHook)
    owners[frame] = root
    local flags = hooked[frame] or {}
    hooked[frame] = flags
    if not flags.mouse and type(frame.HookScript) == "function"
        and (type(frame.HasScript) ~= "function" or invoke(frame, "HasScript", "OnMouseDown")) then
        if pcall(frame.HookScript, frame, "OnMouseDown", focusOwner) then flags.mouse = true end
    end
    if showHook and not flags.show and type(frame.HookScript) == "function" then
        if pcall(frame.HookScript, frame, "OnShow", focusOwner) then flags.show = true end
    end
end

local function snapshot(root)
    local entry = entries[root]
    local base = level(root)
    local result = { frames = {}, low = 0, high = 0 }
    local seen = {}
    local function record(frame)
        bind(root, frame)
        local offset = level(frame) - base
        result.low = math.min(result.low, offset)
        result.high = math.max(result.high, offset)
        result.frames[#result.frames + 1] = { frame, offset }
    end
    walk(root, record, seen)
    for _, extra in ipairs(entry.extras) do walk(extra, record, seen) end
    return result
end

function Layers.Focus(root)
    if busy or not entries[root] or not visible(root) then return end
    busy = true
    local previous = order[#order]
    for index = #order, 1, -1 do
        if order[index] == root then table.remove(order, index) end
    end
    order[#order + 1] = root
    if previous and previous ~= root and entries[previous] and entries[previous].onBlur then
        pcall(entries[previous].onBlur)
    end
    -- Snapshot every family before changing parents: WoW propagates level changes
    -- to descendants, so offsets must not be measured during that propagation.
    local snapshots = {}
    for _, owner in ipairs(order) do
        if entries[owner] and visible(owner) then snapshots[#snapshots + 1] = snapshot(owner) end
    end
    local base = 100
    for _, saved in ipairs(snapshots) do
        for _, item in ipairs(saved.frames) do
            invoke(item[1], "SetFrameLevel", base - saved.low + item[2])
        end
        base = base + saved.high - saved.low + 16
    end
    busy = false
end

function Layers.Register(root, onBlur)
    if not root then return end
    if not entries[root] then entries[root] = { extras = {} } end
    if onBlur then entries[root].onBlur = onBlur end
    invoke(root, "SetFrameStrata", "DIALOG")
    walk(root, function(frame) bind(root, frame) end, {})
    bind(root, root, true)
end

function Layers.Detach(root, frame)
    local entry = entries[root]
    if not entry or not frame then return end
    for index = #entry.extras, 1, -1 do
        if entry.extras[index] == frame then table.remove(entry.extras, index) end
    end
    walk(frame, function(child) if owners[child] == root then owners[child] = nil end end, {})
end

function Layers.Unregister(root)
    local entry = entries[root]
    if not entry then return end
    for _, extra in ipairs(entry.extras) do
        walk(extra, function(child) if owners[child] == root then owners[child] = nil end end, {})
    end
    walk(root, function(child) if owners[child] == root then owners[child] = nil end end, {})
    entries[root] = nil
    for index = #order, 1, -1 do if order[index] == root then table.remove(order, index) end end
end

function Layers.Attach(root, frame, relativeLevel)
    if not root or not frame or root == frame then return end
    Layers.Register(root)
    if owners[frame] and owners[frame] ~= root then Layers.Detach(owners[frame], frame) end
    Layers.Unregister(frame)
    local extras = entries[root].extras
    local found = false
    for _, extra in ipairs(extras) do if extra == frame then found = true; break end end
    if not found then extras[#extras + 1] = frame end
    invoke(frame, "SetFrameStrata", "DIALOG")
    invoke(frame, "SetFrameLevel", level(root) + (relativeLevel or 50))
    walk(frame, function(child) bind(root, child) end, {})
    bind(root, frame, true)
end

_G.AntraktWindowLayers = Layers
