local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local timer_queue = {}
local timer_calls = 0
C_Timer.After = function(_, callback)
    timer_calls = timer_calls + 1
    timer_queue[#timer_queue + 1] = callback
end

local encoded_matrix = nil
local encode_calls = 0
local encode_should_fail = false
local harness = env.load_addon({
    qrcode = function()
        encode_calls = encode_calls + 1
        if encode_should_fail then return false, "fixture encode failure" end
        return true, encoded_matrix
    end,
})
assert(type(harness.BuildQRBlackRunsAsync) == "function", "missing async QR run builder")
assert(type(harness.BuildQRMatrixAsync) == "function", "missing async QR matrix builder")
assert(type(harness.SetQRPaintJobGeneration) == "function", "missing QR generation fixture hook")

local function drain_timers()
    local safety = 1000
    while #timer_queue > 0 do
        local callback = table.remove(timer_queue, 1)
        callback()
        safety = safety - 1
        assert(safety > 0, "timer queue did not drain")
    end
end

local matrix = {}
for y = 1, 117 do
    local row = {}
    for x = 1, 117 do
        row[x] = ((x - 1) % 6) < 3 and 1 or -1
    end
    matrix[y] = row
end
encoded_matrix = matrix

harness.SetQRPaintJobGeneration(7)
local completed_runs = nil
local completed_count = nil
harness.BuildQRBlackRunsAsync(matrix, 6, 3500, 7, function(runs, count)
    completed_runs = runs
    completed_count = count
end)

assert(completed_runs == nil, "large matrix analysis completed synchronously")
drain_timers()
assert(timer_calls >= 10, "large matrix analysis was not split across frames")
assert(completed_count == 2340, "unexpected horizontal run count")
assert(#completed_runs == completed_count * 4, "flat run buffer/count mismatch")
assert(type(completed_runs[1]) == "number", "QR runs still allocate nested tables")
assert(completed_runs[1] == 6 and completed_runs[2] == 6, "wrong first run origin")
assert(completed_runs[3] == 9 and completed_runs[4] == 3, "wrong first run size")
local last = #completed_runs - 3
assert(completed_runs[last] == 348 and completed_runs[last + 1] == 354, "wrong last run origin")
assert(completed_runs[last + 2] == 9 and completed_runs[last + 3] == 3, "wrong last run size")

timer_queue = {}
timer_calls = 0
encode_calls = 0
harness.SetQRPaintJobGeneration(9)
local encoded_result = nil
local encoded_runs = nil
local encoded_run_count = nil
harness.BuildQRMatrixAsync("fixture", false, false, 9, function(result, runs, count)
    encoded_result = result
    encoded_runs = runs
    encoded_run_count = count
end)
assert(encode_calls == 0, "QR encoding ran inside the caller's frame")
assert(encoded_result == nil, "QR build completed synchronously")
drain_timers()
assert(encode_calls == 1, "QR encode ladder did not stop after success")
assert(encoded_result == matrix, "QR matrix callback returned the wrong matrix")
assert(#encoded_runs == 2340 * 4, "async QR build returned the wrong flat run buffer")
assert(encoded_run_count == 2340, "async QR build returned the wrong logical run count")
assert(timer_calls >= 11, "QR encode and analysis did not yield across frames")

local original_print = print
local failure_prints = 0
print = function(message)
    if string.find(tostring(message), "QR build failed", 1, true) then
        failure_prints = failure_prints + 1
    end
end
encode_should_fail = true
for generation = 10, 11 do
    harness.SetQRPaintJobGeneration(generation)
    harness.BuildQRMatrixAsync("fixture", false, false, generation, function() end)
    drain_timers()
end
assert(failure_prints == 1, "identical QR failures spammed chat")

encode_should_fail = false
harness.SetQRPaintJobGeneration(12)
harness.BuildQRMatrixAsync("fixture", false, false, 12, function() end)
drain_timers()
encode_should_fail = true
harness.SetQRPaintJobGeneration(13)
harness.BuildQRMatrixAsync("fixture", false, false, 13, function() end)
drain_timers()
assert(failure_prints == 2, "successful QR build did not reset failure notice suppression")
print = original_print

timer_queue = {}
timer_calls = 0
local dense = {}
for y = 1, 117 do
    local row = {}
    for x = 1, 117 do
        row[x] = (x % 2) == 1 and 1 or -1
    end
    dense[y] = row
end

harness.SetQRPaintJobGeneration(8)
local overflow_runs = false
local overflow_count = nil
harness.BuildQRBlackRunsAsync(dense, 6, 3500, 8, function(runs, count)
    overflow_runs = runs
    overflow_count = count
end)
drain_timers()
assert(overflow_runs == nil, "over-budget QR unexpectedly produced runs")
assert(overflow_count == 3501, "QR run builder did not stop at the budget boundary")

print("ok qr-run-chunking")
