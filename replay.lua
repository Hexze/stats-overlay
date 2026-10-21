local sidebar = require("sidebar")

-- Constants

local SERVER_TYPE = "REPLAY"
local RECORDED_UUID_VERSION = "2"
local TRUNCATED_NAME_LENGTH = 14
local GAME_LINE = "^Game:%s*(.-)%s*$"

-- Location

local function isReplay(location)
    return location.serverType == SERVER_TYPE
end

-- Sidebar

local function gameName()
    for _, text in ipairs(sidebar.texts()) do
        local name = text:match(GAME_LINE)
        if name then return name end
    end
    return nil
end

-- Roster

local function isRecorded(player)
    return player.uuid:sub(15, 15) == RECORDED_UUID_VERSION
end

local function skinProfile(uuid)
    local listed = starfish.players.byUuid(uuid)
    local textures = listed and listed.properties.textures
    local decoded = textures and starfish.base64.decode(textures.value)
    local ok, profile = pcall(starfish.json.decode, decoded or "")
    return ok and type(profile) == "table" and profile or {}
end

local function continuesName(profileName, name)
    if profileName == name then return true end
    return type(profileName) == "string" and #name == TRUNCATED_NAME_LENGTH and profileName:sub(1, #name) == name
end

local function lookupUuid(player)
    local profile = skinProfile(player.uuid)
    return continuesName(profile.profileName, player.name) and profile.profileId or player.uuid
end

local function anyTeamPrefix()
    return true
end

return {
    isReplay = isReplay,
    gameName = gameName,
    rules = {
        isMember = isRecorded,
        lookupUuid = lookupUuid,
        acceptsTeamPrefix = anyTeamPrefix,
    },
}
