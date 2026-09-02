local chunk = assert(loadfile("libs/qrencode.lua"))
setfenv(chunk, setmetatable({ testing = true }, { __index = _G }))
local qr = chunk()

-- Independent polynomial arithmetic: no production XOR/log/generator tables.
-- Field/generator contract: Nayuki QR Code generator v1.8.0, qrcodegen.py,
-- commit 720f62bddb7226106071d4728c292cb1df519ceb.
local function xor_integer(a, b)
    local result, bitValue = 0, 1
    while a > 0 or b > 0 do
        if a % 2 ~= b % 2 then result = result + bitValue end
        a, b = math.floor(a / 2), math.floor(b / 2)
        bitValue = bitValue * 2
    end
    return result
end

local exponents, logarithms = {}, {}
local element = 1
for power = 0, 254 do
    exponents[power] = element
    logarithms[element] = power
    element = element * 2
    if element >= 256 then element = xor_integer(element, 285) end
end

local function multiply(a, b)
    if a == 0 or b == 0 then return 0 end
    return exponents[(logarithms[a] + logarithms[b]) % 255]
end

local function divisor_for_degree(degree)
    local polynomial = { 1 }
    for power = 0, degree - 1 do
        local nextPolynomial = {}
        for index = 1, #polynomial + 1 do nextPolynomial[index] = 0 end
        for index, coefficient in ipairs(polynomial) do
            nextPolynomial[index] = xor_integer(nextPolynomial[index], coefficient)
            nextPolynomial[index + 1] = xor_integer(
                nextPolynomial[index + 1], multiply(coefficient, exponents[power])
            )
        end
        polynomial = nextPolynomial
    end
    return polynomial
end

local function reference_remainder(data, divisor)
    local dividend = {}
    for index, value in ipairs(data) do dividend[index] = value end
    for index = 1, #divisor - 1 do dividend[#data + index] = 0 end
    for offset = 1, #data do
        local factor = dividend[offset]
        for index, coefficient in ipairs(divisor) do
            local target = offset + index - 1
            dividend[target] = xor_integer(dividend[target], multiply(factor, coefficient))
        end
    end
    local result = {}
    for index = 1, #divisor - 1 do result[index] = dividend[#data + index] end
    return result
end

local function assert_equal(actual, expected, label)
    assert(#actual == #expected, label .. " changed the ECC length")
    for index, value in ipairs(expected) do
        assert(actual[index] == value, label .. " differs at ECC byte " .. index)
    end
end

local cases = 0
for _, degree in ipairs({ 7, 10, 13, 15, 16, 17, 18, 20, 22, 24, 26, 28, 30 }) do
    local divisor = divisor_for_degree(degree)
    for _, length in ipairs({ 0, 1, 19, 67, 123, 128 }) do
        for pattern = 0, 3 do
            local data, bitstrings = {}, {}
            for index = 1, length do
                local value = (index * 73 + length * 17 + degree * 11) % 256
                if pattern == 0 then value = 0 end
                if pattern == 1 then value = 255 end
                if pattern == 2 and index <= math.floor(length / 3) then value = 0 end
                data[index] = value
                bitstrings[index] = qr.binary(value, 8)
            end
            local expected = reference_remainder(data, divisor)
            local original = table.concat(data, ",")
            assert_equal(qr.calculate_error_correction(data, degree), expected, "table input")
            assert(table.concat(data, ",") == original, "ECC mutated caller-owned data")
            assert_equal(qr.calculate_error_correction(table.concat(bitstrings), degree),
                expected, "bitstring input")
            cases = cases + 1
        end
    end
end

-- Count actual GF additions, not elapsed time: host speed cannot make this
-- regression flaky. A division step touches only degree + 1 coefficients.
local operations = 0
local originalRows = {}
for coefficient = 0, 255 do
    local original = qr.xor_lookup[coefficient]
    originalRows[coefficient] = original
    qr.xor_lookup[coefficient] = setmetatable({}, {
        __index = function(_, value)
            operations = operations + 1
            return original[value]
        end,
    })
end
local data = {}
for index = 1, 128 do data[index] = (index * 73 + 11) % 256 end
local actual = qr.calculate_error_correction(data, 30)
for coefficient = 0, 255 do qr.xor_lookup[coefficient] = originalRows[coefficient] end
assert_equal(actual, reference_remainder(data, divisor_for_degree(30)), "counted input")
assert(operations <= #data * 31, string.format(
    "ECC performed %d XORs, exceeding the %d nonzero-support budget",
    operations, #data * 31
))

print(string.format("ok qr-error-correction cases=%d bounded=1", cases))
