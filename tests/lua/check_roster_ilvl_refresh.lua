local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
env.unit_data.party2 = nil
env.unit_data.party3 = nil
env.unit_data.party4 = nil
GetNumGroupMembers = function() return 2 end

local now, reads, snapshots, inspectRequests = 1000, 0, 0, 0
local currentIlvl = 704.4
local unavailable = nil
local secretIlvl = {}
GetTime = function() return now end
issecretvalue = function(value) return value == secretIlvl end
NotifyInspect = function() inspectRequests = inspectRequests + 1 end
C_PaperDollInfo.GetInspectItemLevel = function(unit)
    assert(unit == "party1", "only the remote party member needs inspected ilvl")
    reads = reads + 1
    if unavailable == "error" then error("inspect item level temporarily unavailable") end
    if unavailable == "nil" then return nil end
    if unavailable == "secret" then return secretIlvl end
    return currentIlvl
end

local harness = env.load_addon()
harness.StartSession()
local entry = { activityIDs = { 401 }, name = "+16 Fixture Halls", comment = "" }
local function WriteSnapshot()
    now = now + 1
    local beforeReads = reads
    local payload = assert(harness.BuildPayload(entry, {}, false))
    snapshots = snapshots + 1
    assert(reads - beforeReads <= 1, "each row must need at most one ilvl accessor read")
    assert(inspectRequests == 0, "resolved gear changes must not issue new inspections")
    for i = 1, #payload do io.write(string.format("%02x", string.byte(payload, i))) end
    io.write("\n")
    beforeReads = reads
    assert(not harness.EnsureRosterInspectBatchBeforeSnapshot(),
        "a resolved cached member must not start an inspect batch")
    assert(reads == beforeReads, "resolved preflight must retain its cached fast path")
end

WriteSnapshot()
currentIlvl = 798.6
WriteSnapshot()
currentIlvl = 691.2
WriteSnapshot()
currentIlvl = 0
WriteSnapshot()
unavailable = "secret"
WriteSnapshot()
unavailable = "error"
WriteSnapshot()
unavailable = "nil"
WriteSnapshot()
unavailable = nil
currentIlvl = 710.7
WriteSnapshot()
assert(reads <= snapshots, "equipment refresh must not amplify inspection work")
