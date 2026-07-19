local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local timerQueue = {}
C_Timer.After = function(_, callback)
    timerQueue[#timerQueue + 1] = callback
end

local qrNamespace = {}
local qrChunk = assert(loadfile("libs/qrencode.lua"))
qrChunk("ApplicantScout", qrNamespace)
local harness = env.load_addon(qrNamespace.QR)

local function drainTimers()
    local safety = 10000
    while #timerQueue > 0 do
        local callback = table.remove(timerQueue, 1)
        callback()
        safety = safety - 1
        assert(safety > 0, "timer queue did not drain")
    end
end

local function u16(value)
    value = math.floor(value) % 65536
    return string.char(math.floor(value / 256), value % 256)
end

local function u32(value)
    value = math.floor(value) % 4294967296
    return string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256
    )
end

local function read16(value, offset)
    return string.byte(value, offset) * 256 + string.byte(value, offset + 1)
end

local function read32(value, offset)
    return string.byte(value, offset) * 16777216
        + string.byte(value, offset + 1) * 65536
        + string.byte(value, offset + 2) * 256
        + string.byte(value, offset + 3)
end

local crcTable = {}
for index = 0, 255 do
    local value = index
    for _ = 1, 8 do
        if bit.band(value, 1) == 1 then
            value = bit.bxor(bit.rshift(value, 1), 0xEDB88320)
        else
            value = bit.rshift(value, 1)
        end
    end
    crcTable[index] = value
end

local function crc32(value)
    local crc = 0xFFFFFFFF
    for index = 1, #value do
        local byte = string.byte(value, index)
        crc = bit.bxor(
            bit.rshift(crc, 8),
            crcTable[bit.band(bit.bxor(crc, byte), 0xFF)]
        )
    end
    return bit.bxor(crc, 0xFFFFFFFF) % 4294967296
end

-- The logical bytes are a complete v9-shaped frame with a valid CRC. The
-- semantic body is intentionally opaque here: this fixture owns the transport
-- envelope; companion parser fixtures own the inner application schema.
local logicalLength = 5000
local logicalBody = "APS1" .. string.char(0x09) .. u16(logicalLength)
    .. "\0\0" .. string.rep(string.char(0xAB), logicalLength - 13)
local logicalPayload = logicalBody .. u32(crc32(logicalBody))
assert(#logicalPayload == logicalLength, "logical fixture length mismatch")

local logicalHash = harness.HashSnapshot(logicalPayload)
local state, startError = harness.StartQROverflowTransport(
    logicalPayload,
    logicalHash,
    77,
    200,
    false,
    nil
)
assert(state ~= nil, tostring(startError))
assert(state.chunkCount == 8, "unexpected overflow chunk count")

local reconstructed = {}
local maximumMatrix = 0
local maximumRuns = 0
for pass = 1, 2 do
    for expectedIndex = 0, state.chunkCount - 1 do
        assert(state.pass == pass and state.chunkIndex == expectedIndex,
            "overflow progression skipped or reordered a fragment")
        local frame, frameError = harness.BuildQROverflowFragment(state)
        assert(frame ~= nil, tostring(frameError))
        assert(string.sub(frame, 1, 4) == "APS1", "fragment magic mismatch")
        assert(string.byte(frame, 5) == 0x0A, "fragment wire version mismatch")
        assert(read16(frame, 6) == #frame, "fragment total length mismatch")
        assert(string.byte(frame, 8) == 0 and string.byte(frame, 9) == 0,
            "fragment flags/reserved must be zero")
        assert(read32(frame, 10) == state.streamID, "fragment stream mismatch")
        assert(read32(frame, 14) == state.generation, "fragment generation mismatch")
        assert(read16(frame, 18) == expectedIndex, "fragment index mismatch")
        assert(read16(frame, 20) == state.chunkCount, "fragment count mismatch")
        assert(read16(frame, 22) == logicalLength, "inner length mismatch")
        assert(read32(frame, 24) == crc32(logicalBody), "inner CRC mismatch")
        assert(read32(frame, #frame - 3) == crc32(string.sub(frame, 1, #frame - 4)),
            "outer fragment CRC mismatch")

        local chunk = string.sub(frame, 28, #frame - 4)
        local expectedChunkLength = expectedIndex < state.chunkCount - 1
            and 640 or (logicalLength - 640 * (state.chunkCount - 1))
        assert(#chunk == expectedChunkLength, "fragment chunk length mismatch")
        assert(#frame <= 671, "fragment exceeded bounded QR frame bytes")
        if pass == 1 then reconstructed[#reconstructed + 1] = chunk end

        local matrix, runs, runCount = nil, nil, nil
        local jobGeneration = pass * 100 + expectedIndex
        harness.SetQRPaintJobGeneration(jobGeneration)
        harness.BuildQRMatrixAsync(
            frame,
            true,
            true,
            jobGeneration,
            function(resultMatrix, resultRuns, resultRunCount)
                matrix, runs, runCount = resultMatrix, resultRuns, resultRunCount
            end
        )
        drainTimers()
        assert(matrix ~= nil and runs ~= nil, "bounded fragment did not encode")
        assert(#matrix <= 105,
            "fragment exceeded QR Version 22 worst-case render guarantee")
        assert(runCount <= 6000 and #runs == runCount * 4,
            "fragment exceeded or corrupted the texture-run budget")
        maximumMatrix = math.max(maximumMatrix, #matrix)
        maximumRuns = math.max(maximumRuns, runCount)

        local passComplete, deliveryComplete =
            harness.AdvanceQROverflowTransport(state)
        if expectedIndex < state.chunkCount - 1 then
            assert(not passComplete and not deliveryComplete,
                "overflow pass completed before its last fragment")
        elseif pass == 1 then
            assert(passComplete and not deliveryComplete,
                "first overflow pass did not request its bounded resend")
        else
            assert(passComplete and deliveryComplete,
                "second overflow pass did not complete logical delivery")
        end
    end
end

assert(table.concat(reconstructed) == logicalPayload,
    "fragment sequence did not reconstruct exact logical bytes")
assert(harness.QRTransportState().overflowState == nil,
    "completed overflow state was not retired")

-- A newer payload waits only until the frozen first pass is complete, then
-- supersedes the redundant pass so continuous applicant churn cannot starve
-- every logical generation forever.
local superseded = assert(harness.StartQROverflowTransport(
    logicalPayload,
    logicalHash + 1,
    78,
    200,
    false,
    nil
))
superseded.queuedNewer = true
for _ = 1, superseded.chunkCount do
    harness.AdvanceQROverflowTransport(superseded)
end
local finalState = harness.QRTransportState()
assert(finalState.overflowState == nil and finalState.overflowSupersededCount == 1,
    "queued newer generation did not supersede after one complete pass")

-- BuildPayload must fail closed instead of wrapping its uint16 total length.
-- Fifty five-member groups with max-length clean wire names cross 65535 bytes
-- while remaining valid producer records.
harness.SetApplicantTransportAdapters(
    function(rawID)
        return rawID, {
            applicantID = rawID,
            applicationStatus = "applied",
            numMembers = 5,
        }, rawID
    end,
    function(rawID, memberIndex)
        local prefix = string.format("Applicant%03dMember%d-", rawID, memberIndex)
        return true,
            prefix .. string.rep("X", 255),
            "MAGE",
            700,
            "DAMAGER",
            2500,
            63
    end
)
local oversizedIDs = {}
for id = 1, 50 do oversizedIDs[#oversizedIDs + 1] = id end
local oversizedPayload, oversizedHash = harness.BuildPayload({
    activityIDs = { 401 },
    questID = 0,
    name = "Length boundary",
    comment = "must fail closed",
}, oversizedIDs, false)
assert(oversizedPayload == nil and oversizedHash == nil,
    "APS1 total length silently wrapped past uint16")

print(string.format(
    "ok qr-overflow-envelope chunks=%d matrix=%d runs=%d",
    state.chunkCount,
    maximumMatrix,
    maximumRuns
))
