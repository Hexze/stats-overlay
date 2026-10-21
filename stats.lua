-- Constants

local FETCH_ATTEMPTS = 3
local RETRY_BASE_MS = 2000
local NICKED = { state = "nicked" }
local REFUSED = { state = "refused" }

-- Player identity

local members = {}

local function normalizeUuid(uuid)
    return uuid:gsub("-", ""):lower()
end

local function lookupIdentity(member)
    local denicker = starfish.plugins.optional("denicker")
    local realIdentity = denicker.getRealUuid(member.name) or denicker.getRealName(member.name)
    if realIdentity then return realIdentity end
    if denicker.isNicked(member.name) == true then return nil end
    return member.ownUuid
end

-- Stat lookups

local entries = {}

local function fetch(entry)
    entry.inFlight = true
    starfish.plugins.require("urchin").fetchPlayer(entry.identity)
end

local function retryLater(key, entry)
    entry.inFlight = false
    starfish.timers.delay(RETRY_BASE_MS * 2 ^ (entry.attempt - 1), function()
        if entries[key] ~= entry then return end
        entry.attempt = entry.attempt + 1
        fetch(entry)
    end)
end

local function request(uuid)
    local member = members[uuid]
    local identity = lookupIdentity(member)
    if not identity then return end

    local key = identity:lower()
    local existing = entries[key]
    if existing and existing.state ~= "error" then return end

    local entry = { state = "loading", identity = identity, parse = member.parse, attempt = 1 }
    entries[key] = entry
    fetch(entry)
end

local function track(player, ownUuid, parse)
    members[player.uuid] = { name = player.name, ownUuid = normalizeUuid(ownUuid), parse = parse }
    request(player.uuid)
end

local function settle(event)
    local key = event.player:lower()
    local entry = entries[key]
    if not (entry and entry.inFlight) then return false end

    if event.data then
        entries[key] = { state = "loaded", stats = entry.parse(event.data) }
    elseif event.error == "nicked" then
        entries[key] = NICKED
    elseif not event.retryable then
        entries[key] = REFUSED
    elseif entry.attempt < FETCH_ATTEMPTS then
        retryLater(key, entry)
        return false
    else
        entries[key] = { state = "error" }
    end
    return true
end

local function of(uuid)
    local identity = lookupIdentity(members[uuid])
    if not identity then return NICKED end
    return entries[identity:lower()]
end

local function reset()
    entries, members = {}, {}
end

return {
    track = track,
    request = request,
    settle = settle,
    of = of,
    reset = reset,
}
