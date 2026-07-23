local env = dofile("tests/lua/appscout_fixture_env.lua")

ApplicantScoutDB = {
    autoHiMessage = string.rep("Ж", 140),
}

local harness = env.load_addon()
local maxBytes = harness.AutoHiMaxBytes()
assert(maxBytes == 160, "Auto Hi byte budget drifted")

local normalize = harness.NormalizeAutoHiMessage
assert(type(normalize) == "function", "missing Auto Hi normalizer fixture hook")

local ascii = normalize(string.rep("a", 300))
assert(#ascii == 160 and ascii == string.rep("a", 160),
    "ASCII Auto Hi message did not stop at the byte ceiling")

local cyrillic = normalize(string.rep("Ж", 140))
assert(#cyrillic == 160 and cyrillic == string.rep("Ж", 80),
    "Cyrillic Auto Hi message was split or counted as letters")

local emoji = normalize(string.rep("😀", 70))
assert(#emoji == 160 and emoji == string.rep("😀", 40),
    "four-byte Auto Hi code point was split")

local exact = normalize(string.rep("a", 158) .. "Ж")
assert(#exact == 160 and exact == string.rep("a", 158) .. "Ж",
    "exact-boundary UTF-8 Auto Hi message was shortened")

local splitCyrillic = normalize(string.rep("a", 159) .. "Ж")
assert(#splitCyrillic == 159 and splitCyrillic == string.rep("a", 159),
    "two-byte Auto Hi code point was split")

local mixed = normalize(string.rep("a", 158) .. " " .. "😀")
assert(#mixed == 158 and mixed == string.rep("a", 158),
    "truncation left trailing whitespace before a split code point")

assert(normalize(" \n hi\t ") == "hi", "control/whitespace normalization drifted")
assert(normalize({}) == "", "non-string Auto Hi value was accepted")
assert(normalize(emoji) == emoji, "Auto Hi normalization is not idempotent")

local realPrint = print
print = function() end
local ok, err = pcall(SlashCmdList.APSCOUT, "")
print = realPrint
assert(ok, tostring(err))
assert(#ApplicantScoutDB.autoHiMessage == 160,
    "oversized saved Auto Hi message was not normalized on load")
assert(ApplicantScoutDB.autoHiMessage == string.rep("Ж", 80),
    "saved Auto Hi message ended with partial UTF-8")

io.write("auto-hi-message-bytes-ok\n")
