local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

GetCVar = function(name)
    if name == "screenshotQuality" then return "8" end
    if name == "screenshotFormat" then return "jpg" end
    return nil
end

ApplicantScoutDB = { enabled = true, debug = false }
ApplicantScoutSelfTest = nil

local harness = env.load_addon()
assert(type(harness.StartSession) == "function", "session harness is unavailable")
assert(type(SlashCmdList.APSCOUT) == "function", "slash dispatcher is unavailable")

local captured = {}
local real_print = print
print = function(message)
    captured[#captured + 1] = tostring(message)
end

local function run_selftest(argument)
    captured = {}
    if argument then
        SlashCmdList.APSCOUT("selftest " .. argument)
    else
        SlashCmdList.APSCOUT("selftest")
    end
    return captured
end

local function contains(lines, fragment)
    for _, line in ipairs(lines) do
        if string.find(line, fragment, 1, true) then return true end
    end
    return false
end

-- Stop with no active run stays a control message, never an export.
local idle_stop = run_selftest("stop")
assert(#idle_stop == 1, "idle stop must print exactly one line")
assert(contains(idle_stop, "no run active"), "idle stop lost the hint")
assert(not contains(idle_stop, "ASCOUT1:"), "idle stop leaked export prefix")

-- Unknown subcommand prints usage, never an export.
local bogus = run_selftest("frobnicate")
assert(#bogus == 1, "unknown arg must print exactly one line")
assert(contains(bogus, "[start|stop|cancel]"), "unknown arg lost the usage hint")
assert(not contains(bogus, "ASCOUT1:"), "unknown arg leaked export prefix")

-- Start arms a run with one control line.
local started = run_selftest()
assert(#started == 1, "start must print exactly one line")
assert(contains(started, "started"), "start lost the started signal")
assert(not contains(started, "ASCOUT1:"), "start leaked export prefix")
assert(ApplicantScoutSelfTest == nil, "start must not persist")

-- Restarting while active re-arms without exporting.
local restarted = run_selftest("start")
assert(#restarted == 1, "restart must print exactly one line")
assert(contains(restarted, "started"), "restart lost the started signal")

-- Cancel drops the run without exporting or persisting.
local cancelled = run_selftest("cancel")
assert(#cancelled == 1, "cancel must print exactly one line")
assert(contains(cancelled, "cancelled"), "cancel lost the signal")
assert(ApplicantScoutSelfTest == nil, "cancel must not persist")

-- Fresh run, then finish under an active session for coverage.
run_selftest("start")
captured = {}
env.start_session_quietly(harness)
assert(#captured == 0, "quiet session start leaked print output")
local finished = run_selftest()
harness.EndSession()

assert(#finished >= 40, "export too small: " .. #finished)
assert(#finished <= 96, "export exceeded cap: " .. #finished)

local keys = {}
for index, line in ipairs(finished) do
    local key, value = string.match(line, "^ASCOUT1: ([A-Za-z0-9-]+)=(.+)$")
    assert(key ~= nil, "line " .. index .. " broke ASCOUT1: key=value shape: " .. line)
    assert(value ~= nil and value ~= "", "line " .. index .. " has empty value")
    assert(string.find(value, "=", 1, true) == nil,
        "line " .. index .. " value breaks key=value parsing: " .. line)
    assert(#line <= 160, "line " .. index .. " is not short: " .. #line)
    keys[key] = value
end

for _, required in ipairs({
    "v", "addon", "game", "build", "iface", "region",
    "enabled", "debug", "session", "session-gen",
    "scan-ticker", "poll-age", "shot-age", "snapshot", "delivery-sends",
    "transport", "shot-result", "shot-fail",
    "gameplay-suppressed", "suppress-reason", "interaction-defer",
    "qr-visible", "chat-lockdown",
    "inspect-pending", "inspect-age", "inspect-skipped", "inspect-exhausted",
    "payload-bytes", "payload-applicants", "payload-roster",
    "tex-pool", "qr-encode", "autohi", "libks", "leader-key",
    "hooks", "term-clear-dispatch",
    "run-dur", "d-sends", "d-recoveries", "d-shot-fail", "done",
}) do
    assert(keys[required] ~= nil, "export lost required key: " .. required)
end

assert(keys["v"] == "1", "export version must be 1")
assert(keys["transport"] == "one-way", "transport must stay one-way")
assert(keys["session"] == "active", "export under session must say active")
assert(keys["enabled"] == "true", "export lost the enabled state")
assert(keys["scan-ticker"] == "on" or keys["scan-ticker"] == "off",
    "scan ticker state must be on/off")
assert(keys["done"] == "lines-" .. tostring(#finished),
    "done line must carry the exact line count")

-- SavedVariable shape: separate SV, one last run, bounded report.
local sv = ApplicantScoutSelfTest
assert(type(sv) == "table", "selftest SV was not persisted")
assert(sv.version == 1, "selftest SV version must be 1")
assert(type(sv.finishedAt) == "number", "selftest SV finishedAt must be a number")
assert(type(sv.report) == "table", "selftest SV report must be a table")
assert(#sv.report == #finished, "SV report must match the printed block")
for index, line in ipairs(finished) do
    assert(sv.report[index] == string.match(line, "^ASCOUT1: (.+)$"),
        "SV report line " .. index .. " differs from chat export")
end

-- Secret-safety: no fixture identities, GUIDs, payload content, or keys.
local blob = table.concat(finished, "\n")
for _, forbidden in ipairs({
    "Tankone", "Mageone", "Host", "Friend", "Healer", "Feral", "Ret",
    "Realm", "Player-", "secret", "payload=", "|c", "|H", "|T",
}) do
    assert(string.find(blob, forbidden, 1, true) == nil,
        "export leaked forbidden surface: " .. forbidden)
end

-- ApplicantScoutDB stays the addon's own store: no selftest keys in it.
assert(type(ApplicantScoutDB) == "table", "addon DB must stay a table")
assert(ApplicantScoutDB.ApplicantScoutSelfTest == nil,
    "selftest must not nest inside ApplicantScoutDB")
assert(ApplicantScoutDB.enabled == true, "selftest changed the enabled flag")
assert(ApplicantScoutDB.debug == false, "selftest changed the debug flag")

print = real_print
print("ok selftest-export lines=" .. #finished)
