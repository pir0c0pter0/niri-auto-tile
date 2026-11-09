local outputName

local function normalize(value)
    local number = tonumber(value)
    if number == nil or number % 1 ~= 0 or number < 1 or number > 4 then
        return 4
    end
    return number
end

local function currentWorkspace()
    for _, workspace in ipairs(noctalia.state.get("workspaces") or {}) do
        if workspace.id ~= nil and ((outputName and workspace.output == outputName and workspace.is_active)
            or (not outputName and workspace.is_focused)) then
            return workspace
        end
    end
end

local function labelFor(value)
    if value == 1 then
        return noctalia.tr("panel.single")
    end
    return noctalia.tr("panel.columns", { count = value })
end

local function render()
    local workspace = currentWorkspace()
    local id = workspace and tostring(workspace.id)
    local division = normalize((noctalia.state.get("workspaceDivisions") or {})[id]
        or noctalia.state.get("defaultDivision"))
    local paused = noctalia.state.get("paused") == true
    local buttons = {}
    for value = 1, 4 do
        table.insert(buttons, ui.button({
            key = "division-" .. value,
            text = tostring(value),
            tooltip = labelFor(value),
            selected = workspace ~= nil and value == division,
            variant = workspace and value == division and "primary" or "default",
            enabled = workspace ~= nil,
            controlSize = "lg",
            flexGrow = 1,
            onClick = "select" .. value,
        }))
    end

    local status = (noctalia.state.get("layoutStatuses") or {})[id] or "idle"
    local statusKeys = {
        idle = "status.idle", pending = "status.pending", applying = "status.applying",
        applied = "status.applied", error = "status.error", floating = "status.floating",
        empty = "status.empty", ["focus-changed"] = "status.focusChanged",
    }
    local details = {
        ui.label({
            key = "workspace", maxWidth = 360,
            text = workspace and noctalia.tr("panel.workspace", {
                workspace = workspace.name or tostring(workspace.idx or workspace.id),
            }) or noctalia.tr("panel.noWorkspace"),
        }),
        ui.label({
            key = "preference", maxWidth = 360,
            text = workspace and noctalia.tr("panel.preference", {
                count = division, percent = division == 3 and "≈33" or tostring(100 / division),
            }) or "",
        }),
        ui.label({ key = "scope", maxWidth = 360, text = noctalia.tr("panel.scope") }),
        ui.label({
            key = "automation", maxWidth = 360,
            text = noctalia.tr(paused and "status.paused" or "status.active"),
        }),
        ui.label({
            key = "layout-status", maxWidth = 360,
            text = noctalia.tr(statusKeys[status] or "status.idle"),
        }),
    }
    if (noctalia.state.get("saveErrors") or {})[id] == true then
        table.insert(details, ui.label({
            key = "save-error", maxWidth = 360, text = noctalia.tr("status.saveError"),
        }))
    end
    if noctalia.state.get("streamError") == true then
        table.insert(details, ui.label({
            key = "stream-error", maxWidth = 360, text = noctalia.tr("status.streamError"),
        }))
    end
    if (noctalia.state.get("layoutErrors") or {})[id] == true and status ~= "error" then
        table.insert(details, ui.label({
            key = "layout-error", maxWidth = 360, text = noctalia.tr("status.error"),
        }))
    end

    panel.render(ui.column({ gap = 14, padding = 20, flexGrow = 1 }, {
        ui.row({ align = "center", justify = "space_between" }, {
            ui.label({
                text = noctalia.tr("panel.title"),
                fontSize = 18,
                fontWeight = "bold",
                color = "primary",
                flexGrow = 1,
            }),
            ui.button({
                key = "close-panel", glyph = "close", text = noctalia.tr("panel.close"),
                tooltip = noctalia.tr("panel.close"), variant = "ghost", onClick = "closePanel",
            }),
        }),
        ui.row({ gap = 10, align = "center" }, buttons),
        ui.row({ gap = 10 }, {
            ui.button({
                key = "reapply", text = noctalia.tr("panel.reapply"), flexGrow = 1,
                enabled = workspace ~= nil and not paused, onClick = "reapplyLayout",
                tooltip = noctalia.tr(not workspace and "panel.noWorkspace"
                    or paused and "panel.reapplyPaused" or "panel.reapplyHint"),
            }),
            ui.button({
                key = "pause", text = noctalia.tr(paused and "panel.resume" or "panel.pause"),
                selected = paused, flexGrow = 1, onClick = "togglePause",
            }),
        }),
        ui.scroll({ key = "details", flexGrow = 1, gap = 10 }, details),
    }))
end

local function request(value)
    local workspace = currentWorkspace()
    if not workspace then
        return
    end
    local previous = noctalia.state.get("workspaceRequest") or {}
    noctalia.state.set("workspaceRequest", {
        serial = (tonumber(previous.serial) or 0) + 1,
        workspaceId = workspace.id,
        division = value,
    })
end

function select1() request(1) end
function select2() request(2) end
function select3() request(3) end
function select4() request(4) end
function closePanel() panel.close() end

function reapplyLayout()
    if noctalia.state.get("paused") == true then
        return
    end
    request()
end

function togglePause()
    noctalia.state.set("paused", noctalia.state.get("paused") ~= true)
end

for _, key in ipairs({
    "workspaces", "workspaceDivisions", "defaultDivision", "paused", "saveErrors",
    "streamError", "layoutStatuses", "layoutErrors",
}) do
    noctalia.state.watch(key, render)
end

function onOpen(context)
    outputName = type(context) == "string" and context ~= "" and context or nil
    render()
end
