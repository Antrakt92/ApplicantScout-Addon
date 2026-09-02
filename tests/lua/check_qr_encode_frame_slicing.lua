local namespace = {}
assert(loadfile("libs/qrencode.lua"))("ApplicantScout", namespace)

local qr = assert(namespace.QR, "missing QR namespace")
local encode_sync = assert(qr.qrcode, "missing synchronous QR encoder")
local encode_async = assert(qr.qrcodeAsync, "missing frame-sliced QR encoder")

local function matrices_equal(left, right)
    if #left ~= #right then return false end
    for x = 1, #left do
        if #left[x] ~= #right[x] then return false end
        for y = 1, #left[x] do
            if left[x][y] ~= right[x][y] then return false end
        end
    end
    return true
end

local function run_case(data, ec_level)
    local queue = {}
    local completed = false
    local async_ok = nil
    local async_result = nil

    encode_async(
        data,
        ec_level,
        nil,
        function(callback)
            queue[#queue + 1] = callback
        end,
        function() return false end,
        function(ok, result)
            completed = true
            async_ok = ok
            async_result = result
        end
    )

    assert(not completed, "frame-sliced encoder completed synchronously")
    local slices = 0
    while #queue > 0 do
        assert(#queue == 1, "frame-sliced encoder queued concurrent slices")
        local callback = table.remove(queue, 1)
        slices = slices + 1
        callback()
    end

    local sync_ok, sync_result = encode_sync(data, ec_level)
    assert(sync_ok and completed and async_ok, "QR encode failed")
    assert(matrices_equal(sync_result, async_result),
        "frame-sliced QR matrix differs from synchronous output")
    assert(slices == 9,
        string.format("QR encode used %d slices instead of setup + eight masks", slices))
    return slices
end

local max_slices = 0
local binary_bytes = {}
for value = 0, 255 do binary_bytes[#binary_bytes + 1] = string.char(value) end
local maximum_binary = string.sub(string.rep(table.concat(binary_bytes), 12), 1, 2953)
for _, case in ipairs({
    { "APS1", 2 },
    { string.rep("A", 800), 1 },
    { string.rep("B", 2400), 1 },
    { "APS1\0binary\255payload", 2 },
    { string.rep("AB", 2148), 1 },
    { string.sub(string.rep("1234567890", 709), 1, 7089), 1 },
    { maximum_binary, 1 },
    { string.rep("Protected payload ", 20), 4 },
}) do
    max_slices = math.max(max_slices, run_case(case[1], case[2]))
end

for cancel_after_slice = 0, 8 do
    local queue = {}
    local cancelled = false
    local completed = false
    encode_async(
        string.rep("C", 1600),
        1,
        nil,
        function(callback) queue[#queue + 1] = callback end,
        function() return cancelled end,
        function() completed = true end
    )
    for _ = 1, cancel_after_slice do
        assert(#queue == 1, "cancel fixture lost the next encoding slice")
        table.remove(queue, 1)()
    end
    assert(#queue == 1, "cancel fixture did not queue the next slice")
    cancelled = true
    table.remove(queue, 1)()
    assert(not completed and #queue == 0,
        "cancelled QR encode completed or retained callbacks")
end

do
    local queue = {}
    local completed = false
    local encode_ok = true
    encode_async(
        string.rep("D", 5000),
        1,
        nil,
        function(callback) queue[#queue + 1] = callback end,
        function() return false end,
        function(ok)
            completed = true
            encode_ok = ok
        end
    )
    while #queue > 0 do table.remove(queue, 1)() end
    assert(completed and not encode_ok,
        "oversized frame-sliced encode did not fail asynchronously")
end

print(string.format(
    "ok qr-encode-frame-slicing cases=8 max-slices=%d",
    max_slices
))
