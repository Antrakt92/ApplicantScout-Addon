local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
env.install_raid_roster(40)
C_PaperDollInfo.GetInspectItemLevel = function(unit)
    if string.find(unit, "^raid") then return 700 end
    return 0
end

local harness = env.load_addon({})
harness.SetApplicantTransportAdapters(
    function(rawID)
        return rawID, {
            applicantID = rawID,
            applicationStatus = "applied",
            numMembers = 5,
        }, rawID
    end,
    function(rawID, memberIndex)
        return true,
            string.format("Applicant%02dMember%d-Ravencrest", rawID, memberIndex),
            "PALADIN",
            700 + memberIndex,
            "DAMAGER",
            2500 + rawID,
            70
    end
)

local applicantIDs = {}
for id = 1, 40 do applicantIDs[#applicantIDs + 1] = id end
local logicalPayload, logicalHash = harness.BuildPayload({
    activityIDs = { 401 },
    questID = 0,
    name = "Paired overflow contract",
    comment = "all 200 applicants and 40 roster rows must survive reassembly",
}, applicantIDs, false)
assert(logicalPayload and #logicalPayload > 640, "fixture did not require overflow")

local state = assert(harness.StartQROverflowTransport(
    logicalPayload,
    logicalHash,
    91,
    200,
    false,
    nil
))

local function hex(value)
    local out = {}
    for index = 1, #value do
        out[index] = string.format("%02x", string.byte(value, index))
    end
    return table.concat(out)
end

for _ = 1, state.chunkCount do
    local frame = assert(harness.BuildQROverflowFragment(state))
    print(hex(frame))
    harness.AdvanceQROverflowTransport(state)
end
