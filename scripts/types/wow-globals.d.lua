---@meta

-- Minimal LuaLS-only definitions for globals that ApplicantScout intentionally
-- reads through _G. The broader WoW API names used directly by the runtime live
-- in lua-diagnostics.luarc.json::diagnostics.globals.

---@type table
Enum = {}

---@type any
C_PlayerInteractionManager = nil

---@class ChallengeModeAPI
---@field IsChallengeModeActive fun(): boolean
---@type ChallengeModeAPI?
C_ChallengeMode = nil

---@class InstanceEncounterAPI
---@field IsEncounterInProgress fun(): boolean
---@type InstanceEncounterAPI?
C_InstanceEncounter = nil

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
---@type number
LE_PARTY_CATEGORY_HOME = 1
---@type number
LE_PARTY_CATEGORY_INSTANCE = 2
---@type any
LibStub = nil
---@type any
PVEFrame = nil

---@class PixelUtilAPI
---@field ConvertPixelsToUIForRegion fun(desiredPixels: number, region: any): number
---@type PixelUtilAPI?
PixelUtil = nil

---@return number physicalWidth
---@return number physicalHeight
function GetPhysicalScreenSize() end

---@param sidePanelName string
---@param selection? string
function PVEFrame_ToggleFrame(sidePanelName, selection) end

---@type any
RaiderIO = nil

---@type any
securecallfunction = nil

---@type string
UNKNOWN = ""
---@type string
UNKNOWNOBJECT = ""
