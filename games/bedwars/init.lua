local newTracker = require("games.bedwars.tracker")

-- Constants

local SERVER_TYPE = "BEDWARS"
local SIDEBAR_NAME = "Bed Wars"
local PRE_GAME_SIDEBAR = "^Pre"
local PLACEHOLDER_UUID_VERSION = "2"
local FKDR_BASE_COLOR = "§7"
local FKDR_COLORS = {
    { 100, "§5" }, { 50, "§d" }, { 30, "§4" }, { 20, "§c" }, { 10, "§6" },
    { 7, "§e" }, { 5, "§2" }, { 3, "§a" }, { 1, "§f" },
}

-- Game detection

local function isGame(location)
    return location.serverType == SERVER_TYPE and location.lobbyName == nil and location.mode ~= nil
end

local function hasStarted()
    local sidebar = starfish.scoreboard.displayed("sidebar")
    return sidebar ~= nil and sidebar.name:match(PRE_GAME_SIDEBAR) == nil
end

-- Membership

local function isMember(player)
    return player.uuid:sub(15, 15) ~= PLACEHOLDER_UUID_VERSION
end

local function ownUuid(player)
    return player.uuid
end

local function hasVisibleText(teamPrefix)
    return starfish.text.plain(teamPrefix) ~= ""
end

-- Stats

local function fkdrColor(fkdr)
    for _, tier in ipairs(FKDR_COLORS) do
        if fkdr >= tier[1] then return tier[2] end
    end
    return FKDR_BASE_COLOR
end

local function parseStats(player)
    local bedwarsStats = player.stats and player.stats.Bedwars or {}
    local achievedLevel = player.achievements and player.achievements.bedwars_level
    local level = starfish.plugins.require("urchin").bedwarsLevel(bedwarsStats.Experience, achievedLevel)

    return {
        starText = level.starText,
        fkdr = (bedwarsStats.final_kills_bedwars or 0) / math.max(1, bedwarsStats.final_deaths_bedwars or 1),
    }
end

-- Columns

local COLUMNS = {
    {
        header = "✫",
        loading = "§8[---✫]",
        unavailable = "§c[???✫]",
        format = function(stats) return stats.starText end,
    },
    {
        header = "Name",
        isName = true,
    },
    {
        header = "FKDR",
        loading = "§8-.-",
        unavailable = "§c?.?",
        format = function(stats) return fkdrColor(stats.fkdr) .. string.format("%.1f", stats.fkdr) end,
    },
}

return {
    sidebarName = SIDEBAR_NAME,
    isGame = isGame,
    hasStarted = hasStarted,
    rules = {
        isMember = isMember,
        lookupUuid = ownUuid,
        acceptsTeamPrefix = hasVisibleText,
    },
    parseStats = parseStats,
    columns = COLUMNS,
    newTracker = newTracker,
}
