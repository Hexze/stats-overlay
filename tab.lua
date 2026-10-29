local stats = require("stats")

-- Constants

local REFRESH_MS = 500
local SUFFIX_PRIORITY = 100
local SEPARATOR = "§r §8| §r"
local DIMMED_NAME_COLOR = "§7"
local HEADER_LABEL_COLOR = "§7"
local SPACE = "§r "
local BOLD_SPACES = "§l%s§r"
local SPACE_WIDTH = 4
local BOLD_EXTRA_WIDTH = 1
local BOLD_SPACE_WIDTH = SPACE_WIDTH + BOLD_EXTRA_WIDTH
local ALWAYS_PADDABLE_WIDTH = 12
local TAB_HEAD_WIDTH = 9
local TAB_ENTRY_SPARE_WIDTH = 13
local TAB_HEARTS_WIDTH = 90
local TAB_ROWS_PER_COLUMN = 20
local HEARTS = "hearts"
local NO_TEAM = { prefix = "", suffix = "" }
local UNTRACKED = {
    onListed = function() end,
    kindOf = function() return "alive" end,
    reseat = function() end,
    badge = function() end,
    allBadges = function() return {} end,
    isDimmed = function() return false end,
    keeps = function() return false end,
}

-- Text measurement

local textWidth = starfish.display.textWidth

local function teamColorOf(teamPrefix)
    local last = nil
    for code in teamPrefix:gmatch("§([0-9a-f])") do
        last = code
    end
    return last and ("§" .. last) or ""
end

-- Padding

local function spaceCounts(deficit)
    local width = math.max(0, math.floor(deficit))
    local boldNeeded = width % SPACE_WIDTH // BOLD_EXTRA_WIDTH
    local bold = math.min(boldNeeded, width // BOLD_SPACE_WIDTH)
    return (width - bold * BOLD_SPACE_WIDTH) // SPACE_WIDTH, bold
end

local function padWidth(deficit)
    local normal, bold = spaceCounts(deficit)
    return normal * SPACE_WIDTH + bold * BOLD_SPACE_WIDTH
end

local function padSpaces(deficit)
    local normal, bold = spaceCounts(deficit)
    local boldSpaces = bold > 0 and BOLD_SPACES:format((" "):rep(bold)) or ""
    return SPACE:rep(normal) .. boldSpaces, padWidth(deficit)
end

local function padsExactly(deficit)
    return padWidth(deficit) == math.floor(deficit)
end

local function padsEveryCell(width, cellWidths)
    for _, cellWidth in ipairs(cellWidths) do
        if not padsExactly(width - cellWidth) then return false end
    end
    return true
end

local function paddableWidth(cellWidths)
    local widest = math.max(0, table.unpack(cellWidths))
    for slack = 0, ALWAYS_PADDABLE_WIDTH do
        if padsEveryCell(widest + slack, cellWidths) then return widest + slack end
    end
end

-- Roster

local managed = {}
local acceptsTeamPrefix = nil
local tracker = nil

local function othersChanged()
    for uuid, entry in pairs(managed) do
        if entry.othersPrefix ~= starfish.display.othersPrefix(uuid) then return true end
        if entry.othersSuffix ~= starfish.display.othersSuffix(uuid) then return true end
    end
    return false
end

local function snapshotIdentity(uuid, entry)
    entry.othersPrefix, entry.othersSuffix = starfish.display.othersPrefix(uuid), starfish.display.othersSuffix(uuid)
    entry.drawnTeamPrefix = starfish.display.teamPrefix(uuid) or ""
    local player = starfish.players.byUuid(uuid)
    if not player then return end

    entry.displayName = player.displayName or player.name
    local team = player.team or NO_TEAM
    if acceptsTeamPrefix(team.prefix) then
        entry.teamPrefix, entry.teamSuffix = team.prefix, team.suffix
    end
end

local function uuidOf(name)
    local held = nil
    for uuid, entry in pairs(managed) do
        if entry.name == name then
            if entry.listed then return uuid end
            held = uuid
        end
    end
    return held
end

local function memberTeamColor(uuid)
    return teamColorOf(managed[uuid].teamPrefix or "")
end

local function isUnlisted(uuid)
    local entry = managed[uuid]
    return entry ~= nil and not entry.listed
end

local function members()
    local uuids = {}
    for uuid in pairs(managed) do
        table.insert(uuids, uuid)
    end
    return uuids
end

-- Layout

local function leadText(entry)
    return (entry.teamPrefix or "") .. entry.othersPrefix
end

local function nameText(entry)
    return entry.displayName .. (entry.teamSuffix or "") .. entry.othersSuffix
end

local function badgeSlotWidth(badges)
    if #badges == 0 then return 0 end
    local widths, widest = { 0 }, 0
    for _, badge in ipairs(badges) do
        table.insert(widths, textWidth(badge))
        widest = math.max(widest, textWidth(badge))
    end
    for width = widest + SPACE_WIDTH, widest + SPACE_WIDTH + ALWAYS_PADDABLE_WIDTH do
        if padsEveryCell(width, widths) then return width end
    end
end

local function nameColor(entry, row)
    if row.dimmed then return DIMMED_NAME_COLOR end
    return teamColorOf(entry.teamPrefix or entry.drawnTeamPrefix)
end

local function cellText(column, playerStats)
    if not playerStats or playerStats.state == "loading" then return column.loading end
    if playerStats.state == "loaded" then return column.format(playerStats.stats) end
    return column.unavailable
end

local function measureRow(uuid, entry, columns)
    local playerStats = stats.of(uuid)
    local row = { cells = {}, widths = {}, badge = tracker.badge(uuid) or "", dimmed = tracker.isDimmed(uuid) }
    for index, column in ipairs(columns) do
        if column.isName then
            row.cells[index] = ""
            row.widths[index] = textWidth(nameText(entry))
        else
            row.cells[index] = cellText(column, playerStats)
            row.widths[index] = textWidth(row.cells[index])
        end
    end
    return row
end

local function computeLayout(columns)
    local layout = { columns = columns, widths = {}, contentWidths = {}, rows = {} }
    local leadWidths, cellWidths = {}, {}
    for index, column in ipairs(columns) do
        cellWidths[index] = { textWidth(column.header) }
        layout.contentWidths[index] = textWidth(column.header)
        if column.isName then layout.nameIndex = index end
    end

    for uuid, entry in pairs(managed) do
        local row = measureRow(uuid, entry, columns)
        layout.rows[uuid] = row
        table.insert(leadWidths, textWidth(leadText(entry)))
        for index, width in ipairs(row.widths) do
            table.insert(cellWidths[index], width)
            layout.contentWidths[index] = math.max(layout.contentWidths[index], width)
        end
    end

    layout.leadWidth = paddableWidth(leadWidths)
    layout.badgeWidth = badgeSlotWidth(tracker.allBadges())
    for index, widths in ipairs(cellWidths) do
        layout.widths[index] = paddableWidth(widths)
    end
    return layout
end

-- Row composition

local function placeFixed(cursor, parts, text)
    local width = textWidth(text)
    table.insert(parts, text)
    cursor.x, cursor.target = cursor.x + width, cursor.target + width
end

local function placeAligned(cursor, parts, text, width, slotWidth, alignRight)
    cursor.target = cursor.target + slotWidth
    local pad, padWidth = padSpaces(cursor.target - cursor.x - width)

    if alignRight then
        table.insert(parts, pad)
        table.insert(parts, text)
    else
        table.insert(parts, text)
        table.insert(parts, pad)
    end
    cursor.x = cursor.x + width + padWidth
end

local function placeCell(cursor, parts, index, alignRight)
    local row, layout = cursor.row, cursor.layout
    placeAligned(cursor, parts, row.cells[index], row.widths[index], layout.widths[index], alignRight)
end

local function splitPad(deficit, desiredLeft)
    local best = 0
    for left = 0, math.floor(deficit) do
        local exact = padsExactly(left) and padsExactly(deficit - left)
        if exact and math.abs(left - desiredLeft) < math.abs(best - desiredLeft) then best = left end
    end
    return best
end

local function placeCentred(cursor, parts, text, width, slotWidth, centre)
    local slotStart = cursor.target
    cursor.target = cursor.target + slotWidth
    local deficit = cursor.target - cursor.x - width
    local left = splitPad(deficit, slotStart + centre - width / 2 - cursor.x)
    local leftPad, leftWidth = padSpaces(left)
    local rightPad, rightWidth = padSpaces(deficit - left)

    table.insert(parts, leftPad .. text .. rightPad)
    cursor.x = cursor.x + leftWidth + width + rightWidth
end

local function placeBadge(cursor, parts)
    local slotWidth, badge = cursor.layout.badgeWidth, cursor.row.badge
    if slotWidth == 0 then return end
    placeCentred(cursor, parts, badge, textWidth(badge), slotWidth, (slotWidth - SPACE_WIDTH) / 2)
end

local function labelCentre(layout, index)
    local width, content = layout.widths[index], layout.contentWidths[index]
    local contentStart = index < layout.nameIndex and width - content or 0
    return contentStart + content / 2
end

local function placeLabel(cursor, parts, index)
    local layout, label = cursor.layout, cursor.layout.columns[index].header
    placeCentred(cursor, parts, HEADER_LABEL_COLOR .. label, textWidth(label), layout.widths[index], labelCentre(layout, index))
end

local function replacedTeamPrefix(entry)
    if acceptsTeamPrefix(entry.drawnTeamPrefix) then return "" end
    return entry.teamPrefix or ""
end

local function composeRow(entry, row, layout)
    local leadWidth = textWidth(leadText(entry))
    local leadPad, leadPadWidth = padSpaces(layout.leadWidth - leadWidth)
    local prefix, suffix = { replacedTeamPrefix(entry), leadPad }, {}
    local cursor = { row = row, layout = layout, x = leadWidth + leadPadWidth, target = layout.leadWidth }

    placeBadge(cursor, prefix)
    for index = 1, layout.nameIndex - 1 do
        placeCell(cursor, prefix, index, true)
        placeFixed(cursor, prefix, SEPARATOR)
    end
    table.insert(prefix, nameColor(entry, row))

    if layout.nameIndex < #layout.columns then
        placeCell(cursor, suffix, layout.nameIndex, false)
        for index = layout.nameIndex + 1, #layout.columns do
            placeFixed(cursor, suffix, SEPARATOR)
            placeCell(cursor, suffix, index, false)
        end
    else
        cursor.x = cursor.x + row.widths[layout.nameIndex]
    end

    return table.concat(prefix), table.concat(suffix), cursor.x
end

local function composeLabels(layout)
    local cursor = { layout = layout, x = 0, target = 0 }
    local parts = {}
    for index = 1, #layout.columns do
        if index > 1 then placeFixed(cursor, parts, SEPARATOR) end
        placeLabel(cursor, parts, index)
    end
    return table.concat(parts), cursor.x
end

-- Header alignment

local function scoreHolder(player)
    local teammates = player.team and player.team.players or {}
    for _, teammate in ipairs(teammates) do
        if starfish.text.plain(teammate) == player.name then return teammate end
    end
    return player.name
end

local function tabEntryNames()
    local names = {}
    for _, player in ipairs(starfish.players.all()) do
        table.insert(names, scoreHolder(player))
    end
    for _, entry in pairs(managed) do
        if not entry.listed then table.insert(names, entry.name) end
    end
    return names
end

local function foreignRowWidth(player)
    local team, uuid = player.team or NO_TEAM, player.uuid
    local lead = team.prefix .. starfish.display.othersPrefix(uuid)
    return textWidth(lead .. player.displayName .. team.suffix .. starfish.display.othersSuffix(uuid))
end

local function widestForeignRow()
    local widest = 0
    for _, player in ipairs(starfish.players.all()) do
        if not managed[player.uuid] then widest = math.max(widest, foreignRowWidth(player)) end
    end
    return widest
end

local function listObjectiveWidth(names)
    local objective = starfish.scoreboard.displayed("list")
    if not objective then return 0 end
    if objective.type == HEARTS then return TAB_HEARTS_WIDTH end

    local widest = 0
    for _, name in ipairs(names) do
        local score = starfish.scoreboard.score(objective.name, name) or 0
        widest = math.max(widest, textWidth(" " .. score))
    end
    return widest
end

local function labelsOffsetFromCenter(layout, labelsWidth, widestRow, names)
    local entryWidth = TAB_HEAD_WIDTH + widestRow + listObjectiveWidth(names) + TAB_ENTRY_SPARE_WIDTH
    local firstCellX = TAB_HEAD_WIDTH + layout.leadWidth + layout.badgeWidth - entryWidth / 2
    return firstCellX + labelsWidth / 2
end

local function centeredAtOffset(text, offset)
    local shift = 2 * math.abs(offset)
    local longWidth = paddableWidth({ 0, shift })
    local long, short = padSpaces(longWidth), padSpaces(longWidth - shift)
    return offset > 0 and long .. text .. short or short .. text .. long
end

local function headerText(layout, widestRow)
    local labels, labelsWidth = composeLabels(layout)
    local names = tabEntryNames()
    if #names > TAB_ROWS_PER_COLUMN then return "\n" .. labels end
    return "\n" .. centeredAtOffset(labels, labelsOffsetFromCenter(layout, labelsWidth, widestRow, names))
end

-- Tab rendering

local columns = {}
local applied = {}
local appliedHeader = nil
local refreshTimer = nil
local dirty = false

local function applyRow(uuid, entry, prefix, suffix)
    local rendered = table.concat({ entry.drawnTeamPrefix, prefix, suffix }, "\0")
    if applied[uuid] == rendered then return end
    applied[uuid] = rendered
    starfish.display.setPrefix(uuid, prefix)
    starfish.display.setSuffix(uuid, suffix, { priority = SUFFIX_PRIORITY })
end

local function applyRows(layout)
    local widestRow = 0
    for uuid, entry in pairs(managed) do
        local prefix, suffix, width = composeRow(entry, layout.rows[uuid], layout)
        applyRow(uuid, entry, prefix, suffix)
        widestRow = math.max(widestRow, width)
    end
    return widestRow
end

local function applyHeader(text)
    if appliedHeader == text then return end
    appliedHeader = text
    starfish.display.setTabHeader(text)
end

-- Membership

local function forget(uuid)
    if not managed[uuid] then return end
    managed[uuid], applied[uuid] = nil, nil
    starfish.display.clear(uuid)
    starfish.display.releaseRemoval(uuid)
    dirty = true
end

local function reconcile(uuid, entry)
    if tracker.keeps(uuid) then
        starfish.display.holdRemoval(uuid)
        return
    end
    starfish.display.releaseRemoval(uuid)
    if not entry.listed then forget(uuid) end
end

local function track(uuid, name)
    local entry = managed[uuid] or { seatPending = true }
    entry.name, entry.displayName, entry.listed = name, name, true
    snapshotIdentity(uuid, entry)
    managed[uuid] = entry
    tracker.onListed(uuid)
    reconcile(uuid, entry)
    dirty = true
end

local function tracks(uuid)
    return managed[uuid] ~= nil
end

local function unlist(uuid)
    local entry = managed[uuid]
    if not entry then return end
    entry.listed = false
    reconcile(uuid, entry)
    dirty = true
end

local function markDirty()
    dirty = true
end

-- Seats

local function isAway(uuid)
    local kind = tracker.kindOf(uuid)
    return kind == "disconnected" or kind == "respawning"
end

local function formerSeatOf(uuid, entry)
    local color = memberTeamColor(uuid)
    local disconnectedTeammates = {}
    for other, held in pairs(managed) do
        if other ~= uuid and not held.listed and isAway(other) then
            if held.name == entry.name then return other end
            if color ~= "" and tracker.kindOf(other) == "disconnected" and memberTeamColor(other) == color then
                table.insert(disconnectedTeammates, other)
            end
        end
    end
    return #disconnectedTeammates == 1 and disconnectedTeammates[1] or nil
end

local function settleSeat(uuid, entry)
    local former = formerSeatOf(uuid, entry)
    if former then
        tracker.reseat(former, uuid)
        forget(former)
    end
    if former or memberTeamColor(uuid) ~= "" then entry.seatPending = nil end
end

local function settleSeats()
    for uuid, entry in pairs(managed) do
        if entry.seatPending and entry.listed then settleSeat(uuid, entry) end
    end
end

-- Tab lifecycle

local function refresh()
    if not (dirty or othersChanged()) then return end
    dirty = false

    for uuid, entry in pairs(managed) do
        reconcile(uuid, entry)
    end
    for uuid, entry in pairs(managed) do
        snapshotIdentity(uuid, entry)
    end
    settleSeats()

    local layout = computeLayout(columns)
    local widestRow = math.max(applyRows(layout), widestForeignRow())
    applyHeader(headerText(layout, widestRow))
end

local function refreshNow()
    if not refreshTimer then return end
    dirty = true
    refresh()
end

local function hide()
    if refreshTimer then refreshTimer:off() end
    refreshTimer = nil
    for uuid in pairs(managed) do
        starfish.display.releaseRemoval(uuid)
    end
    starfish.display.clearAll()
    managed, applied, appliedHeader, tracker = {}, {}, nil, nil
end

local function show(gameColumns, teamPrefixRule, gameTracker)
    hide()
    columns, acceptsTeamPrefix, tracker = gameColumns, teamPrefixRule, gameTracker or UNTRACKED
    dirty = true
    refreshTimer = starfish.timers.interval(REFRESH_MS, refresh)
end

local function setColumns(gameColumns)
    columns = gameColumns
    dirty = true
end

return {
    show = show,
    setColumns = setColumns,
    hide = hide,
    track = track,
    tracks = tracks,
    unlist = unlist,
    forget = forget,
    markDirty = markDirty,
    refreshNow = refreshNow,
    roster = {
        uuidOf = uuidOf,
        teamColorOf = memberTeamColor,
        isUnlisted = isUnlisted,
        members = members,
        forget = forget,
        changed = markDirty,
    },
}
