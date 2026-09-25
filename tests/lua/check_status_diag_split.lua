local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

GetCVar = function(name)
    if name == "screenshotQuality" then return "8" end
    if name == "screenshotFormat" then return "jpg" end
    return nil
end

ApplicantScoutDB = { enabled = true, debug = false }

local harness = env.load_addon()
assert(type(harness.StartSession) == "function", "session harness is unavailable")

local captured = {}
local real_print = print
print = function(message)
    captured[#captured + 1] = tostring(message)
end

local function run_status(argument)
    captured = {}
    if argument then
        SlashCmdList.APSCOUT("status " .. argument)
    else
        SlashCmdList.APSCOUT("status")
    end
    return captured
end

local function contains(lines, fragment)
    for _, line in ipairs(lines) do
        if string.find(line, fragment, 1, true) then return true end
    end
    return false
end

-- Short status: bounded user summary with the required fields.
local short = run_status()
assert(#short <= 15, "short status exceeded 15 lines: " .. #short)
assert(contains(short, "enabled: true"), "short status lost the enabled line")
assert(contains(short, "session: idle"), "short status lost the session line")
assert(contains(short, "suppressed: no")
    or contains(short, "suppressed: yes ("),
    "short status lost the suppression line")
assert(contains(short, "QR: hidden"), "short status lost the QR visibility line")
assert(contains(short, "last shot: never"), "short status lost the last-shot line")
assert(contains(short, "debug: off"), "short status lost the debug line")
assert(contains(short, "one-way transport"), "short status lost the one-way hint")
assert(contains(short, "status diag"), "short status lost the diag pointer")

-- Debug reminder: the ON state must point back at the off switch.
-- Set after the first slash call so the one-time debug migration keeps it.
ApplicantScoutDB.debug = true
local short_debug = run_status()
assert(contains(short_debug, "debug: ON"), "short status hid debug ON")
assert(contains(short_debug, "/apscout debug off"),
    "short status lost the debug reminder")
ApplicantScoutDB.debug = false

-- Full diagnostics stay behind "status diag" and keep delivery order.
local diag = run_status("diag")
assert(#diag > #short, "diag output did not expand beyond short status")
local hash_idx, delivery_idx, sends_idx, pending_idx
for index, line in ipairs(diag) do
    if not hash_idx and string.find(line, "last snapshot hash:", 1, true) then
        hash_idx = index
    elseif not delivery_idx
        and string.find(line, "last delivery snapshot hash:", 1, true) then
        delivery_idx = index
    elseif not sends_idx
        and string.find(line, "last delivery snapshot sends:", 1, true) then
        sends_idx = index
    elseif not pending_idx
        and string.find(line, "pending throttled shot:", 1, true) then
        pending_idx = index
    end
end
assert(hash_idx and delivery_idx and sends_idx and pending_idx,
    "diag output lost delivery diagnostics")
assert(hash_idx < delivery_idx and delivery_idx < sends_idx
    and sends_idx < pending_idx, "diag delivery diagnostics out of order")

-- Session start stays exactly one user-visible line with the emit signal.
captured = {}
harness.StartSession()
assert(#captured == 1, "session start must print exactly one line")
assert(contains(captured, "emitting"),
    "session start line lost the emitting signal")
assert(contains(captured, "companion"),
    "session start line lost the companion signal")
harness.EndSession()
captured = {}
env.start_session_quietly(harness)
assert(#captured == 0, "quiet session start leaked print output")

print = real_print
print("ok status-diag-split short=" .. #short .. " diag=" .. #diag)
