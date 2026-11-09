local logic = dofile("niri-auto-tile/service.luau")

local function sum(values, first, last)
    local total = 0
    for index = first or 1, last or #values do
        total = total + values[index]
    end
    return total
end

local function windowsFor(workspaceId, firstId, count, focusedId)
    local windows = {}
    for position = 1, count do
        local id = firstId + position - 1
        table.insert(windows, {
            id = id,
            workspace_id = workspaceId,
            is_focused = id == focusedId,
            is_floating = false,
            layout = { pos_in_scrolling_layout = { position - 1, 0 } },
        })
    end
    return windows
end

local function append(target, values)
    for _, value in ipairs(values) do
        table.insert(target, value)
    end
end

local function occurrences(value, needle)
    local count = 0
    local start = 1
    while true do
        local found = value:find(needle, start, true)
        if not found then
            return count
        end
        count = count + 1
        start = found + #needle
    end
end

local function endsWith(value, suffix)
    local actions = value:gsub('; exit "%$status"$', "")
    return actions:sub(-#suffix) == suffix
end

local function focusAction(id)
    return "(niri msg action focus-window --id " .. id .. " >/dev/null) || status=1"
end

local centerAction = "(niri msg action center-visible-columns >/dev/null) || status=1"

assert(logic.normalizeDivision("4") == 4)
assert(logic.normalizeDivision("0") == 4)
assert(logic.normalizeDivision("invalid") == 4)

local workspaces = logic.groupColumns({
    { id = 1, workspace_id = 7, is_floating = false, layout = { pos_in_scrolling_layout = { 0, 0 } } },
    { id = 2, workspace_id = 7, is_floating = false, layout = { pos_in_scrolling_layout = { 0, 1 } } },
    { id = 3, workspace_id = 7, is_focused = true, is_floating = false,
        layout = { pos_in_scrolling_layout = { 1, 0 } } },
    { id = 4, workspace_id = 7, is_floating = true, layout = { pos_in_scrolling_layout = { 2, 0 } } },
    { id = 5, workspace_id = 8, is_floating = false, layout = { pos_in_scrolling_layout = { 0, 0 } } },
}, { [7] = true })
assert(#workspaces == 1 and #workspaces[1].columns == 2)
assert(workspaces[1].focusedColumnIndex == 1)

local active = logic.activeWorkspaceIds({
    { id = 7, output = "DP-1", is_active = true, is_focused = true, active_window_id = "3" },
    { id = 8, output = "DP-1", is_active = false },
    { id = 9, output = "HDMI-A-1", is_active = true },
}, { [7] = true, [8] = true })
assert(active[7] == 3 and not active[8] and not active[9])

active = logic.activeWorkspaceIds({
    { id = 7, is_active = true, is_focused = true, active_window_id = 3 },
    { id = 9, is_active = true, is_focused = false, active_window_id = 5 },
})
assert(active[7] == 3 and not active[9])
active = logic.activeWorkspaceIds({
    { id = 7, is_active = true, is_focused = true, active_window_id = 3 },
    { id = 9, is_active = true, is_focused = false, active_window_id = 5 },
}, { [9] = true })
assert(next(active) == nil)

workspaces = logic.groupColumns({
    { id = 1, workspace_id = 7, is_floating = false,
        layout = { pos_in_scrolling_layout = { 0, 0 } } },
    { id = 2, workspace_id = 7, is_floating = false,
        layout = { pos_in_scrolling_layout = { 1, 0 } } },
    { id = 3, workspace_id = 7, is_floating = false,
        layout = { pos_in_scrolling_layout = { 2, 0 } } },
}, { [7] = 3 })
assert(workspaces[1].focusedColumnIndex == 2 and workspaces[1].activeWindowId == 3)

workspaces = logic.groupColumns({
    { id = 1, workspace_id = 7, is_floating = false,
        layout = { pos_in_scrolling_layout = { 0, 0 } } },
    { id = 2, workspace_id = 7, is_focused = true, is_floating = false,
        layout = { pos_in_scrolling_layout = { 1, 0 } } },
}, { [7] = 1 })
assert(workspaces[1].focusedColumnIndex == 1 and workspaces[1].activeWindowId == 1)

for division = 1, 4 do
    for count = 1, 5 do
        local widths = logic.widths(count, division)
        assert(#widths == count)
        for _, width in ipairs(widths) do
            assert(width == 100 / division)
        end
    end
end
assert(#logic.widths(0, 4) == 0)
local fourColumns = logic.buildCommand(windowsFor(1, 1, 4, 2), { [1] = 2 }, 4)
assert(occurrences(fourColumns, "set-column-width 25") == 4)
local thirds = logic.widths(5, 3)
for first = 1, 3 do
    assert(math.abs(sum(thirds, first, first + 2) - 100) < 0.000001)
end

local columns = {
    { index = 0 }, { index = 1 }, { index = 2 }, { index = 3 },
    { index = 4 }, { index = 5 }, { index = 6 }, { index = 7 },
}
local first, last = logic.visibleRange({ columns[1], columns[2] }, 4, 1)
assert(first == 1 and last == 2)
first, last = logic.visibleRange(columns, 1, 4)
assert(first == 5 and last == 5)
first, last = logic.visibleRange(columns, 3, 3)
assert(first == 3 and last == 5)
first, last = logic.visibleRange(columns, 4, 6)
assert(first == 5 and last == 8)
first, last = logic.visibleRange(columns, 4, 0)
assert(first == 1 and last == 4)
first, last = logic.visibleRange(columns, 4, 7)
assert(first == 5 and last == 8)
first, last = logic.visibleRange(columns, 4, nil)
assert(first == nil and last == nil)

local command = logic.buildCommand(windowsFor(1, 1, 8), { [1] = 7 }, 4)
local suffix = focusAction(5) .. "; " .. focusAction(8)
    .. "; " .. centerAction .. "; " .. focusAction(7)
assert(endsWith(command, suffix))
assert(logic.buildCommand(windowsFor(1, 1, 8), { [1] = 99 }, 4) == "")

local multiple = windowsFor(1, 101, 5, 104)
append(multiple, windowsFor(2, 201, 5))
command = logic.buildCommand(multiple, { [1] = 102, [2] = 202 }, 3)
assert(command:find(
    focusAction(103) .. "; " .. focusAction(105) .. "; " .. centerAction, 1, true))
assert(command:find(
    focusAction(201) .. "; " .. focusAction(203) .. "; " .. centerAction, 1, true))
assert(occurrences(command, centerAction) == 2)
assert(endsWith(command, focusAction(104)))

command = logic.buildCommand(windowsFor(1, 1, 5, 4), nil, 3)
assert(endsWith(command,
    focusAction(3) .. "; " .. focusAction(5)
        .. "; " .. centerAction .. "; " .. focusAction(4)))

multiple = windowsFor(1, 101, 5)
append(multiple, windowsFor(2, 201, 5))
assert(logic.buildCommand(multiple, { [1] = 102, [2] = 202 }, 3) == "")

-- The panel owns keyboard focus; only its focused workspace may be resized.
active = logic.activeWorkspaceIds({
    { id = 1, is_active = true, is_focused = false, active_window_id = 102 },
    { id = 2, is_active = true, is_focused = true, active_window_id = 202 },
})
command = logic.buildCommand(multiple, active, 3)
assert(occurrences(command, "set-column-width") == 5)
assert(occurrences(command, centerAction) == 1)
assert(not command:find("focus-window --id 10", 1, true))
assert(endsWith(command, focusAction(202)))

local known = {}
local redistribute, verify, affected = logic.shouldRedistribute({
    WindowOpenedOrChanged = { window = {
        id = 10, workspace_id = 1, is_floating = false,
        layout = { pos_in_scrolling_layout = { 0, 0 } },
    } },
}, known)
assert(redistribute and verify and affected[1])
assert(not logic.shouldRedistribute({
    WindowOpenedOrChanged = { window = {
        id = 10, workspace_id = 1, is_floating = false, title = "new title",
        layout = { pos_in_scrolling_layout = { 0, 0 } },
    } },
}, known))
redistribute, verify, affected = logic.shouldRedistribute({
    WindowOpenedOrChanged = { window = {
        id = 10, workspace_id = 2, is_floating = false,
        layout = { pos_in_scrolling_layout = { 0, 0 } },
    } },
}, known)
assert(redistribute and not verify and affected[1] and affected[2])
assert(logic.shouldRedistribute({
    WindowLayoutsChanged = { changes = {
        { 10, { pos_in_scrolling_layout = { 1, 0 } } },
    } },
}, known))
assert(not logic.shouldRedistribute({
    WindowLayoutsChanged = { changes = {
        { 10, { pos_in_scrolling_layout = { 1, 0 }, tile_size = { 100, 100 } } },
    } },
}, known))
redistribute, verify = logic.shouldRedistribute({ WindowClosed = { id = 10 } }, known)
assert(redistribute and verify)
redistribute, verify = logic.shouldRedistribute({ WindowsChanged = { windows = {
    { id = 11, workspace_id = 1, is_floating = false,
        layout = { pos_in_scrolling_layout = { 0, 0 } } },
} } }, known)
assert(redistribute and verify)
redistribute, verify = logic.shouldRedistribute({ WindowsChanged = { windows = {} } }, known)
assert(redistribute and verify)

-- Validate every input consistently, including values from shared state.
assert(logic.normalizeDivision(nil) == 4)
for _, value in ipairs({ false, true, {}, "invalid", 0, 5, 1.5, "2.5" }) do
    assert(logic.normalizeDivision(value) == 4)
end
for value = 1, 4 do
    assert(logic.normalizeDivision(value) == value)
    assert(logic.normalizeDivision(tostring(value)) == value)
end

local status
command, status = logic.buildCommand(windowsFor(2, 20, 1, 20), { [1] = 1 }, 4)
assert(command == "" and status == "focus-changed")
local inconsistent = windowsFor(1, 1, 2)
append(inconsistent, windowsFor(2, 20, 1, 20))
command, status = logic.buildCommand(inconsistent, { [1] = 1 }, 4)
assert(command == "" and status == "focus-changed")
command, status = logic.buildCommand(windowsFor(1, 1, 2), { [1] = 99 }, 4)
assert(command == "" and status == "focus-changed")
command, status = logic.buildCommand({}, { [1] = true }, 4)
assert(command == "" and status == "empty")

-- A floating effective focus has the same policy on either side of the visible limit.
for _, count in ipairs({ 1, 4, 5, 8 }) do
    for _, panelFocused in ipairs({ false, true }) do
        local windows = windowsFor(1, 1, count)
        table.insert(windows, { id = 99, workspace_id = 1,
            is_floating = true, is_focused = not panelFocused })
        command, status = logic.buildCommand(windows, { [1] = 99 }, 4)
        assert(command == "" and status == "floating")
        windows[#windows].is_focused = false
        windows[1].is_focused = true
        command, status = logic.buildCommand(windows, { [1] = 99 }, 4)
        assert(status == "ready" and not command:find("--id 99", 1, true))
    end
end

known = {}
local function changed(window)
    return logic.shouldRedistribute({ WindowOpenedOrChanged = { window = window } }, known)
end
redistribute, verify, affected = changed({ id = 99, workspace_id = 1, is_floating = true })
assert(not redistribute and not verify and next(affected) == nil and known[99])
redistribute, verify = changed({ id = 99, workspace_id = 2, is_floating = true })
assert(not redistribute and not verify and known[99].workspaceId == 2)
redistribute, verify = logic.shouldRedistribute({ WindowLayoutsChanged = { changes = {
    { 99, { pos_in_scrolling_layout = { 2, 0 } } },
} } }, known)
assert(not redistribute and not verify)
redistribute, verify = logic.shouldRedistribute({ WindowClosed = { id = 99 } }, known)
assert(not redistribute and not verify and known[99] == nil)
redistribute, verify = logic.shouldRedistribute({ WindowsChanged = { windows = {
    { id = 99, workspace_id = 1, is_floating = true },
} } }, known)
assert(not redistribute and not verify)
redistribute, verify = logic.shouldRedistribute({ WindowsChanged = { windows = {} } }, known)
assert(not redistribute and not verify and next(known) == nil)

-- Missing topology is not evidence of floating; both transition directions affect tiling.
redistribute, verify, affected = changed({ id = 1, workspace_id = 1 })
assert(redistribute and verify and affected[1])
redistribute, verify, affected = changed({ id = 1, workspace_id = 1, is_floating = false,
    layout = { pos_in_scrolling_layout = { 0, 0 } } })
assert(redistribute and not verify and affected[1])
redistribute, verify, affected = changed({ id = 1, workspace_id = 2, is_floating = true })
assert(redistribute and not verify and affected[1] and not affected[2])
redistribute, verify, affected = changed({ id = 1, workspace_id = 3, is_floating = false,
    layout = { pos_in_scrolling_layout = { 1, 0 } } })
assert(redistribute and not verify and not affected[2] and affected[3])
redistribute, verify, affected = logic.shouldRedistribute({ WindowsChanged = { windows = {
    { id = 1, workspace_id = 3, is_floating = true },
} } }, known)
assert(redistribute and not verify and affected[3])

-- Output activation and global focus are distinct; neither changes the input snapshot.
local live = {
    { id = 1, output = "DP-1", is_active = true, is_focused = true, active_window_id = 11 },
    { id = 2, output = "DP-2", is_active = true, is_focused = false },
    { id = 3, output = "DP-2", is_active = false, is_focused = false },
}
local updated = logic.workspaceEvent(live, { WorkspaceActivated = { id = 3, focused = false } })
assert(updated[1].is_focused and updated[1].is_active)
assert(not updated[2].is_active and updated[3].is_active)
assert(live[2].is_active and not live[3].is_active)
updated = logic.workspaceEvent(updated, { WorkspaceActivated = { id = 2, focused = true } })
assert(not updated[1].is_focused and updated[1].is_active)
assert(updated[2].is_focused and updated[2].is_active and not updated[3].is_active)
updated = logic.workspaceEvent(updated, { WorkspaceActiveWindowChanged = {
    workspace_id = 1, active_window_id = 12,
} })
assert(updated[1].active_window_id == 12 and live[1].active_window_id == 11)
updated = logic.workspaceEvent(updated, { WorkspaceActiveWindowChanged = { workspace_id = 1 } })
assert(updated[1].active_window_id == nil)
assert(logic.workspaceEvent(updated, { WindowFocusChanged = { id = 12 } }) == nil)
local moved = { { id = 2, output = "DP-1", name = "code", is_active = true, is_focused = true } }
assert(logic.workspaceEvent(updated, { WorkspacesChanged = { workspaces = moved } }) == moved)

assert(logic.validPreferences({ version = 1, session = "socket", byId = { ["2"] = 2 },
    byName = { code = 3 } }))
for _, invalid in ipairs({ {}, { version = 2, byId = {}, byName = {} },
        { version = 1, byId = { [1] = 2 }, byName = {} },
        { version = 1, byId = {}, byName = { code = "2" } },
        { version = 1, byId = {}, byName = { code = 5 } } }) do
    assert(not logic.validPreferences(invalid))
end

print("service logic ok")
