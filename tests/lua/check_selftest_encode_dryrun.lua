local namespace = {}
assert(loadfile("libs/qrencode.lua"))("ApplicantScout", namespace)
local qr = assert(namespace.QR, "missing QR namespace")
assert(type(qr.qrcode) == "function", "missing synchronous QR encoder")

local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

GetCVar = function(name)
    if name == "screenshotQuality" then return "8" end
    if name == "screenshotFormat" then return "jpg" end
    return nil
end

local frames = {}
local timers = {}
local in_combat = false
InCombatLockdown = function() return in_combat end
C_Timer.After = function(_delay, fn)
    timers[#timers + 1] = fn
end

local function stub_frame()
    local f = {
        __shown = false,
        __scripts = {},
        __text = nil,
    }
    f.SetSize = function() end
    f.SetPoint = function() end
    f.SetFrameStrata = function() end
    f.SetClampedToScreen = function() end
    f.EnableMouse = function() end
    f.SetBackdrop = function() end
    f.SetBackdropColor = function() end
    f.SetBackdropBorderColor = function() end
    f.SetScript = function(self, ev, fn) self.__scripts[ev] = fn end
    f.Show = function(self) self.__shown = true end
    f.Hide = function(self) self.__shown = false end
    f.IsShown = function(self) return self.__shown end
    f.RegisterEvent = function() end
    f.UnregisterAllEvents = function() end
    f.CreateFontString = function()
        return {
            SetPoint = function() end,
            SetSize = function() end,
            SetJustifyH = function() end,
            SetJustifyV = function() end,
            SetText = function() end,
        }
    end
    f.SetScrollChild = function(self, child) self.__scrollchild = child end
    f.SetMultiLine = function() end
    f.SetFontObject = function() end
    f.SetWidth = function() end
    f.SetHeight = function() end
    f.SetAutoFocus = function() end
    f.SetMaxLetters = function() end
    f.SetText = function(self, text) self.__text = text end
    f.SetCursorPosition = function() end
    f.SetFocus = function() end
    f.HighlightText = function() end
    f.ClearFocus = function() end
    frames[#frames + 1] = f
    return f
end
CreateFrame = function() return stub_frame() end

local function fresh_addon(with_qr)
    ApplicantScoutDB = { enabled = true, debug = false }
    ApplicantScoutSelfTest = nil
    frames = {}
    timers = {}
    in_combat = false
    if with_qr then
        return env.load_addon({ qrcode = qr.qrcode, qrcodeAsync = qr.qrcodeAsync })
    end
    return env.load_addon()
end

local captured = {}
local real_print = print
print = function(message)
    captured[#captured + 1] = tostring(message)
end

local function finish_run(harness)
    captured = {}
    SlashCmdList.APSCOUT("selftest start")
    env.start_session_quietly(harness)
    captured = {}
    SlashCmdList.APSCOUT("selftest")
    local chat = captured
    captured = {}
    local saved = print
    print = function() end
    harness.EndSession()
    print = saved
    return chat
end

local function report_map(report)
    local m = {}
    for _, line in ipairs(report) do
        local k, v = string.match(line, "^([A-Za-z0-9-]+)=(.+)$")
        if k then m[k] = v end
    end
    return m
end

local function encode_map(report)
    local m = {}
    for _, line in ipairs(report) do
        local k, v = string.match(line, "^(encode%-[a-z]+)=(.+)$")
        if k then m[k] = v end
    end
    return m
end

local function deep_equal(a, b, seen)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    seen = seen or {}
    if seen[a] then return seen[a] == b end
    seen[a] = b
    for k, v in pairs(a) do
        if not deep_equal(v, b[k], seen) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function snapshot_db()
    local out = {}
    for k, v in pairs(ApplicantScoutDB) do
        if type(v) == "table" then
            local inner = {}
            for k2, v2 in pairs(v) do inner[k2] = v2 end
            out[k] = inner
        else
            out[k] = v
        end
    end
    return out
end

local function box_text()
    for _, f in ipairs(frames) do
        if f.__scrollchild and f.__scrollchild.__text then
            return f.__scrollchild.__text
        end
        if f.__text and string.find(f.__text, "ASCOUT1: v=1", 1, true) then
            return f.__text
        end
    end
    return nil
end

local SHADOW_KEYS = {
    "snapshot", "delivery-sends", "job", "shot-lease", "shot-pending",
    "shot-throttled", "payload-bytes", "payload-error", "payload-applicants",
    "payload-roster", "payload-roster-incomplete", "payload-emitted",
    "qr-encode", "qr-bytes", "qr-error", "transport", "shot-result",
    "shot-fail", "tex-pool", "tex-used", "tex-high", "gameplay-suppressed",
    "suppress-reason", "combat", "mplus", "encounter", "loading", "dormant",
    "chat-lockdown", "overflow", "recoveries", "term-clear-dispatch",
    "session", "inspect-pending", "inspect-skipped", "inspect-exhausted",
}

-- OOC dry-run: genuine encode path, one chat line, window/SV in sync.
local harness = fresh_addon(true)
local chat = finish_run(harness)
assert(#chat == 6, "finish chat must be 6 lines, got " .. #chat)
local encode_line = nil
for _, line in ipairs(chat) do
    if string.find(line, "^  encode: ") then encode_line = line end
end
assert(encode_line ~= nil, "finish chat lost the encode line")
-- The dispatcher seeds DB defaults on first call (pre-existing InitDB
-- behavior); snapshot after seeding so the compare isolates the probe.
local db_before = snapshot_db()

local report = ApplicantScoutSelfTest.report
local enc = encode_map(report)
assert(enc["encode-ok"] == "true", "dry-run must report encode-ok=true")
assert(enc["encode-bytes"] == "86", "dry-run bytes mismatch: " .. tostring(enc["encode-bytes"]))
assert(enc["encode-version"] == "4", "dry-run version mismatch: " .. tostring(enc["encode-version"]))
assert(tonumber(enc["encode-ms"]) ~= nil, "dry-run ms must be numeric")
assert(enc["encode-skip"] == "none", "dry-run must not skip OOC")
local text = box_text()
assert(text ~= nil, "copy window has no report text")
for k, v in pairs(enc) do
    assert(string.find(text, "ASCOUT1: " .. k .. "=" .. v, 1, true) ~= nil,
        "window lost encode key: " .. k)
end

-- Determinism: a second consecutive run reports identical encode keys, and
-- no observable pipeline shadow moved between the two builds.
local first = report_map(report)
local chat2 = finish_run(harness)
assert(#chat2 == 6, "second finish chat must stay 6 lines")
local second = report_map(ApplicantScoutSelfTest.report)
local enc2 = encode_map(ApplicantScoutSelfTest.report)
for k, v in pairs(enc) do
    assert(enc2[k] == v, "encode key not deterministic: " .. k)
end
for _, k in ipairs(SHADOW_KEYS) do
    assert(second[k] == first[k], "pipeline shadow moved across dry-runs: " .. k)
end
assert(deep_equal(ApplicantScoutDB, db_before),
    "second dry-run changed ApplicantScoutDB")

-- Combat: OOC-only gate skips the probe with a reason; chat stays 6 lines.
in_combat = true
local combat_chat = finish_run(harness)
assert(#combat_chat == 6, "combat finish chat must stay 6 lines")
local combat_enc = encode_map(ApplicantScoutSelfTest.report)
assert(combat_enc["encode-ok"] == "false", "combat must not encode")
assert(combat_enc["encode-skip"] == "combat", "combat skip lost its reason")
assert(combat_enc["encode-bytes"] == "0", "combat skip must report zero bytes")
assert(combat_enc["encode-version"] == "0", "combat skip must report zero version")
in_combat = false

-- Missing library: fail-closed skip, no crash, same 6-line chat shape.
fresh_addon(false)
local nolib_chat = finish_run(harness)
assert(#nolib_chat == 6, "nolib finish chat must stay 6 lines")
local nolib_enc = encode_map(ApplicantScoutSelfTest.report)
assert(nolib_enc["encode-ok"] == "false", "nolib must not encode")
assert(nolib_enc["encode-skip"] == "nolib", "nolib skip lost its reason")

-- Secret-safety: the probe path only adds counters/flags, never identities.
local blob = box_text() or ""
for _, forbidden in ipairs({
    "Tankone", "Mageone", "Host", "Friend", "Healer", "Feral", "Ret",
    "Realm", "Player-", "secret", "payload=", "|c", "|H", "|T",
}) do
    assert(string.find(blob, forbidden, 1, true) == nil,
        "dry-run leaked forbidden surface: " .. forbidden)
end

print = real_print
print("ok selftest-encode-dryrun bytes=86 version=4")
