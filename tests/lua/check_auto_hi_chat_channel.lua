local env = dofile("tests/lua/appscout_fixture_env.lua")

LE_PARTY_CATEGORY_HOME = 1
LE_PARTY_CATEGORY_INSTANCE = 2

local homeGroup = false
local instanceGroup = false
local raid = false

IsInGroup = function(category)
    if category == LE_PARTY_CATEGORY_HOME then return homeGroup end
    if category == LE_PARTY_CATEGORY_INSTANCE then return instanceGroup end
    return homeGroup or instanceGroup
end
IsInRaid = function() return raid end
IsInInstance = function() return true, "party" end

local harness = env.load_addon()
local channel = harness.AutoHiChatChannel
assert(type(channel) == "function", "missing Auto Hi chat-channel fixture hook")

homeGroup = true
instanceGroup = false
raid = false
assert(channel() == "PARTY",
    "premade party inside a dungeon did not use PARTY chat")

homeGroup = false
instanceGroup = true
raid = false
assert(channel() == "INSTANCE_CHAT",
    "queued instance group did not use INSTANCE_CHAT")

homeGroup = true
instanceGroup = true
raid = true
assert(channel() == "RAID",
    "home raid did not take precedence over instance-group membership")

homeGroup = true
instanceGroup = false
raid = true
assert(channel() == "RAID", "home raid did not use RAID chat")

io.write("auto-hi-chat-channel-ok\n")
