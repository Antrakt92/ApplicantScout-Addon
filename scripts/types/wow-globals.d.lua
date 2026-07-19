---@meta

-- Minimal LuaLS-only definitions for globals that ApplicantScout intentionally
-- reads through _G. The broader WoW API names used directly by the runtime live
-- in lua-diagnostics.luarc.json::diagnostics.globals.

---@type table?
ApplicantScoutFixtureHarness = nil

---@type table
Enum = {}

---@overload fun(functionName: string, hook: function)
---@param target any
---@param method string
---@param hook function
function hooksecurefunc(target, method, hook) end

---@param value any
---@return boolean
function issecretvalue(value) return false end

---@type any
LFGListEntryCreation_IsEditMode = nil
---@type any
LFGListEntryCreation_OnPlayStyleSelectedInternal = nil
---@type any
LFGListEntryCreation_Select = nil
---@type any
LFGListEntryCreation_SetEditMode = nil
---@type any
LFGListEntryCreation_Show = nil
---@type any
LFGListEntryCreation_UpdateValidState = nil
---@type any
LFGListFrame = nil
---@type any
LibStub = nil
---@type any
PVEFrame = nil

---@param sidePanelName string
---@param selection? string
function PVEFrame_ToggleFrame(sidePanelName, selection) end

---@type any
RaiderIO = nil

---@type string
UNKNOWN = ""
---@type string
UNKNOWNOBJECT = ""
