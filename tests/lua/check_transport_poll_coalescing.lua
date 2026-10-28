local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))
local benchmark = arg[1] == "benchmark"
env.install_raid_roster(40)
env.install_single_applicant()
C_PaperDollInfo.GetInspectItemLevel = function() return 700 end
local now = 1000
GetTime = function() return now end
local scanTick
C_Timer.NewTicker = function(_, callback)
    scanTick = callback
    return { Cancel = function() end }
end
local ids = {}
for id = 1, 40 do ids[id] = id end
local listing = {
    activityIDs = {401}, questID = 0,
    name = "Raid40 poll coalescing", comment = "stable applicants",
}
local applicantReads = 0
C_LFGList.HasActiveEntryInfo = function() return true end
C_LFGList.GetActiveEntryInfo = function() return listing end
C_LFGList.GetApplicants = function()
    applicantReads = applicantReads + 1
    return ids
end
ApplicantScoutDB = { enabled = true, debug = false }
local harness = env.load_addon({})
assert(scanTick, "scan ticker callback missing")

-- Stage a fully delivered snapshot without simulating framebuffer timing.
-- The operation under test is the real scan callback and real serialization;
-- debug access only establishes the otherwise capture-owned preconditions.
local function upvalue(fn, wanted, value, replace)
    for index = 1, 100 do
        local name, current = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then
            if replace then debug.setupvalue(fn, index, value) end
            return current
        end
    end
    error("missing fixture upvalue: " .. wanted)
end
env.start_session_quietly(harness)
harness.CheckSessionTransition(true)
local state = upvalue(scanTick, "entryCreationKeyState")
state.qrGameplayLoadingActive = false
state.qrGameplaySuppressed = false
state.qrGameplaySuppressionReason = "none"
upvalue(harness.MaybeTriggerScreenshot, "qrFrameCreated", true, true)
local payload, hash = harness.BuildPayload(listing, ids, false)
assert(payload and hash, "full workload payload missing")
upvalue(harness.MaybeTriggerScreenshot, "lastSnapshotHash", hash, true)
state.lastDeliverySnapshotHash = hash
state.lastDeliverySnapshotSendCount = 2
state.lastEmittedApplicantCount = 40
state.rosterChangedSinceLastPayload = false
state.rosterChangePreflightDeadline = nil
upvalue(harness.MaybeTriggerScreenshot, "suppressShotsUntil", 0, true)

local samples = {}
local cases = {
    { name = "pending-and-poll", pending = true, pollAge = 0.5, expected = 1 },
    { name = "periodic-only", pending = false, pollAge = 0.5, expected = 1 },
    { name = "pending-only", pending = true, pollAge = 0.25, expected = 1 },
    { name = "not-due", pending = false, pollAge = 0.25, expected = 0 },
}
for repetition = 1, 7 do
    for _, case in ipairs(cases) do
        now = now + 3
        upvalue(scanTick, "scanDirty", false, true)
        upvalue(scanTick, "pendingShotDirty", case.pending, true)
        upvalue(scanTick, "lastTransportPollTime", now - case.pollAge, true)
        upvalue(harness.MaybeTriggerScreenshot, "lastShotTime", now - 1, true)
        applicantReads = 0
        local byteReads = 0
        local originalByte = string.byte
        string.byte = function(...)
            byteReads = byteReads + 1
            return originalByte(...)
        end
        local started = os.clock()
        scanTick()
        local elapsed = os.clock() - started
        string.byte = originalByte
        samples[#samples + 1] = string.format(
            "%s repetition=%d applicant_reads=%d byte_reads=%d cpu_seconds=%.6f",
            case.name, repetition, applicantReads, byteReads, elapsed
        )
        if not benchmark then
            assert(applicantReads == case.expected, string.format(
                "%s repeated applicant payload work: %d reads, expected %d",
                case.name, applicantReads, case.expected
            ))
            assert(byteReads == case.expected * #payload,
                case.name .. " repeated or skipped payload finalization")
            assert(not harness.QRTransportState().pendingShotDirty,
                case.name .. " left completed pending work armed")
        end
    end
end
for _, sample in ipairs(samples) do print(sample) end
print("ok transport-poll-coalescing bytes=" .. #payload)
