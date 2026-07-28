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
    local visible = logic.normalizeDivision(division)
    if columnCount <= visible then
        return {}
    end

    local width = 100 / visible
    local result = {}
    for index = 1, columnCount do
        result[index] = width
    end
    return result
end

function logic.visibleRange(columns, division, focusedColumnIndex)
    local visible = logic.normalizeDivision(division)
    if #columns <= visible then
        return 1, #columns
    end

    for index, column in ipairs(columns) do
        if column.index == focusedColumnIndex then
            local first = math.max(
                1, math.min(index - math.floor(visible / 2), #columns - visible + 1))
            return first, first + visible - 1
        end
    end
    return nil, nil
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

local function addWorkspace(workspaceIds, windowTopology)
    if windowTopology and windowTopology.workspaceId then
        workspaceIds[windowTopology.workspaceId] = true
    end
end

function logic.activeWorkspaceIds(workspaces, affected)
    local active = {}
    for _, workspace in ipairs(workspaces) do
        local id = tonumber(workspace.id)
        if id and workspace.is_active and (affected == nil or affected[id]) then
            active[id] = tonumber(workspace.active_window_id) or true
        end
    end
    return active
end

function logic.groupColumns(windows, workspaceIds)
    local byWorkspace = {}
    local focusedColumns = {}
    local activeColumns = {}
    local activeWindowIds = {}
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

        if not window.is_floating and workspaceId and windowId and columnIndex
                and (workspaceIds == nil or workspaceIds[workspaceId]) then
            byWorkspace[workspaceId] = byWorkspace[workspaceId] or {}
            byWorkspace[workspaceId][columnIndex] = byWorkspace[workspaceId][columnIndex] or windowId
            if window.is_focused then
                focusedColumns[workspaceId] = columnIndex
            end
            local activeId = workspaceIds and workspaceIds[workspaceId]
            if type(activeId) == "number" and activeId == windowId then
                activeColumns[workspaceId] = columnIndex
                activeWindowIds[workspaceId] = windowId
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
            focusedColumnIndex = focusedColumns[workspaceId] or activeColumns[workspaceId],
            activeWindowId = activeWindowIds[workspaceId],
        })
    end
    table.sort(workspaces, function(a, b) return a.id < b.id end)

    return workspaces, focusedId
end

function logic.shouldRedistribute(event, knownIds)
    local closed = type(event) == "table" and event.WindowClosed or nil
    if type(closed) == "table" and tonumber(closed.id) then
        local id = tonumber(closed.id)
        local affected = {}
        addWorkspace(affected, knownIds[id])
        knownIds[id] = nil
        return next(affected) ~= nil, true, affected
    end

    local changed = type(event) == "table" and event.WindowOpenedOrChanged or nil
    local window = type(changed) == "table" and changed.window or nil
    local previous = type(window) == "table" and knownIds[tonumber(window.id)] or nil
    local id, nextTopology = topology(window, previous)
    if id then
        local opened = knownIds[id] == nil
        local different = not sameTopology(knownIds[id], nextTopology)
        local affected = {}
        if different then
            addWorkspace(affected, previous)
            addWorkspace(affected, nextTopology)
        end
        knownIds[id] = nextTopology
        return different, opened, affected
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
        local openedOrClosed = false
        local affected = {}
        for itemId, itemTopology in pairs(nextIds) do
            openedOrClosed = openedOrClosed or knownIds[itemId] == nil
            if not sameTopology(knownIds[itemId], itemTopology) then
                different = true
                addWorkspace(affected, knownIds[itemId])
                addWorkspace(affected, itemTopology)
            end
        end
        for itemId in pairs(knownIds) do
            openedOrClosed = openedOrClosed or nextIds[itemId] == nil
            if not nextIds[itemId] then
                different = true
                addWorkspace(affected, knownIds[itemId])
            end
            knownIds[itemId] = nil
        end
        for itemId, itemTopology in pairs(nextIds) do
            knownIds[itemId] = itemTopology
        end
        return different, openedOrClosed, affected
    end

    local layoutsChanged = type(event) == "table" and event.WindowLayoutsChanged or nil
    local changes = type(layoutsChanged) == "table" and layoutsChanged.changes or nil
    if type(changes) == "table" then
        local different = false
        local affected = {}
        for _, change in ipairs(changes) do
            local id = type(change) == "table" and tonumber(change[1]) or nil
            local current = id and knownIds[id] or nil
            local layout = type(change) == "table" and change[2] or nil
            local position = type(layout) == "table" and layout.pos_in_scrolling_layout or nil
            local columnIndex = type(position) == "table" and tonumber(position[1]) or nil
            if current and current.columnIndex ~= columnIndex then
                current.columnIndex = columnIndex
                different = true
                addWorkspace(affected, current)
            end
        end
        return different, false, affected
    end

    return false
end

local function action(command)
    return "(niri msg action " .. command .. " >/dev/null 2>&1)"
end

function logic.buildCommand(windows, workspaceIds, division)
    local workspaces, focusedId = logic.groupColumns(windows, workspaceIds)
    local restoreId = focusedId
    if not restoreId and #workspaces == 1 then
        restoreId = workspaces[1].activeWindowId
    end
    if not restoreId then
        return ""
    end

    local commands = {}
    for _, workspace in ipairs(workspaces) do
        local first, last = logic.visibleRange(
            workspace.columns, division, workspace.focusedColumnIndex)
        if first then
            for index, width in ipairs(logic.widths(#workspace.columns, division)) do
                local column = workspace.columns[index]
                table.insert(commands, action("focus-window --id " .. column.windowId)
                    .. " && " .. action("set-column-width " .. width .. "%"))
            end

            table.insert(commands, action("focus-window --id "
                .. workspace.columns[first].windowId))
            table.insert(commands, action("focus-window --id "
                .. workspace.columns[last].windowId))
            table.insert(commands, action("center-visible-columns"))
        end
    end

    if #commands > 0 then
        table.insert(commands, action("focus-window --id " .. restoreId))
    end
    return table.concat(commands, "; ")
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
local pendingWorkspaceIds = {}
local verificationWorkspaceIds = {}

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
        local shouldRedistribute, verify, affected = logic.shouldRedistribute(event, knownIds)
        if shouldRedistribute then
            for workspaceId in pairs(affected) do
                pendingWorkspaceIds[workspaceId] = true
                if verify then
                    verificationWorkspaceIds[workspaceId] = true
                end
            end
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

    local affected = next(pendingWorkspaceIds) and pendingWorkspaceIds or nil
    pendingWorkspaceIds = {}
    if affected then
        for workspaceId in pairs(affected) do
            if verificationWorkspaceIds[workspaceId] then
                pendingWorkspaceIds[workspaceId] = true
                verificationWorkspaceIds[workspaceId] = nil
                rerun = true
            end
        end
    end

    if not noctalia.runAsync("niri msg -j workspaces", function(workspaceResult)
        local workspaces = workspaceResult.exitCode == 0
            and noctalia.json.decode(workspaceResult.stdout) or nil
        if type(workspaces) ~= "table" then
            noctalia.log("failed to read niri workspaces: "
                .. (workspaceResult.stderr or "unknown error"))
            if initialize then
                startStream()
            end
            finishRedistribution()
            return
        end

        local activeWorkspaceIds = logic.activeWorkspaceIds(workspaces, affected)
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

            local command = logic.buildCommand(windows, activeWorkspaceIds, division)
            if command == "" then
                finishRedistribution()
            elseif not noctalia.runAsync(command, function(layoutResult)
                if layoutResult.exitCode ~= 0 then
                    noctalia.log("niri redistribution failed: "
                        .. (layoutResult.stderr or "unknown error"))
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
    end) then
        noctalia.log("failed to query niri workspaces")
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
