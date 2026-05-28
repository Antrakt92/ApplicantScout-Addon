local TWO32 = 4294967296

local function norm32(n)
    n = math.floor(tonumber(n) or 0) % TWO32
    if n < 0 then n = n + TWO32 end
    return n
end

local function bit_loop(a, b, op)
    a, b = norm32(a), norm32(b)
    local out, bitval = 0, 1
    for _ = 1, 32 do
        local abit = a % 2
        local bbit = b % 2
        if op(abit, bbit) then out = out + bitval end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bitval = bitval * 2
    end
    return out
end

bit = {
    bxor = function(a, b)
        return bit_loop(a, b, function(left, right) return left ~= right end)
    end,
    band = function(a, b)
        return bit_loop(a, b, function(left, right) return left == 1 and right == 1 end)
    end,
    rshift = function(a, bits)
        return math.floor(norm32(a) / (2 ^ bits))
    end,
}

SlashCmdList = {}
C_AddOns = {
    GetAddOnMetadata = function(_addon, field)
        if field == "Version" then return "0.3.4-fixture" end
        return nil
    end,
}

local function frame_stub()
    return {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        UnregisterAllEvents = function() end,
        SetScript = function() end,
        HookScript = function() end,
        SetSize = function() end,
        SetPoint = function() end,
        SetFrameStrata = function() end,
        SetBackdrop = function() end,
        SetBackdropColor = function() end,
        SetBackdropBorderColor = function() end,
        EnableMouse = function() end,
        SetMovable = function() end,
        RegisterForDrag = function() end,
        Hide = function() end,
        Show = function() end,
        IsShown = function() return false end,
        CreateTexture = function()
            return {
                SetColorTexture = function() end,
                SetPoint = function() end,
                SetSize = function() end,
                Show = function() end,
                Hide = function() end,
            }
        end,
        CreateFontString = function()
            return {
                SetPoint = function() end,
                SetText = function() end,
                SetTextColor = function() end,
                SetFontObject = function() end,
                SetJustifyH = function() end,
            }
        end,
    }
end

CreateFrame = function() return frame_stub() end
UIParent = frame_stub()
C_Timer = {
    NewTicker = function() return { Cancel = function() end } end,
    After = function() end,
}

GetBuildInfo = function() return "12.0.5" end
GetCurrentRegion = function() return 3 end
GetTime = function() return 1000 end
InCombatLockdown = function() return false end
issecretvalue = function() return false end

local unit_data = {
    player = {
        name = "Host",
        realm = "Realm",
        guid = "Player-1",
        class = "WARRIOR",
        classID = 1,
        specID = 73,
        role = "TANK",
    },
    party1 = {
        name = "Friend",
        realm = "Realm",
        guid = "Party-1",
        class = "MAGE",
        classID = 8,
        specID = 63,
        role = "DAMAGER",
    },
    party2 = {
        name = "Healer",
        realm = "Realm",
        guid = "Party-2",
        class = "PRIEST",
        classID = 5,
        specID = 256,
        role = "HEALER",
    },
    party3 = {
        name = "Feral",
        realm = "Realm",
        guid = "Party-3",
        class = "DRUID",
        classID = 11,
        specID = 103,
        role = "DAMAGER",
    },
    party4 = {
        name = "Ret",
        realm = "Realm",
        guid = "Party-4",
        class = "PALADIN",
        classID = 2,
        specID = 70,
        role = "DAMAGER",
    },
}

UnitFullName = function(unit)
    local data = unit_data[unit]
    if data then
        if data.unitFullName then return data.unitFullName[1], data.unitFullName[2] end
        return data.name, data.realm
    end
    return "Unknown", "Realm"
end
GetUnitName = function(unit)
    local data = unit_data[unit]
    if data then
        if data.unitName then return data.unitName end
        return data.name .. "-" .. data.realm
    end
    return "Unknown-Realm"
end
UnitExists = function(unit) return unit_data[unit] ~= nil end
UnitGUID = function(unit) return unit_data[unit] and unit_data[unit].guid or "" end
UnitClass = function(unit)
    local data = unit_data[unit]
    if not data then return nil, nil, 0 end
    return data.class, data.class, data.classID
end
UnitIsUnit = function(left, right) return left == right end
UnitIsGroupLeader = function(unit) return unit == "player" end
GetSpecialization = function() return 3 end
GetSpecializationInfo = function() return 73, "Protection", nil, nil, nil, "WARRIOR" end
GetInspectSpecialization = function(unit)
    local data = unit_data[unit]
    return data and data.specID or 0
end
GetAverageItemLevel = function() return 710.4, 709.6 end
C_PaperDollInfo = {
    GetInspectItemLevel = function(unit)
        if unit == "party1" then return 704.4 end
        if unit == "party2" then return 706.5 end
        if unit == "party3" then return 702.2 end
        if unit == "party4" then return 701.8 end
        return 0
    end,
}
UnitGroupRolesAssigned = function(unit)
    local data = unit_data[unit]
    return data and data.role or "NONE"
end
GetSpecializationRoleByID = function(specID)
    if specID == 73 then return "TANK" end
    if specID == 256 then return "HEALER" end
    if specID == 63 then return "DAMAGER" end
    if specID == 103 then return "DAMAGER" end
    if specID == 70 then return "DAMAGER" end
    return "DAMAGER"
end
GetNumGroupMembers = function() return 5 end
IsInRaid = function() return false end
NotifyInspect = function() end
CanInspect = function() return true end

local profiles = {
    ["Tankone-Realm"] = { current = 3210, main = 3456, levels = { 18, 15, 14 } },
    ["Mageone-Realm"] = { current = 2988, main = 3101, levels = { 16, 15, 13 } },
    ["Host-Realm"] = { current = 3333, main = 3500, levels = { 17, 16, 14 } },
    ["Friend-Realm"] = { current = 2777, main = 2999, levels = { 16, 14, 12 } },
    ["Healer-Realm"] = { current = 2550, main = 2700, levels = { 15, 14, 12 } },
    ["Feral-Realm"] = { current = 2440, main = 2600, levels = { 14, 13, 12 } },
    ["Ret-Realm"] = { current = 2320, main = 2500, levels = { 13, 12, 11 } },
}

local function dungeon_entry(level, timed, activityID)
    return {
        level = level,
        chests = timed and 1 or 0,
        dungeon = { lfd_activity_ids = { activityID or 401 }, keystone_instance = activityID or 401 },
    }
end

RaiderIO = {
    GetProfile = function(name)
        local profile = profiles[name]
        if not profile then return nil end
        return {
            mythicKeystoneProfile = {
                mplusCurrent = { score = profile.current },
                mplusMainCurrent = { score = profile.main },
                sortedDungeons = {
                    dungeon_entry(profile.levels[1], true, 401),
                    dungeon_entry(profile.levels[2], true, 402),
                    dungeon_entry(profile.levels[3], false, 403),
                },
            },
        }
    end,
}

C_LFGList = {
    GetActivityInfoTable = function()
        return {
            shortName = "Fixture Halls",
            fullName = "Fixture Halls",
            categoryID = 2,
            difficultyID = 8,
        }
    end,
    GetOwnedKeystoneActivityAndGroupAndLevel = function()
        return 0, 0, 0
    end,
    GetApplicantInfo = function(id)
        if id == 42 then
            return { applicationStatus = "applied", numMembers = 2 }
        end
        return nil
    end,
    GetApplicantMemberInfo = function(id, memberIndex)
        if id ~= 42 then return nil end
        if memberIndex == 1 then
            return "Tankone-Realm", "WARRIOR", nil, nil, 710.2, nil, nil, nil, nil,
                "TANK", nil, 3210, nil, nil, nil, 73
        end
        if memberIndex == 2 then
            return "Mageone-Realm", "MAGE", nil, nil, 707.4, nil, nil, nil, nil,
                "DAMAGER", nil, 2988, nil, nil, nil, 63
        end
        return nil
    end,
}

local env = {
    unit_data = unit_data,
    profiles = profiles,
}

env.load_addon = function()
    ApplicantScoutFixtureHarness = {}
    local chunk = assert(loadfile("ApplicantScout.lua"))
    chunk("ApplicantScout", { QR = {} })
    return ApplicantScoutFixtureHarness
end

return env
