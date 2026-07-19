local env = assert(dofile("tests/lua/appscout_fixture_env.lua"))

local member_count = 2
local secret_guid = {}
local party_guids = { party1 = "Party-A" }
local scheduled = {}
local sent = 0
local lockdown = false
local fixture_print = print

GetNumGroupMembers = function() return member_count end
IsInRaid = function() return false end
UnitGUID = function(unit) return party_guids[unit] or "" end
issecretvalue = function(value) return value == secret_guid end
C_Timer.After = function(delay, callback)
    scheduled[#scheduled + 1] = { delay = delay, callback = callback }
end
C_ChatInfo = {
    InChatMessagingLockdown = function() return lockdown end,
    SendChatMessage = function()
        sent = sent + 1
    end,
}
ApplicantScoutDB = {
    enabled = true,
    autoHiGreetNewPartyMembers = true,
    autoHiMessage = "hi",
}

local harness = env.load_addon({})
assert(type(harness.PrimeAutoHiPartyMembers) == "function")
assert(type(harness.ResetAutoHiPartyMembers) == "function")
assert(type(harness.ScheduleAutoHiForNewPartyMembers) == "function")
assert(type(harness.SyncAutoHiInitialGroupState) == "function")
assert(type(harness.SetEnabled) == "function")

local function timer_count(delay)
    local count = 0
    for _, timer in ipairs(scheduled) do
        if timer.delay == delay then count = count + 1 end
    end
    return count
end

local function run_timer(delay)
    for index, timer in ipairs(scheduled) do
        if timer.delay == delay then
            table.remove(scheduled, index)
            timer.callback()
            return
        end
    end
    error("missing timer at delay " .. tostring(delay))
end

local function reset_case()
    harness.ResetAutoHiPartyMembers()
    scheduled = {}
    sent = 0
    lockdown = false
    member_count = 2
    party_guids = { party1 = "Party-A" }
end

-- An unreadable initial roster must be primed only after the first complete
-- sample. Existing members are not "new" merely because their GUID cleared.
party_guids.party1 = secret_guid
harness.PrimeAutoHiPartyMembers()
assert(timer_count(0.5) == 1, "incomplete initial sample did not schedule retry")
party_guids.party1 = "Party-A"
run_timer(0.5)
assert(timer_count(10) == 0, "initial incomplete sample greeted an existing member")

-- A transient unreadable sample must preserve the last complete baseline.
reset_case()
harness.PrimeAutoHiPartyMembers()
party_guids.party1 = secret_guid
harness.ScheduleAutoHiForNewPartyMembers()
party_guids.party1 = "Party-A"
run_timer(0.5)
assert(timer_count(10) == 0, "recovered GUID was treated as a new party member")

-- A join observed only as an incomplete sample is recovered without another
-- roster event and greeted exactly once.
member_count = 3
party_guids.party2 = secret_guid
harness.ScheduleAutoHiForNewPartyMembers()
assert(timer_count(0.5) == 1, "secret new member did not schedule a resample")
party_guids.party2 = "Party-B"
run_timer(0.5)
assert(timer_count(10) == 1, "recovered new member did not schedule a greeting")
harness.ScheduleAutoHiForNewPartyMembers()
assert(timer_count(10) == 1, "stable sample scheduled duplicate greetings")
run_timer(10)
assert(sent == 1, "recovered new member was not greeted exactly once")

-- A clean join also remains exactly-once across repeated identical samples.
reset_case()
harness.PrimeAutoHiPartyMembers()
member_count = 3
party_guids.party2 = "Party-B"
harness.ScheduleAutoHiForNewPartyMembers()
harness.ScheduleAutoHiForNewPartyMembers()
assert(timer_count(10) == 1, "clean join scheduled duplicate greetings")
run_timer(10)
assert(sent == 1, "clean join was not greeted exactly once")

-- An incomplete sample defers a confirmed join without forgetting it.
reset_case()
harness.PrimeAutoHiPartyMembers()
member_count = 3
party_guids.party2 = "Party-B"
harness.ScheduleAutoHiForNewPartyMembers()
party_guids.party1 = secret_guid
harness.ScheduleAutoHiForNewPartyMembers()
assert(timer_count(10) == 1 and timer_count(0.5) == 1)
run_timer(10)
assert(sent == 0, "greeting sent while party composition was incomplete")
party_guids.party1 = "Party-A"
run_timer(0.5)
assert(timer_count(10) == 1, "confirmed pending join was not rescheduled")
run_timer(10)
assert(sent == 1, "confirmed pending join was lost after incomplete sample")

-- If that pending joiner has actually left, recovery must not greet anyone.
reset_case()
harness.PrimeAutoHiPartyMembers()
member_count = 3
party_guids.party2 = "Party-B"
harness.ScheduleAutoHiForNewPartyMembers()
party_guids.party1 = secret_guid
harness.ScheduleAutoHiForNewPartyMembers()
run_timer(10)
party_guids.party1 = "Party-A"
party_guids.party2 = nil
member_count = 2
run_timer(0.5)
assert(timer_count(10) == 0 and sent == 0,
    "departed pending member still produced a greeting")

-- Persistent secret values exhaust the short retry budget without corrupting
-- the baseline. Combat-end recovery can still observe and greet the real join.
reset_case()
harness.PrimeAutoHiPartyMembers()
member_count = 3
party_guids.party2 = secret_guid
harness.ScheduleAutoHiForNewPartyMembers()
for _ = 1, 5 do run_timer(0.5) end
assert(timer_count(0.5) == 0 and timer_count(10) == 0 and sent == 0,
    "persistent incomplete sample escaped its retry budget")
party_guids.party2 = "Party-B"
harness.FireEvent("PLAYER_REGEN_ENABLED")
assert(timer_count(10) == 1, "combat-end did not recover pending party sample")
run_timer(10)
assert(sent == 1, "combat-end recovery did not greet the confirmed join")

-- A stale chat retry from an older membership generation must not erase the
-- pending joiners or timer owned by the newer generation.
reset_case()
harness.PrimeAutoHiPartyMembers()
member_count = 3
party_guids.party2 = "Party-B"
harness.ScheduleAutoHiForNewPartyMembers()
lockdown = true
run_timer(10)
assert(timer_count(1.0) == 1, "lockdown did not schedule chat retry")
lockdown = false
member_count = 4
party_guids.party3 = "Party-C"
harness.ScheduleAutoHiForNewPartyMembers()
assert(timer_count(10) == 1, "new generation did not retain a greeting")
run_timer(1.0)
run_timer(10)
assert(sent == 1, "stale chat retry erased the newer pending generation")

-- Re-entering the world with the same group state must reconcile rather than
-- re-prime away a join whose greeting is already delayed.
reset_case()
harness.SyncAutoHiInitialGroupState()
member_count = 3
party_guids.party2 = "Party-B"
harness.ScheduleAutoHiForNewPartyMembers()
harness.SyncAutoHiInitialGroupState()
assert(timer_count(10) == 1, "same-state world entry replaced pending baseline")
run_timer(10)
assert(sent == 1, "same-state world entry lost pending greeting")

-- Re-enable immediately primes the current party. A later join is therefore
-- compared with the enable-time baseline instead of being swallowed by it.
reset_case()
print = function() end
harness.SetEnabled(false)
scheduled = {}
harness.SetEnabled(true)
member_count = 3
party_guids.party2 = "Party-B"
harness.ScheduleAutoHiForNewPartyMembers()
assert(timer_count(10) == 1, "post-enable join was absorbed as initial baseline")
harness.SetEnabled(false)
run_timer(10)
assert(sent == 0, "disabled addon allowed a stale greeting timer to send")
scheduled = {}
harness.SetEnabled(true)
member_count = 4
party_guids.party3 = "Party-C"
harness.ScheduleAutoHiForNewPartyMembers()
run_timer(10)
assert(sent == 1, "re-enabled addon did not greet the next confirmed join")
print = fixture_print

-- Duplicate clean GUIDs cannot masquerade as a complete two-member sample.
reset_case()
harness.PrimeAutoHiPartyMembers()
member_count = 3
party_guids.party2 = "Party-A"
harness.ScheduleAutoHiForNewPartyMembers()
assert(timer_count(0.5) == 1 and timer_count(10) == 0,
    "duplicate GUID sample was accepted as complete")

fixture_print("auto-hi-party-sampling-ok")
