local sidebar = require("sidebar")

-- Constants

local RESPAWN_SECONDS = 5
local RECONNECT_RESPAWN_SECONDS = 10
local COUNTDOWN_STEP_MS = 1000
local RESPAWN_CONFIRM_GRACE_MS = 500
local COUNTDOWN_BADGE = "§8[§c%ds§8]"
local BED_BADGE = "§8[§a§l✓§8]"
local DISCONNECTED_BADGE = "§8[§cx§8]"
local BED_STANDING = "✓"
local TEAM_BED_LINE = "(%a+): (%S+)"
local FINAL_KILL = "FINAL KILL!"
local GAME_END_LINE = "^%s*1st Killer "
local REJOIN_MESSAGES = {
    ["You will respawn in 10 seconds!"] = "respawn",
    ["Your bed was destroyed so you are a spectator!"] = "spectator",
}
local TEAM_COLORS = {
    Red = "§c", Blue = "§9", Green = "§a", Yellow = "§e",
    Aqua = "§b", White = "§f", Pink = "§d", Gray = "§8",
}
local DEATH_PHRASES = {
    " was ", "fell into the void", "hit the ground too hard",
    "burned to death", "drowned", "went up in flames", " died",
}

-- Chat lines

local function isDeathMessage(message)
    if message:sub(-1) ~= "." then return false end
    for _, phrase in ipairs(DEATH_PHRASES) do
        if message:find(phrase, 1, true) then return true end
    end
    return false
end

local function isFinalKill(message)
    return message:sub(-#FINAL_KILL) == FINAL_KILL
end

local function eliminatedTeamColor(message)
    return TEAM_COLORS[message:match("^TEAM ELIMINATED > (%a+) Team") or ""]
end

-- Player states

local function kindOf(game, uuid)
    local state = game.states[uuid]
    return state and state.kind or "alive"
end

local function cancelCountdown(game, uuid)
    local state = game.states[uuid]
    if state and state.timer then state.timer:off() end
end

local function markEliminated(game, uuid)
    cancelCountdown(game, uuid)
    game.states[uuid] = { kind = "eliminated" }
    game.roster.forget(uuid)
end

local function markDisconnected(game, uuid)
    local kind = kindOf(game, uuid)
    if kind == "disconnected" or kind == "eliminated" then return end
    cancelCountdown(game, uuid)
    game.states[uuid] = { kind = "disconnected" }
    game.roster.changed()
end

local function clearDisconnected(game, uuid)
    if kindOf(game, uuid) ~= "disconnected" then return end
    game.states[uuid] = nil
    game.roster.changed()
end

local function markTeamEliminated(game, teamColor)
    for _, uuid in ipairs(game.roster.members()) do
        if game.roster.teamColorOf(uuid) == teamColor then
            markEliminated(game, uuid)
        end
    end
end

local function confirmRespawned(game, uuid)
    if game.stopped or game.states[uuid] then return end
    if game.roster.isUnlisted(uuid) then
        markDisconnected(game, uuid)
    end
end

local function countDown(game, uuid, respawn)
    respawn.remaining = respawn.remaining - 1
    game.roster.changed()
    if respawn.remaining > 0 then return end

    respawn.timer:off()
    game.states[uuid] = nil
    starfish.timers.delay(RESPAWN_CONFIRM_GRACE_MS, function()
        confirmRespawned(game, uuid)
    end)
end

local function trackRespawn(game, uuid, seconds)
    if kindOf(game, uuid) == "eliminated" then return end
    cancelCountdown(game, uuid)

    local respawn = { kind = "respawning", remaining = seconds }
    respawn.timer = starfish.timers.interval(COUNTDOWN_STEP_MS, function()
        countDown(game, uuid, respawn)
    end)
    game.states[uuid] = respawn
    game.roster.changed()
end

local function reseat(game, from, to)
    local state = game.states[from]
    game.states[from] = nil
    if not state then return end
    if state.timer then state.timer:off() end
    if state.kind == "respawning" and not game.states[to] then
        trackRespawn(game, to, state.remaining)
    end
end

local function stop(game)
    game.stopped = true
    for uuid, state in pairs(game.states) do
        if state.kind == "respawning" then
            state.timer:off()
            game.states[uuid] = nil
        end
    end
    game.roster.changed()
end

-- Row status

local function respawnSecondsOf(game, uuid)
    if kindOf(game, uuid) ~= "respawning" or not starfish.config.get("respawnTimer.enabled") then return nil end
    return game.states[uuid].remaining
end

local function standingBeds()
    local beds = {}
    for _, text in ipairs(sidebar.texts()) do
        local team, mark = text:match(TEAM_BED_LINE)
        local color = TEAM_COLORS[team or ""]
        if color then beds[color] = mark == BED_STANDING end
    end
    return beds
end

local function isDimmed(game, uuid)
    return kindOf(game, uuid) == "disconnected" or respawnSecondsOf(game, uuid) ~= nil
end

local function badgeOf(game, uuid)
    if kindOf(game, uuid) == "disconnected" then return DISCONNECTED_BADGE end

    local seconds = respawnSecondsOf(game, uuid)
    if seconds then return COUNTDOWN_BADGE:format(seconds) end

    if standingBeds()[game.roster.teamColorOf(uuid)] then return BED_BADGE end
    return nil
end

local function allBadges()
    local badges = { BED_BADGE, DISCONNECTED_BADGE }
    for seconds = 1, RECONNECT_RESPAWN_SECONDS do
        table.insert(badges, COUNTDOWN_BADGE:format(seconds))
    end
    return badges
end

local function isKept(game, uuid)
    local kind = kindOf(game, uuid)
    if kind == "eliminated" then return false end
    if kind == "disconnected" then return starfish.config.get("keepDisconnected.enabled") end
    return true
end

-- Chat handling

local function applyRejoin(game, rejoin)
    local me = starfish.players.me()
    if not me then return end

    if rejoin == "spectator" then
        markEliminated(game, me.uuid)
    else
        trackRespawn(game, me.uuid, RECONNECT_RESPAWN_SECONDS)
    end
end

local function applyPlayerLine(game, message)
    local name, action = message:match("^([%w_]+) (.+)$")
    local uuid = name and game.roster.uuidOf(name)
    if not uuid then return end

    if isFinalKill(message) then
        markEliminated(game, uuid)
    elseif action:find("^disconnected%.") then
        markDisconnected(game, uuid)
    elseif action == "reconnected." then
        trackRespawn(game, uuid, RECONNECT_RESPAWN_SECONDS)
    elseif isDeathMessage(message) then
        trackRespawn(game, uuid, RESPAWN_SECONDS)
    end
end

local function isGameEnd(message)
    for line in message:gmatch("[^\n]+") do
        if line:find(GAME_END_LINE) then return true end
    end
    return false
end

local function handleChat(game, message)
    if game.stopped or message:find(":", 1, true) then return end

    local rejoin = REJOIN_MESSAGES[message]
    local eliminatedTeam = eliminatedTeamColor(message)
    if rejoin then
        applyRejoin(game, rejoin)
    elseif isGameEnd(message) then
        stop(game)
    elseif eliminatedTeam then
        markTeamEliminated(game, eliminatedTeam)
    else
        applyPlayerLine(game, message)
    end
end

-- Tracker

local function newTracker(roster)
    local game = { roster = roster, states = {}, stopped = false }
    return {
        onChat = function(message) handleChat(game, message) end,
        onListed = function(uuid) clearDisconnected(game, uuid) end,
        kindOf = function(uuid) return kindOf(game, uuid) end,
        reseat = function(from, to) reseat(game, from, to) end,
        badge = function(uuid) return badgeOf(game, uuid) end,
        allBadges = allBadges,
        isDimmed = function(uuid) return isDimmed(game, uuid) end,
        keeps = function(uuid) return isKept(game, uuid) end,
        stop = function() stop(game) end,
    }
end

return newTracker
