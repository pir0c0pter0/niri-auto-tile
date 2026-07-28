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
    return value:sub(-#suffix) == suffix
end

local function focusAction(id)
    return "(niri msg action focus-window --id " .. id .. " >/dev/null 2>&1)"
end

local centerAction = "(niri msg action center-visible-columns >/dev/null 2>&1)"

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
    { id = 7, output = "DP-1", is_active = true, active_window_id = "3" },
    { id = 8, output = "DP-1", is_active = false },
    { id = 9, output = "HDMI-A-1", is_active = true },
}, { [7] = true, [8] = true })
assert(active[7] == 3 and not active[8] and not active[9])

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

assert(#logic.widths(2, 4) == 0)
assert(#logic.widths(4, 4) == 0)
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

print("service logic ok")
