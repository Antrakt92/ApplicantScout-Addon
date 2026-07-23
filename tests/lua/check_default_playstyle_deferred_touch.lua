local env = dofile("tests/lua/appscout_fixture_env.lua")

ApplicantScoutDB = {
    enabled = true,
    autoMPlusPlaystyle = "FunSerious",
}

local hooks = {}
hooksecurefunc = function(name, callback)
    if not hooks[name] then
        local original = assert(_G[name], "missing hooked function " .. name)
        hooks[name] = {}
        _G[name] = function(...)
            local results = { original(...) }
            for _, hook in ipairs(hooks[name]) do hook(...) end
            return unpack(results)
        end
    end
    table.insert(hooks[name], callback)
end

Enum = {
    LFGEntryGeneralPlaystyle = {
        Learning = 101,
        FunRelaxed = 102,
        FunSerious = 103,
        Expert = 104,
    },
}

local panel = {
    selectedActivity = 42,
    generalPlaystyle = nil,
    PlayStyleDropdown = { GenerateMenu = function() end },
}
LFGListFrame = { EntryCreation = panel }
LFGListEntryCreation_IsEditMode = function() return false end
LFGListEntryCreation_UpdateValidState = function() end
LFGListEntryCreation_Select = function() end
LFGListEntryCreation_SetEditMode = function() end
LFGListEntryCreation_OnPlayStyleSelectedInternal = function(target, playstyle)
    target.generalPlaystyle = playstyle
end
LFGListEntryCreation_Show = function(target)
    LFGListEntryCreation_OnPlayStyleSelectedInternal(target, 101)
end
C_LFGList.GetActivityInfoTable = function()
    return { isMythicPlusActivity = true }
end

local harness = env.load_addon()
local realPrint = print
print = function() end
harness.FireEvent("PLAYER_LOGIN")
print = realPrint
local drain = harness.ProcessLFGEntryCreationDeferredWork
assert(type(drain) == "function", "missing deferred work fixture hook")

-- Drain setup-time work so each scenario starts with no coalesced flags.
drain()
assert(panel.generalPlaystyle == 103, "setup did not apply the configured default")

-- Blizzard's selection inside Show belongs to initialization, but a manual
-- selection after Show returns is a later generation and must survive drain.
LFGListEntryCreation_Show(panel)
LFGListEntryCreation_OnPlayStyleSelectedInternal(panel, 102)
drain()
assert(panel.generalPlaystyle == 102,
    "deferred Show reset overwrote the later manual playstyle")

-- With no later manual touch, the same internal-Show initialization is reset
-- and the configured default is still applied.
LFGListEntryCreation_Show(panel)
drain()
assert(panel.generalPlaystyle == 103,
    "internal Show initialization prevented the configured default")

io.write("default-playstyle-deferred-touch-ok\n")
