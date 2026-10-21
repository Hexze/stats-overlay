plugin = {
    name = "stats-overlay",
    displayName = "Stats Overlay",
    version = "1.0.0",
    description = "Reworked tablist that shows players' stats ingame",
    dependencies = {
        { name = "hypixel-mod-api" },
        { name = "urchin" },
        { name = "denicker", optional = true },
    },
}

local game = require("games.bedwars")
local replay = require("replay")
local stats = require("stats")
local tab = require("tab")
local tabOrder = require("tab_order")

-- Config schema

starfish.schema.section({
    key = "gameState",
    label = "Game State",
    description = "Follow deaths, disconnects and eliminations in the tab list.",
    settings = {
        { key = "respawnTimer.enabled", type = "toggle", default = true, label = "Respawn Timer", description = "Show a countdown while a player respawns." },
        { key = "keepDisconnected.enabled", type = "toggle", default = true, label = "Keep Disconnected", description = "Keep disconnected players in tab, marked [x], until they reconnect." },
    },
})

-- Game session

local session

local function resetSession()
    tab.hide()
    tabOrder.deactivate()
    stats.reset()
    session = { inGame = false, replay = false, live = false, rules = game.rules }
end

local function follow(player)
    if not session.rules.isMember(player) then
        tab.forget(player.uuid)
        return
    end
    stats.track(player, session.rules.lookupUuid(player), game.parseStats)
    tab.track(player.uuid, player.name)
end

local function isGameReady()
    if session.replay then return replay.gameName() == game.sidebarName end
    return session.inGame and game.hasStarted()
end

local function activateOnceLive()
    if session.live or not isGameReady() then return end
    session.live = true
    tab.show(game.columns, session.rules.acceptsTeamPrefix, session.tracker)
    if session.replay then tabOrder.activate() end
    for _, player in ipairs(starfish.players.all()) do
        follow(player)
    end
end

local function activateOnceReplayedGameShows()
    if session.replay then activateOnceLive() end
end

local function applyLocation(location)
    if location.serverName ~= session.server then
        resetSession()
        session.server = location.serverName
    end

    session.replay = replay.isReplay(location)
    session.rules = session.replay and replay.rules or game.rules
    session.inGame = game.isGame(location)
    if session.inGame and not session.tracker then
        session.tracker = game.newTracker(tab.roster)
    end
    activateOnceLive()
end

-- Event wiring

starfish.events.on("hypixel:location", function(event)
    if event.success then applyLocation(event.location) end
end)

starfish.events.on("session:join", function()
    resetSession()
end)

starfish.events.on("chat:receive", function(event)
    if event.kind == "actionBar" or not session.tracker then return end
    session.tracker.onChat(starfish.text.plain(event.message))
end)

starfish.events.on("scoreboard:displayChange", function()
    activateOnceLive()
    tab.markDirty()
end)

starfish.events.on("scoreboard:scoreUpdate", function(event)
    activateOnceReplayedGameShows()
    local list = starfish.scoreboard.displayed("list")
    if list and list.name == event.objectiveName then tab.markDirty() end
end)

starfish.events.on("player:join", function(event)
    if not session.live then return end
    follow(event)
    tab.refreshNow()
end)

starfish.events.on("player:listUpdate", function(event)
    if event.action ~= "remove" then return end
    for _, player in ipairs(event.players) do
        tab.unlist(player.uuid)
    end
end)

starfish.events.on("team:update", function()
    activateOnceReplayedGameShows()
    tab.refreshNow()
end)

starfish.events.on("config:changed", function()
    tab.markDirty()
end)

starfish.events.on("urchin:playerFetched", function(event)
    if stats.settle(event) then tab.markDirty() end
end)

starfish.events.on("denicker:nick_resolved", function(event)
    if not tab.tracks(event.uuid) then return end
    stats.request(event.uuid)
    tab.markDirty()
end)

-- Startup

resetSession()

local restored = starfish.plugins.require("hypixel-mod-api").getLocation()
if restored and restored.serverName then
    applyLocation(restored)
end
