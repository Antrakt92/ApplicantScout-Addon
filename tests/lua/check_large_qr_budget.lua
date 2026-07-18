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

-- 1139 bytes reproduces the live failure size. 0xAB becomes a mixed
-- alphanumeric hex payload whose Version 29 matrix needs 5550 row-RLE runs.
local payload = string.rep(string.char(0xAB), 1139)
local result_matrix = nil
local result_runs = nil
local result_run_count = nil
harness.SetQRPaintJobGeneration(21)
harness.BuildQRMatrixAsync(payload, false, false, 21, function(matrix, runs, count)
    result_matrix = matrix
    result_runs = runs
    result_run_count = count
end)
drain_timers()

assert(result_matrix ~= nil, "observed-size payload exceeded QR texture budget")
assert(#result_matrix == 133, "unexpected QR matrix size")
assert(#result_runs == 5550 * 4, "unexpected flat QR row-RLE buffer size")
assert(result_run_count == 5550, "unexpected logical QR row-RLE run count")

print("ok large-qr-budget")
