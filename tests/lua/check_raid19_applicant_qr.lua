local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
env.install_raid_roster(19)
env.install_single_applicant()

local unitGUIDCalls = 0
local originalUnitGUID = UnitGUID
UnitGUID = function(unit)
    unitGUIDCalls = unitGUIDCalls + 1
    return originalUnitGUID(unit)
end

local unitIsUnitCalls = 0
local originalUnitIsUnit = UnitIsUnit
UnitIsUnit = function(left, right)
    unitIsUnitCalls = unitIsUnitCalls + 1
    return originalUnitIsUnit(left, right)
end

-- Keep every raid member fully resolved so this fixture measures only the
-- synchronous identity work needed to serialize each roster row.
C_PaperDollInfo.GetInspectItemLevel = function(unit)
    if string.find(unit, "^raid") then return 700 end
    return 0
end

local timer_queue = {}
C_Timer.After = function(_, callback)
    timer_queue[#timer_queue + 1] = callback
end

local qr_namespace = {}
local qr_chunk = assert(loadfile("libs/qrencode.lua"))
qr_chunk("ApplicantScout", qr_namespace)
local harness = env.load_addon(qr_namespace.QR)

local entry = {
    activityIDs = { 401 },
    questID = 0,
    name = "Raid 19 transport fixture",
    comment = "one applicant must not evict the raid roster",
}
local payload = assert(harness.BuildPayload)(entry, { 42 }, false)
assert(#payload > 900, "raid fixture did not exercise a large payload")
assert(not harness.LastPayloadRosterIncomplete(), "raid roster payload was incomplete")
assert(unitGUIDCalls == 19, string.format(
    "roster build resolved GUID %d times for 19 rows",
    unitGUIDCalls
))
assert(unitIsUnitCalls == 19, string.format(
    "roster build resolved self identity %d times for 19 rows",
    unitIsUnitCalls
))

local result_matrix = nil
local result_runs = nil
local result_run_count = nil
harness.SetQRPaintJobGeneration(31)
harness.BuildQRMatrixAsync(payload, false, true, 31, function(matrix, runs, count)
    result_matrix = matrix
    result_runs = runs
    result_run_count = count
end)

local safety = 1000
while #timer_queue > 0 do
    local callback = table.remove(timer_queue, 1)
    callback()
    safety = safety - 1
    assert(safety > 0, "timer queue did not drain")
end

assert(result_matrix ~= nil, "raid19 + applicant full payload exceeded QR budget")
assert(result_runs ~= nil and result_run_count <= 6000, "raid19 QR exceeded texture budget")
assert(#result_runs == result_run_count * 4, "raid19 QR flat buffer/count mismatch")

print(string.format(
    "ok raid19-applicant-qr payload=%d matrix=%d runs=%d",
    #payload,
    #result_matrix,
    result_run_count
))
