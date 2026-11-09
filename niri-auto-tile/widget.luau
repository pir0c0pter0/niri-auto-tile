local function normalize(value)
    local number = tonumber(value)
    if number == nil or number % 1 ~= 0 or number < 1 or number > 4 then
        return 4
    end
    return number
end

local function currentWorkspace()
    local outputName = barWidget.outputName()
    for _, workspace in ipairs(noctalia.state.get("workspaces") or {}) do
        if outputName and workspace.id ~= nil and workspace.output == outputName and workspace.is_active then
            return workspace
        end
    end
end

local function render()
    local workspace = currentWorkspace()
    local id = workspace and tostring(workspace.id)
    local division = normalize((noctalia.state.get("workspaceDivisions") or {})[id]
        or noctalia.state.get("defaultDivision"))
    barWidget.setGlyph("columns-3")
    barWidget.setText(workspace and tostring(division) or "—")
    local tooltip = {
        workspace and noctalia.tr("bar.tooltip", {
            count = division, workspace = workspace.name or tostring(workspace.idx or workspace.id),
        }) or noctalia.tr("panel.noWorkspace"),
        noctalia.tr(noctalia.state.get("paused") == true and "status.paused" or "status.active"),
    }
    if (noctalia.state.get("saveErrors") or {})[id] == true then
        table.insert(tooltip, noctalia.tr("status.saveError"))
    end
    if noctalia.state.get("streamError") == true then
        table.insert(tooltip, noctalia.tr("status.streamError"))
    end
    local status = (noctalia.state.get("layoutStatuses") or {})[id]
    if status == "error" then
        table.insert(tooltip, noctalia.tr("status.error"))
    elseif status == "floating" then
        table.insert(tooltip, noctalia.tr("status.floating"))
    elseif status == "empty" then
        table.insert(tooltip, noctalia.tr("status.empty"))
    elseif status == "focus-changed" then
        table.insert(tooltip, noctalia.tr("status.focusChanged"))
    end
    if (noctalia.state.get("layoutErrors") or {})[id] == true and status ~= "error" then
        table.insert(tooltip, noctalia.tr("status.error"))
    end
    barWidget.setTooltip(table.concat(tooltip, "\n"))
end

for _, key in ipairs({
    "workspaces", "workspaceDivisions", "defaultDivision", "paused", "saveErrors",
    "streamError", "layoutStatuses", "layoutErrors",
}) do
    noctalia.state.watch(key, render)
end

function update()
    render()
end

function onClick()
    local outputName = barWidget.outputName()
    if not outputName then
        noctalia.togglePanel("pir0c0pter0/niri-auto-tile:panel")
        return
    end
    -- togglePanel ignores context; IPC forwards the output to onOpen.
    local command = "noctalia msg panel-toggle pir0c0pter0/niri-auto-tile:panel '"
        .. outputName:gsub("'", "'\\''") .. "'"
    if not noctalia.runAsync(command, function(result)
        if result.exitCode ~= 0 or result.timedOut then
            noctalia.log("failed to open workspace panel: " .. (result.stderr or "unknown error"))
        end
    end) then
        noctalia.log("failed to start workspace panel request")
    end
end
