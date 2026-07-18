local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

GetNumGroupMembers = function() return 0 end
IsInRaid = function() return false end

local harness = env.load_addon({})
assert(type(harness.SetApplicantTransportAdapters) == "function")

local tokens = {}
local tokenIDs = {}
for id = 1, 40 do
    local token = setmetatable({}, {
        __lt = function() error("opaque API token was compared") end,
        __tostring = function() error("opaque API token was stringified") end,
    })
    tokens[id] = token
    tokenIDs[token] = id
end

harness.SetApplicantTransportAdapters(
    function(rawID)
        return rawID, {
            applicantID = rawID,
            applicationStatus = "applied",
            numMembers = 1,
        }, tokens[rawID]
    end,
    function(apiID, memberIndex)
        local id = tokenIDs[apiID]
        assert(id, "opaque API token identity was not preserved")
        if memberIndex ~= 1 or id == 17 then return false end
        return true,
            string.format("Applicant%02d-Realm", id),
            "MAGE",
            700,
            "DAMAGER",
            2500,
            63
    end
)

local applicantIDs = {}
for id = 40, 1, -1 do applicantIDs[#applicantIDs + 1] = id end
local payload = assert(harness.BuildPayload)({
    activityIDs = { 401 },
    questID = 0,
    name = "Applicants 40",
    comment = "stable",
}, applicantIDs, false)

local previousPosition = 0
for id = 1, 40 do
    local name = string.format("Applicant%02d-Realm", id)
    local position = payload:find(name, 1, true)
    if id == 17 then
        assert(position == nil, "missing applicant member row was emitted")
    else
        assert(position, "valid applicant member row was omitted")
        assert(position > previousPosition, "applicant rows were not sorted by clean ID")
        previousPosition = position
    end
end

assert(#payload == 1696, "transport record reuse changed APS1 payload length")
local payloadHash = harness.HashSnapshot(payload)
assert(
    payloadHash == 3053853762,
    string.format("transport record reuse changed APS1 payload bytes: %u", payloadHash)
)

print(string.format(
    "ok transport-record-reuse rows=39 bytes=%d hash=%u",
    #payload,
    payloadHash
))
