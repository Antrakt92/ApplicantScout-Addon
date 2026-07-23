local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local original_get_inspect_specialization = GetInspectSpecialization

GetNumGroupMembers = function() return 0 end
IsInRaid = function() return false end

local harness = env.load_addon({})
local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "Authority fixture",
    comment = "complete domains only",
}

local function wire_version(payload)
    return string.byte(payload, 5)
end

local function flags(payload)
    return string.byte(payload, 8)
end

local function install_applicant(member_count, missing_member, status)
    harness.SetApplicantTransportAdapters(
        function(rawID)
            return rawID, {
                applicantID = rawID,
                applicationStatus = status or "applied",
                numMembers = member_count,
            }, rawID
        end,
        function(rawID, memberIndex)
            if memberIndex == missing_member then return false end
            return true,
                string.format("Applicant%dMember%d-Realm", rawID, memberIndex),
                "MAGE",
                700,
                "DAMAGER",
                2500,
                63
        end
    )
end

install_applicant(3)
local complete = assert(harness.BuildPayload(entry, { 42 }, false))
assert(wire_version(complete) == 0x09, "complete applicants must remain v9")
assert(flags(complete) == 0, "complete applicants unexpectedly marked partial")
assert(complete:find("Applicant42Member2-Realm", 1, true), "complete member missing")

install_applicant(3, 2)
local missing_middle = assert(harness.BuildPayload(entry, { 42 }, false))
assert(wire_version(missing_middle) == 0x0B, "applicant partial must use v11")
assert(flags(missing_middle) == 0x08, "applicant partial flag missing")
assert(
    not missing_middle:find("Applicant42Member1-Realm", 1, true),
    "partial applicant domain leaked a valid-looking sibling"
)

harness.SetApplicantTransportAdapters(
    function(rawID)
        if rawID == 41 then return nil end
        return rawID, {
            applicantID = rawID,
            applicationStatus = "applied",
            numMembers = 1,
        }, rawID
    end,
    function(rawID)
        return true, "Later-Realm", "MAGE", 700, "DAMAGER", 2500, 63
    end
)
local missing_info = assert(harness.BuildPayload(entry, { 41, 42 }, false))
assert(wire_version(missing_info) == 0x0B, "missing applicant info must use v11")
assert(flags(missing_info) == 0x08, "missing applicant info flag missing")
assert(not missing_info:find("Later-Realm", 1, true), "partial applicant rows leaked")

install_applicant(1, nil, "declined")
local dead = assert(harness.BuildPayload(entry, { 42 }, false))
assert(wire_version(dead) == 0x09, "dead-status omission changed wire version")
assert(flags(dead) == 0, "dead-status omission must remain authoritative")

local unavailable = assert(harness.BuildPayload(entry, nil, false))
assert(wire_version(unavailable) == 0x0B, "unavailable applicant list must use v11")
assert(flags(unavailable) == 0x08, "unavailable applicant list flag missing")

GetNumGroupMembers = function() return 5 end
GetInspectSpecialization = function(unit)
    if unit == "party2" then return 0 end
    return original_get_inspect_specialization(unit)
end
install_applicant(1)
local roster_partial = assert(harness.BuildPayload(entry, { 42 }, false))
assert(wire_version(roster_partial) == 0x09, "roster-only partial must remain v9")
assert(flags(roster_partial) == 0x04, "roster partial flag missing")
assert(not roster_partial:find("Healer-Realm", 1, true), "partial roster rows leaked")

install_applicant(3, 2)
local both_partial = assert(harness.BuildPayload(entry, { 42 }, false))
assert(wire_version(both_partial) == 0x0B, "combined partial must use v11")
assert(flags(both_partial) == 0x0C, "combined applicant/roster flags missing")

install_applicant(1)
local lfg_and_roster = assert(harness.BuildPayload(entry, {}, false, true))
assert(wire_version(lfg_and_roster) == 0x09, "LFG/roster partial must remain v9")
assert(flags(lfg_and_roster) == 0x06, "combined LFG/roster flags missing")

local terminal = assert(harness.BuildPayload(entry, nil, true, true, true))
assert(wire_version(terminal) == 0x09, "terminal clear must retain v9")
assert(flags(terminal) == 0x01, "terminal clear leaked partial flags")

install_applicant(3)
GetNumGroupMembers = function() return 0 end
GetInspectSpecialization = original_get_inspect_specialization
local recovered = assert(harness.BuildPayload(entry, { 42 }, false))
assert(wire_version(recovered) == 0x09, "full recovery did not return to v9")
assert(flags(recovered) == 0, "full recovery retained partial flags")
assert(recovered:find("Applicant42Member2-Realm", 1, true), "recovery rows missing")

print("ok partial-surface-authority")
