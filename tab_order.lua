-- Constants

local ALIAS_MARKER = "~"
local ALIAS_FORMAT = "%s%s%06d"

-- Colour groups

local aliases = {}
local issued = 0
local subscription = nil

local function bareColour(prefix)
    if prefix:gsub("§.", "") ~= "" then return nil end

    local colour = nil
    for code in prefix:gmatch("§(%x)") do
        colour = code:lower()
    end
    return colour
end

local function aliasFor(teamName, colour)
    local alias = aliases[teamName]
    if alias and alias.colour == colour then return alias.name end

    issued = issued + 1
    alias = { colour = colour, name = ALIAS_FORMAT:format(ALIAS_MARKER, colour, issued) }
    aliases[teamName] = alias
    return alias.name
end

local function groupByColour(packet)
    if packet.mode ~= "create" then return end

    local colour = bareColour(packet.prefix)
    if colour then packet:setName(aliasFor(packet.realName, colour)) end
end

-- Lifecycle

local function activate()
    if subscription then return end
    subscription = starfish.scoreboard.onTeams(groupByColour)
end

local function deactivate()
    if not subscription then return end
    subscription:off()
    subscription = nil
    aliases, issued = {}, 0
end

-- Exports

return {
    activate = activate,
    deactivate = deactivate,
}
