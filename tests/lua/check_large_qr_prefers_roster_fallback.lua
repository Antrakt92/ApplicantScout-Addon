local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local timer_queue = {}
C_Timer.After = function(_, callback)
    timer_queue[#timer_queue + 1] = callback
end

local qr_namespace = {}
local qr_chunk = assert(loadfile("libs/qrencode.lua"))
qr_chunk("ApplicantScout", qr_namespace)
local harness = env.load_addon(qr_namespace.QR)

local function drain_timers()
    local safety = 1000
    while #timer_queue > 0 do
        local callback = table.remove(timer_queue, 1)
        callback()
        safety = safety - 1
        assert(safety > 0, "timer queue did not drain")
    end
end

-- Hex for this payload needs 6056 row runs, just over the 6000 budget, while
-- raw byte-mode needs only 4446. The full roster path must report failure so
-- MaybeTriggerScreenshot can build a reliable roster-unavailable hex payload
-- instead of painting the smaller but live-corrupting raw QR.
local payload = string.rep(string.char(0xAB), 1200)
local preferred_matrix = "not-called"
harness.SetQRPaintJobGeneration(41)
harness.BuildQRMatrixAsync(payload, true, true, 41, function(matrix)
    preferred_matrix = matrix
end)
drain_timers()
assert(preferred_matrix == nil, "full snapshot used raw before roster fallback")

local emergency_matrix = nil
local emergency_runs = nil
harness.SetQRPaintJobGeneration(42)
harness.BuildQRMatrixAsync(payload, false, false, 42, function(matrix, runs)
    emergency_matrix = matrix
    emergency_runs = runs
end)
drain_timers()
assert(emergency_matrix ~= nil, "raw emergency fallback was removed")
assert(#emergency_matrix == 117, "unexpected raw fallback matrix size")
assert(#emergency_runs == 4446, "unexpected raw fallback run count")

print("ok large-qr-prefers-roster-fallback")
