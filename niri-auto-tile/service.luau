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
    if windowTopology and windowTopology.floating ~= true and windowTopology.workspaceId then
        workspaceIds[windowTopology.workspaceId] = true
    end
end

function logic.activeWorkspaceIds(workspaces, affected)
    local active = {}
    for _, workspace in ipairs(workspaces) do
        local id = tonumber(workspace.id)
        if id and workspace.is_focused and (affected == nil or affected[id]) then
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
        return next(affected) ~= nil, next(affected) ~= nil, affected
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
        return next(affected) ~= nil, opened and next(affected) ~= nil, affected
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

        local openedOrClosed = false
        local affected = {}
        for itemId, itemTopology in pairs(nextIds) do
            openedOrClosed = openedOrClosed
                or (knownIds[itemId] == nil and itemTopology.floating ~= true)
            if not sameTopology(knownIds[itemId], itemTopology) then
                addWorkspace(affected, knownIds[itemId])
                addWorkspace(affected, itemTopology)
            end
        end
        for itemId in pairs(knownIds) do
            openedOrClosed = openedOrClosed
                or (nextIds[itemId] == nil and knownIds[itemId].floating ~= true)
            if not nextIds[itemId] then
                addWorkspace(affected, knownIds[itemId])
            end
            knownIds[itemId] = nil
        end
        for itemId, itemTopology in pairs(nextIds) do
            knownIds[itemId] = itemTopology
        end
        return next(affected) ~= nil, openedOrClosed and next(affected) ~= nil, affected
    end

    local layoutsChanged = type(event) == "table" and event.WindowLayoutsChanged or nil
    local changes = type(layoutsChanged) == "table" and layoutsChanged.changes or nil
    if type(changes) == "table" then
        local affected = {}
        for _, change in ipairs(changes) do
            local id = type(change) == "table" and tonumber(change[1]) or nil
            local current = id and knownIds[id] or nil
            local layout = type(change) == "table" and change[2] or nil
            local position = type(layout) == "table" and layout.pos_in_scrolling_layout or nil
            local columnIndex = type(position) == "table" and tonumber(position[1]) or nil
            if current and current.columnIndex ~= columnIndex then
                current.columnIndex = columnIndex
                addWorkspace(affected, current)
            end
        end
        return next(affected) ~= nil, false, affected
    end

    return false
end

local function action(command)
    return "(niri msg action " .. command .. " >/dev/null)"
end

function logic.buildCommand(windows, workspaceIds, division)
    local focusedWindow = nil
    local targetCount = 0
    for _, window in ipairs(windows) do
        if window.is_focused then
            focusedWindow = window
        end
        if workspaceIds == nil or workspaceIds[tonumber(window.workspace_id)] then
            targetCount = targetCount + 1
        end
    end
    if focusedWindow and workspaceIds
            and not workspaceIds[tonumber(focusedWindow.workspace_id)] then
        return "", "focus-changed"
    end
    if targetCount == 0 then
        return "", "empty"
    end
    if not focusedWindow and workspaceIds then
        local workspaceId, activeId = next(workspaceIds)
        if workspaceId and next(workspaceIds, workspaceId) == nil then
            for _, window in ipairs(windows) do
                if tonumber(window.id) == activeId
                        and tonumber(window.workspace_id) == workspaceId then
                    focusedWindow = window
                    break
                end
            end
        end
    end
    if not focusedWindow then
        return "", "focus-changed"
    end
    if focusedWindow.is_floating then
        return "", "floating"
    end

    local workspaces = logic.groupColumns(windows, workspaceIds)
    local restoreId = tonumber(focusedWindow.id)
    if not restoreId then
        return "", "focus-changed"
    end

    local commands = {}
    for _, workspace in ipairs(workspaces) do
        local first, last = logic.visibleRange(
            workspace.columns, division, workspace.focusedColumnIndex)
        if first then
            for index, width in ipairs(logic.widths(#workspace.columns, division)) do
                local column = workspace.columns[index]
                table.insert(commands, action("focus-window --id " .. column.windowId)
                    .. " && " .. action("set-column-width " .. width .. "%") .. " || status=1")
            end

            table.insert(commands, action("focus-window --id "
                .. workspace.columns[first].windowId) .. " || status=1")
            table.insert(commands, action("focus-window --id "
                .. workspace.columns[last].windowId) .. " || status=1")
            table.insert(commands, action("center-visible-columns") .. " || status=1")
        end
    end

    if #commands == 0 then
        return "", "empty"
    end
    table.insert(commands, action("focus-window --id " .. restoreId) .. " || status=1")
    return "status=0; " .. table.concat(commands, "; ") .. '; exit "$status"', "ready"
end

local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do
        result[key] = value
    end
    return result
end

function logic.workspaceEvent(workspaces, event)
    if event.WorkspacesChanged then
        return event.WorkspacesChanged.workspaces
    end
    local activated = event.WorkspaceActivated
    local changed = event.WorkspaceActiveWindowChanged
    if not activated and not changed then
        return nil
    end
    local output
    for _, workspace in ipairs(workspaces) do
        if activated and workspace.id == activated.id then
            output = workspace.output
        end
    end
    local result = {}
    for _, workspace in ipairs(workspaces) do
        local row = copy(workspace)
        if activated then
            if row.id == activated.id then
                row.is_active = true
            elseif output and row.output == output then
                row.is_active = false
            end
            if activated.focused then
                row.is_focused = row.id == activated.id
            end
        elseif row.id == changed.workspace_id then
            row.active_window_id = changed.active_window_id
        end
        table.insert(result, row)
    end
    return result
end

function logic.validPreferences(value)
    if type(value) ~= "table" or value.version ~= 1
            or type(value.byId) ~= "table" or type(value.byName) ~= "table" then
        return false
    end
    for _, values in ipairs({ value.byId, value.byName }) do
        for key, division in pairs(values) do
            if type(key) ~= "string" or key == "" or type(division) ~= "number"
                    or division ~= logic.normalizeDivision(division) then
                return false
            end
        end
    end
    return true
end

if noctalia == nil then
    return logic
end

local function decode(value)
    local ok, result = pcall(noctalia.json.decode, value)
    return ok and result or nil
end

local dataDir = noctalia.pluginDataDir()
local preferencesPath = dataDir and dataDir .. "/workspace-divisions.json"
local defaultDivision = logic.normalizeDivision(dataDir and noctalia.readFile(dataDir .. "/division"))
local session = noctalia.getenv("NIRI_SOCKET")
if type(session) ~= "string" or session == "" then session = nil end
local rawPreferences = preferencesPath and noctalia.readFile(preferencesPath)
local preferences = rawPreferences and decode(rawPreferences)
local trustedPreferences = logic.validPreferences(preferences)
local malformedPreferences = rawPreferences ~= nil and not trustedPreferences
if malformedPreferences then noctalia.log("invalid workspace-divisions.json; using defaults") end
if not logic.validPreferences(preferences) then
    preferences = { version = 1, byId = {}, byName = {} }
end
local divisions = {}
if session and preferences.session == session then
    divisions = copy(preferences.byId)
end
for key, value in pairs(noctalia.state.get("workspaceDivisions") or {}) do
    divisions[key] = logic.normalizeDivision(value)
end
preferences.session = session or ""
preferences.byId = divisions
noctalia.state.set("defaultDivision", defaultDivision)
for key, value in pairs({ paused = false, streamError = false, workspaces = {},
        saveErrors = {}, layoutStatuses = {}, layoutErrors = {} }) do
    if noctalia.state.get(key) == nil then noctalia.state.set(key, value) end
end
local workspaces = noctalia.state.get("workspaces")
local workspaceRevision = 0
local paused = noctalia.state.get("paused") == true
local previousRequest = noctalia.state.get("workspaceRequest")
local requestSerial = type(previousRequest) == "table" and previousRequest.serial or 0
local knownIds = {}
local busy = false
local generation = 0
local manualSerial = 0
local pendingManual = nil
local pendingWorkspaceIds = {}
local verificationWorkspaceIds = {}
local retryPass = nil
local verificationPass = nil
local debounceTicks = nil
local streamStarted = false
local streamRetryTicks = nil
local streamRetryDelay = 20
local workspaceSerials = {}

local function setEntry(key, workspaceId, value)
    if not workspaceId then return end
    local values = copy(noctalia.state.get(key))
    values[tostring(workspaceId)] = value
    noctalia.state.set(key, values)
end

-- A reloaded service cannot confirm an unfinished batch from the previous runtime.
for key, status in pairs(noctalia.state.get("layoutStatuses")) do
    if status == "pending" or status == "applying" then
        setEntry("layoutStatuses", key, "idle")
    end
end

local function savePreferences(workspaceIds)
    for _, workspace in ipairs(workspaces) do
        if type(workspace.name) == "string" and workspace.name ~= "" then
            preferences.byName[workspace.name] = divisions[tostring(workspace.id)]
        end
    end
    local saveDir = noctalia.pluginDataDir()
    local savePath = saveDir and saveDir .. "/workspace-divisions.json"
    local encodedOk, encoded = pcall(noctalia.json.encode, preferences)
    local ok, err = false, "data directory or JSON encoding unavailable"
    if savePath and encodedOk and type(encoded) == "string" then
        ok, err = noctalia.writeFile(savePath, encoded)
    end
    if ok then
        trustedPreferences = true
        malformedPreferences = false
        local errors = {}
        for id in pairs(divisions) do errors[id] = false end
        noctalia.state.set("saveErrors", errors)
    else
        for workspaceId in pairs(workspaceIds) do
            setEntry("saveErrors", workspaceId, true)
        end
    end
    if not ok then noctalia.log("failed to save workspace division: " .. tostring(err)) end
end

local function publishWorkspaces(rows)
    local previous = {}
    for _, workspace in ipairs(workspaces) do previous[workspace.id] = workspace end
    local renamed = {}
    workspaces = rows
    for _, workspace in ipairs(rows) do
        local key = tostring(workspace.id)
        if divisions[key] == nil then
            divisions[key] = preferences.byName[workspace.name] or defaultDivision
        end
        local old = previous[workspace.id]
        if old and old.name ~= workspace.name
                and type(workspace.name) == "string" and workspace.name ~= "" then
            renamed[workspace.id] = true
        end
        if malformedPreferences then setEntry("saveErrors", workspace.id, true) end
    end
    noctalia.state.set("workspaceDivisions", copy(divisions))
    noctalia.state.set("workspaces", rows)
    if next(renamed) then
        if trustedPreferences then
            savePreferences(renamed)
        else
            -- A failed read cannot distinguish a missing file from unread existing preferences.
            for workspaceId in pairs(renamed) do setEntry("saveErrors", workspaceId, true) end
        end
    end
end
publishWorkspaces(workspaces)

local function requestManual(workspaceId)
    if not paused then
        if pendingManual then
            setEntry("layoutStatuses", pendingManual.workspaceId, "idle")
        end
        if retryPass then
            setEntry("layoutStatuses", retryPass.workspaceId, "idle")
            retryPass = nil
        end
        manualSerial = manualSerial + 1
        pendingManual = { workspaceId = workspaceId, serial = manualSerial,
            generation = generation, retries = 0 }
        if workspaceId then workspaceSerials[tostring(workspaceId)] = manualSerial end
        debounceTicks = 0
        setEntry("layoutStatuses", workspaceId, "pending")
    end
end

local function validRows(rows)
    if type(rows) ~= "table" then
        return nil
    end
    for key, row in pairs(rows) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #rows
                or type(row) ~= "table" or tonumber(row.id) == nil then
            return nil
        end
    end
    return rows
end

local function snapshot(result)
    if result.exitCode ~= 0 or result.timedOut or result.stdoutTruncated then
        return nil
    end
    return validRows(decode(result.stdout))
end

local function validEvent(event)
    if type(event) ~= "table" then return false end
    return (type(event.WindowsChanged) == "table"
            and validRows(event.WindowsChanged.windows) ~= nil)
        or (type(event.WindowOpenedOrChanged) == "table"
            and type(event.WindowOpenedOrChanged.window) == "table"
            and tonumber(event.WindowOpenedOrChanged.window.id) ~= nil)
        or (type(event.WindowClosed) == "table" and tonumber(event.WindowClosed.id) ~= nil)
        or (type(event.WindowLayoutsChanged) == "table"
            and type(event.WindowLayoutsChanged.changes) == "table")
        or (type(event.WorkspacesChanged) == "table"
            and validRows(event.WorkspacesChanged.workspaces) ~= nil)
        or (type(event.WorkspaceActivated) == "table"
            and tonumber(event.WorkspaceActivated.id) ~= nil
            and type(event.WorkspaceActivated.focused) == "boolean")
        or (type(event.WorkspaceActiveWindowChanged) == "table"
            and tonumber(event.WorkspaceActiveWindowChanged.workspace_id) ~= nil)
        or type(event.WindowFocusChanged) == "table"
end

local function startStream()
    if streamStarted then return end
    streamStarted = noctalia.runStream("niri msg -j event-stream", function(line)
        local event = decode(line)
        if not validEvent(event) then return end
        if noctalia.state.get("streamError") ~= false then
            noctalia.state.set("streamError", false)
        end
        streamRetryDelay = 20
        local rows = logic.workspaceEvent(workspaces, event)
        if rows then
            workspaceRevision = workspaceRevision + 1
            publishWorkspaces(rows)
        end
        -- Only stream events own this cache; older query results cannot overwrite it.
        local changed, verify, affected = logic.shouldRedistribute(event, knownIds)
        if changed and not paused then
            for workspaceId in pairs(affected) do
                pendingWorkspaceIds[workspaceId] = true
                if verify then verificationWorkspaceIds[workspaceId] = true end
            end
            if not pendingManual then debounceTicks = 3 end
        end
    end)
    if streamStarted then
        streamRetryTicks = nil
    else
        noctalia.log("failed to start niri event stream")
        noctalia.state.set("streamError", true)
        streamRetryTicks = streamRetryDelay
        streamRetryDelay = math.min(streamRetryDelay * 2, 200)
    end
end

local function current(pass)
    return not paused and pass.generation == generation and pass.serial == manualSerial
end

local function finishRedistribution(pass, status, verify)
    busy = false
    local key = pass.workspaceId and tostring(pass.workspaceId)
    local latest = key and workspaceSerials[key] == pass.serial
    if status == "error" and (latest or pass.division ~= nil) then
        setEntry("layoutErrors", pass.workspaceId, true)
    elseif status == "applied" and latest and not paused and pass.generation == generation
            and pass.division == divisions[key] then
        setEntry("layoutErrors", pass.workspaceId, false)
    end
    if latest and status and not paused and pass.generation == generation then
        setEntry("layoutStatuses", pass.workspaceId, status)
    end
    if current(pass) and verify and pass.verify and next(pass.verify) then
        -- shortcut: repeat framing until IPC geometry proves the viewport; upgrade when available.
        verificationPass = { affected = pass.verify, generation = generation,
            serial = pass.serial, retries = pass.retries }
    end
    if not paused and (pendingManual or retryPass or verificationPass
            or next(pendingWorkspaceIds)) then
        debounceTicks = debounceTicks or 0
    end
end

local function fail(pass, message, result)
    local detail = result and (result.timedOut and "timed out"
        or result.stdoutTruncated and "truncated response" or result.stderr) or nil
    noctalia.log(message .. (detail and ": " .. detail or ""))
    finishRedistribution(pass, "error")
end

local function redistribute(pass)
    busy = true
    local queryRevision = workspaceRevision
    if not noctalia.runAsync("niri msg -j workspaces", function(workspaceResult)
        local rows = snapshot(workspaceResult)
        if rows and queryRevision == workspaceRevision then publishWorkspaces(rows) end
        if not current(pass) then
            finishRedistribution(pass, "idle")
            return
        end
        if not rows then
            fail(pass, "failed to read niri workspaces", workspaceResult)
            return
        end
        local affected = pass.workspaceId and { [pass.workspaceId] = true } or pass.affected
        local activeWorkspaceIds = logic.activeWorkspaceIds(workspaces, affected)
        if next(activeWorkspaceIds) == nil then
            finishRedistribution(pass, pass.workspaceId and "focus-changed"
                or pass.retries > 0 and "focus-changed" or pass.affected == nil and "empty" or nil)
            return
        end
        pass.workspaceId = next(activeWorkspaceIds)
        workspaceSerials[tostring(pass.workspaceId)] = pass.serial
        if not noctalia.runAsync("niri msg -j windows", function(result)
            if not current(pass) then
                finishRedistribution(pass, "idle")
                return
            end
            local windows = snapshot(result)
            if not windows then
                fail(pass, "failed to read niri windows", result)
                return
            end
            -- Recheck live focus after the asynchronous windows query.
            activeWorkspaceIds = logic.activeWorkspaceIds(workspaces, { [pass.workspaceId] = true })
            local division = divisions[tostring(pass.workspaceId)] or defaultDivision
            local command, status
            if next(activeWorkspaceIds) == nil then
                command, status = "", "focus-changed"
            else
                command, status = logic.buildCommand(windows, activeWorkspaceIds, division)
            end
            if status == "focus-changed" and pass.retries == 0 and not pendingManual then
                pass.retries = 1
                retryPass = pass
                finishRedistribution(pass)
            elseif command == "" then
                finishRedistribution(pass, status)
            else
                pass.division = division
                setEntry("layoutStatuses", pass.workspaceId, "applying")
                if not noctalia.runAsync(command, function(layoutResult)
                    local failed = layoutResult.exitCode ~= 0 or layoutResult.timedOut
                        or layoutResult.stdoutTruncated
                    if failed then
                        noctalia.log("niri redistribution failed: "
                            .. (layoutResult.timedOut and "timed out; focus restoration unconfirmed"
                                or layoutResult.stderr or "unknown error"))
                    end
                    finishRedistribution(pass, failed and "error" or "applied", true)
                end) then
                    fail(pass, "failed to start niri redistribution")
                end
            end
        end) then fail(pass, "failed to query niri windows") end
    end) then fail(pass, "failed to query niri workspaces") end
end

noctalia.state.watch("workspaceRequest", function(request)
    if type(request) ~= "table" or type(request.serial) ~= "number"
            or request.serial % 1 ~= 0 or request.serial <= (tonumber(requestSerial) or 0) then
        return
    end
    requestSerial = request.serial
    local workspaceId = tonumber(request.workspaceId)
    local target
    for _, workspace in ipairs(workspaces) do
        if workspace.id == workspaceId then target = workspace; break end
    end
    if not target then return end
    local key = tostring(workspaceId)
    if request.division ~= nil then
        local division = logic.normalizeDivision(request.division)
        local changed = divisions[key] ~= division
        divisions[key] = division
        noctalia.state.set("workspaceDivisions", copy(divisions))
        savePreferences({ [workspaceId] = true })
        if changed then requestManual(workspaceId) end
    else
        requestManual(workspaceId)
    end
end)

noctalia.state.watch("paused", function(value)
    local nextPaused = value == true
    if nextPaused == paused then return end
    paused = nextPaused
    if paused then
        generation = generation + 1
        pendingManual = nil
        pendingWorkspaceIds = {}
        verificationWorkspaceIds = {}
        retryPass = nil
        verificationPass = nil
        debounceTicks = nil
        for key, status in pairs(noctalia.state.get("layoutStatuses")) do
            if status == "pending" or status == "applying" then
                setEntry("layoutStatuses", key, "idle")
            end
        end
    else
        requestManual()
    end
end)

noctalia.setUpdateInterval(50)

function update()
    if streamRetryTicks ~= nil then
        streamRetryTicks = streamRetryTicks - 1
        if streamRetryTicks <= 0 then startStream() end
    end
    if paused or busy or debounceTicks == nil then return end
    if debounceTicks > 0 then
        debounceTicks = debounceTicks - 1
        return
    end
    debounceTicks = nil
    local pass
    if pendingManual then
        pass = pendingManual
        pendingManual = nil
        retryPass = nil
        verificationPass = nil
    elseif retryPass then
        pass = retryPass
        retryPass = nil
    elseif next(pendingWorkspaceIds) then
        pass = { affected = pendingWorkspaceIds, verify = verificationWorkspaceIds,
            serial = manualSerial, retries = 0, generation = generation }
        pendingWorkspaceIds = {}
        verificationWorkspaceIds = {}
    elseif verificationPass then
        pass = verificationPass
        verificationPass = nil
    end
    if pass then redistribute(pass) end
end

requestManual()
update()
startStream()
