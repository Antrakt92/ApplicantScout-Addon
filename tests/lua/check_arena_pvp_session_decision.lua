local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

-- Arena/pvp session decision: GetInstanceInfo "arena"/"pvp" must NOT suspend
-- the transport session. Rationale (locked here): suspending drops snapshot
-- data, not just capture; applicants can apply while the group is in
-- PvP-adjacent staging, and combat already pauses capture via gameplay
-- suppression. Revisit only with live evidence of harmful arena snapshots.
local harness = env.load_addon({})

local saved_print = print
print = function() end
harness.CheckSessionTransition(true)
print = saved_print

local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "Arena staging fixture",
    comment = "session survives pvp instance types",
}

for _, instanceType in ipairs({ "arena", "pvp" }) do
    GetInstanceInfo = function()
        return "Staging", instanceType, 1, 1, 1
    end
    harness.CheckSessionTransition(true)
    local payload = assert(harness.BuildPayload(entry, {}, false),
        instanceType .. " voided the payload")
    assert(harness.LastPayloadRosterCount() == 5,
        instanceType .. " dropped the party roster")
    assert(not harness.LastPayloadRosterIncomplete(),
        instanceType .. " marked the real party incomplete")
    assert(#payload > 0, instanceType .. " emitted an empty payload")
end

print("ok arena-pvp-session-decision")
