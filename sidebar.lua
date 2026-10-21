-- Sidebar lines

local function teamsByEntry()
    local teams = {}
    for _, team in ipairs(starfish.scoreboard.teams()) do
        for _, entry in ipairs(team.players) do
            teams[entry] = team
        end
    end
    return teams
end

local function texts()
    local sidebar = starfish.scoreboard.sidebar()
    if not sidebar then return {} end

    local teams = teamsByEntry()
    local lines = {}
    for _, line in ipairs(sidebar.lines) do
        local team = teams[line.name]
        if team then table.insert(lines, starfish.text.plain(team.prefix .. team.suffix)) end
    end
    return lines
end

return {
    texts = texts,
}
