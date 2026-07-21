local logic = {}

local DEFAULT_DIVISION = 4

function logic.normalizeDivision(value)
    local number = tonumber(value)
    if number == nil or number % 1 ~= 0 or number < 1 or number > 4 then
        return DEFAULT_DIVISION
    end
    return number
end

function logic.widths(columnCount, division)
    if columnCount < 1 then
        return {}
    end

    local visible = math.min(columnCount, logic.normalizeDivision(division))
    local width = 100 / visible
    local result = {}
    for index = 1, columnCount do
        result[index] = width
    end
    return result
end

function logic.anchorIndex(columns, division, focusedColumnIndex)
    if #columns <= logic.normalizeDivision(division) or focusedColumnIndex == nil then
        return 1
    end
    for index, column in ipairs(columns) do
        if column.index == focusedColumnIndex then
            return math.max(1, index - logic.normalizeDivision(division) + 1)
        end
    end
    return 1
end

local function topology(window, previous)
    if type(window) ~= "table" then
        return nil, nil
    end

    local id = tonumber(window.id)
    if not id then
        return nil, nil
    end

    local layout = window.layout
    local position = type(layout) == "table" and layout.pos_in_scrolling_layout or nil
    local floating = previous and previous.floating
    if type(window.is_floating) == "boolean" then
        floating = window.is_floating
    end
    return id, {
        workspaceId = tonumber(window.workspace_id) or (previous and previous.workspaceId),
        floating = floating,
        columnIndex = type(position) == "table" and tonumber(position[1])
            or (layout == nil and previous and previous.columnIndex),
    }
end

local function sameTopology(a, b)
    return a ~= nil and b ~= nil
        and a.workspaceId == b.workspaceId
        and a.floating == b.floating
        and a.columnIndex == b.columnIndex
end

function logic.groupColumns(windows)
    local byWorkspace = {}
    local focusedColumns = {}
    local focusedId = nil

    for _, window in ipairs(windows) do
        if window.is_focused then
            focusedId = tonumber(window.id)
        end

        local layout = window.layout
        local position = type(layout) == "table" and layout.pos_in_scrolling_layout or nil
        local workspaceId = tonumber(window.workspace_id)
        local windowId = tonumber(window.id)
        local columnIndex = type(position) == "table" and tonumber(position[1]) or nil

        if not window.is_floating and workspaceId and windowId and columnIndex then
            byWorkspace[workspaceId] = byWorkspace[workspaceId] or {}
            byWorkspace[workspaceId][columnIndex] = byWorkspace[workspaceId][columnIndex] or windowId
            if window.is_focused then
                focusedColumns[workspaceId] = columnIndex
            end
        end
    end

    local workspaces = {}
    for workspaceId, columnsByIndex in pairs(byWorkspace) do
        local columns = {}
        for columnIndex, windowId in pairs(columnsByIndex) do
            table.insert(columns, { index = columnIndex, windowId = windowId })
        end
        table.sort(columns, function(a, b) return a.index < b.index end)
        table.insert(workspaces, {
            id = workspaceId,
            columns = columns,
            focusedColumnIndex = focusedColumns[workspaceId],
        })
    end
    table.sort(workspaces, function(a, b) return a.id < b.id end)

    return workspaces, focusedId
end

function logic.shouldRedistribute(event, knownIds)
    local closed = type(event) == "table" and event.WindowClosed or nil
    if type(closed) == "table" and tonumber(closed.id) then
        knownIds[tonumber(closed.id)] = nil
        return true
    end

    local changed = type(event) == "table" and event.WindowOpenedOrChanged or nil
    local window = type(changed) == "table" and changed.window or nil
    local id, nextTopology = topology(window, type(window) == "table" and knownIds[tonumber(window.id)])
    if id then
        local different = not sameTopology(knownIds[id], nextTopology)
        knownIds[id] = nextTopology
        return different
    end

    local allChanged = type(event) == "table" and event.WindowsChanged or nil
    local windows = type(allChanged) == "table" and allChanged.windows or nil
    if type(windows) == "table" then
        local nextIds = {}
        for _, item in ipairs(windows) do
            local itemId, itemTopology = topology(
                item, type(item) == "table" and knownIds[tonumber(item.id)])
            if itemId then
                nextIds[itemId] = itemTopology
            end
        end

        local different = false
        for itemId, itemTopology in pairs(nextIds) do
            different = different or not sameTopology(knownIds[itemId], itemTopology)
        end
        for itemId in pairs(knownIds) do
            different = different or not nextIds[itemId]
            knownIds[itemId] = nil
        end
        for itemId, itemTopology in pairs(nextIds) do
            knownIds[itemId] = itemTopology
        end
        return different
    end

    local layoutsChanged = type(event) == "table" and event.WindowLayoutsChanged or nil
    local changes = type(layoutsChanged) == "table" and layoutsChanged.changes or nil
    if type(changes) == "table" then
        local different = false
        for _, change in ipairs(changes) do
            local id = type(change) == "table" and tonumber(change[1]) or nil
            local current = id and knownIds[id] or nil
            local layout = type(change) == "table" and change[2] or nil
            local position = type(layout) == "table" and layout.pos_in_scrolling_layout or nil
            local columnIndex = type(position) == "table" and tonumber(position[1]) or nil
            if current and current.columnIndex ~= columnIndex then
                current.columnIndex = columnIndex
                different = true
            end
        end
        return different
    end

    return false
end

if noctalia == nil then
    return logic
end

local divisionPath = noctalia.pluginDataDir()
divisionPath = divisionPath and divisionPath .. "/division" or nil

local division = logic.normalizeDivision(divisionPath and noctalia.readFile(divisionPath) or nil)
local knownIds = {}
local busy = false
local rerun = false
local debounceTicks = nil
local streamStarted = false

local function action(command)
    return "(niri msg action " .. command .. " >/dev/null 2>&1)"
end

local function buildCommand(windows)
    local workspaces, focusedId = logic.groupColumns(windows)
    local commands = {}

    for _, workspace in ipairs(workspaces) do
        local widths = logic.widths(#workspace.columns, division)
        for index, column in ipairs(workspace.columns) do
            table.insert(commands, action("focus-window --id " .. column.windowId)
                .. " && " .. action("set-column-width " .. widths[index] .. "%"))
        end

        local anchor = workspace.columns[logic.anchorIndex(
            workspace.columns, division, workspace.focusedColumnIndex)]
        if anchor then
            table.insert(commands, action("focus-window --id " .. anchor.windowId))
            table.insert(commands, action("center-visible-columns"))
        end
    end

    if focusedId then
        table.insert(commands, action("focus-window --id " .. focusedId))
    end

    return table.concat(commands, "; ")
end

local function finishRedistribution()
    busy = false
    if rerun then
        rerun = false
        debounceTicks = 0
    end
end

local redistribute

local function startStream()
    if streamStarted then
        return
    end
    streamStarted = true

    if not noctalia.runStream("niri msg -j event-stream", function(line)
        local event = noctalia.json.decode(line)
        if event and logic.shouldRedistribute(event, knownIds) then
            debounceTicks = 3
        end
    end) then
        noctalia.log("failed to start niri event stream")
    end
end

redistribute = function(initialize)
    if busy then
        rerun = true
        return
    end
    busy = true

    if not noctalia.runAsync("niri msg -j windows", function(result)
        local windows = result.exitCode == 0 and noctalia.json.decode(result.stdout) or nil
        if type(windows) ~= "table" then
            noctalia.log("failed to read niri windows: " .. (result.stderr or "unknown error"))
            if initialize then
                startStream()
            end
            finishRedistribution()
            return
        end

        if initialize then
            for _, window in ipairs(windows) do
                local id, windowTopology = topology(window)
                if id then
                    knownIds[id] = windowTopology
                end
            end
            startStream()
        end

        local command = buildCommand(windows)
        if command == "" then
            finishRedistribution()
        elseif not noctalia.runAsync(command, function(layoutResult)
            if layoutResult.exitCode ~= 0 then
                noctalia.log("niri redistribution failed: " .. (layoutResult.stderr or "unknown error"))
            end
            finishRedistribution()
        end) then
            noctalia.log("failed to start niri redistribution")
            finishRedistribution()
        end
    end) then
        noctalia.log("failed to query niri windows")
        if initialize then
            startStream()
        end
        finishRedistribution()
    end
end

noctalia.state.set("division", division)
noctalia.state.watch("division", function(value)
    local nextDivision = logic.normalizeDivision(value)
    if nextDivision ~= division then
        division = nextDivision
        redistribute(false)
    end
end)

noctalia.setUpdateInterval(50)

function update()
    if debounceTicks == nil then
        return
    end
    if debounceTicks > 0 then
        debounceTicks = debounceTicks - 1
        return
    end
    debounceTicks = nil
    redistribute(false)
end

redistribute(true)
