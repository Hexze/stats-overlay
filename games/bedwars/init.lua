local newTracker = require("games.bedwars.tracker")

-- Constants

local SERVER_TYPE = "BEDWARS"
local SIDEBAR_NAME = "Bed Wars"
local PRE_GAME_SIDEBAR = "^Pre"
local PLACEHOLDER_UUID_VERSION = "2"
local RATIO_BASE_COLOR = "§7"
local RATIO_COLORS = {
    { 100, "§5" }, { 50, "§d" }, { 30, "§4" }, { 20, "§c" }, { 10, "§6" },
    { 7, "§e" }, { 5, "§2" }, { 3, "§a" }, { 1, "§f" },
}
local KDR_COLORS = {
    { 8, "§5" }, { 7, "§d" }, { 6, "§4" }, { 5, "§c" }, { 4, "§6" },
    { 3, "§e" }, { 2, "§2" }, { 1, "§a" }, { 0.5, "§f" },
}
local FINALS_COLORS = {
    { 100000, "§5" }, { 50000, "§d" }, { 25000, "§4" }, { 15000, "§c" }, { 7500, "§6" },
    { 5000, "§e" }, { 2500, "§2" }, { 1000, "§a" }, { 500, "§f" },
}
local COUNT_COLOR = "§f"

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

local function tierColor(value, tiers)
    for _, tier in ipairs(tiers) do
        if value >= tier[1] then return tier[2] end
    end
    return RATIO_BASE_COLOR
end

local function ratioColor(value)
    return tierColor(value, RATIO_COLORS)
end

local function ratio(hits, misses)
    return (hits or 0) / math.max(1, misses or 1)
end

local function formatNumber(n)
    local result = tostring(math.floor(n))
    local pos = #result - 3
    while pos > 0 do
        result = result:sub(1, pos) .. "," .. result:sub(pos + 1)
        pos = pos - 3
    end
    return result
end

local function formatRatio(value)
    return (string.format("%.2f", value):gsub("%.00$", ""))
end

local function parseStats(player)
    local bedwarsStats = player.stats and player.stats.Bedwars or {}
    local achievedLevel = player.achievements and player.achievements.bedwars_level
    local level = starfish.plugins.require("urchin").bedwarsLevel(bedwarsStats.Experience, achievedLevel)

    return {
        starText = level.starText,
        fkdr = ratio(bedwarsStats.final_kills_bedwars, bedwarsStats.final_deaths_bedwars),
        wlr = ratio(bedwarsStats.wins_bedwars, bedwarsStats.losses_bedwars),
        bblr = ratio(bedwarsStats.beds_broken_bedwars, bedwarsStats.beds_lost_bedwars),
        kdr = ratio(bedwarsStats.kills_bedwars, bedwarsStats.deaths_bedwars),
        finals = bedwarsStats.final_kills_bedwars or 0,
        wins = bedwarsStats.wins_bedwars or 0,
        beds = bedwarsStats.beds_broken_bedwars or 0,
        kills = bedwarsStats.kills_bedwars or 0,
    }
end

-- Columns

local function ratioColumn(header, field)
    return {
        header = header, loading = "§8-.-", unavailable = "§c?.?",
        format = function(stats) return ratioColor(stats[field]) .. string.format("%.1f", stats[field]) end,
    }
end

local function countColumn(header, field)
    return {
        header = header, loading = "§8-", unavailable = "§c?",
        format = function(stats) return COUNT_COLOR .. formatNumber(stats[field]) end,
    }
end

local COLUMNS = {
    star = { header = "✫", loading = "§8[---✫]", unavailable = "§c[???✫]", format = function(stats) return stats.starText end },
    name = { header = "Name", isName = true },
    fkdr = ratioColumn("FKDR", "fkdr"),
    wlr = ratioColumn("WLR", "wlr"),
    bblr = ratioColumn("BBLR", "bblr"),
    kdr = {
        header = "KDR", loading = "§8-.-", unavailable = "§c?.?",
        format = function(stats) return tierColor(stats.kdr, KDR_COLORS) .. formatRatio(stats.kdr) end,
    },
    finals = {
        header = "Finals", loading = "§8-", unavailable = "§c?",
        format = function(stats) return tierColor(stats.finals, FINALS_COLORS) .. formatNumber(stats.finals) end,
    },
    wins = countColumn("Wins", "wins"),
    beds = countColumn("Beds", "beds"),
    kills = countColumn("Kills", "kills"),
}

local SLOT_CONTENTS = {
    { text = "Star", value = "star" },
    { text = "Name", value = "name" },
    { text = "FKDR", value = "fkdr" },
    { text = "WLR", value = "wlr" },
    { text = "BBLR", value = "bblr" },
    { text = "KDR", value = "kdr" },
    { text = "Finals", value = "finals" },
    { text = "Wins", value = "wins" },
    { text = "Beds", value = "beds" },
    { text = "Kills", value = "kills" },
}

local DEFAULT_SLOTS = {
    { content = "star", shown = true },
    { content = "name", shown = true },
    { content = "fkdr", shown = true },
    { content = "finals", shown = true },
    { content = "wlr", shown = false },
    { content = "kdr", shown = false },
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
    slotContents = SLOT_CONTENTS,
    defaultSlots = DEFAULT_SLOTS,
    newTracker = newTracker,
}
