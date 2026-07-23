local logic = dofile("niri-auto-tile/service.luau")

local function sum(values, first, last)
    local total = 0
    for index = first or 1, last or #values do
        total = total + values[index]
    end
    return total
end

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
    { id = 7, output = "DP-1", is_active = true },
    { id = 8, output = "DP-1", is_active = false },
    { id = 9, output = "HDMI-A-1", is_active = true },
}, { [7] = true, [8] = true })
assert(active[7] and not active[8] and not active[9])

assert(#logic.widths(2, 4) == 0)
assert(#logic.widths(4, 4) == 0)
local thirds = logic.widths(5, 3)
for first = 1, 3 do
    assert(math.abs(sum(thirds, first, first + 2) - 100) < 0.000001)
end

local columns = {
    { index = 0 }, { index = 1 }, { index = 2 }, { index = 3 }, { index = 4 },
}
local first, last = logic.visibleRange(columns, 3, 4)
assert(first == 3 and last == 5)
first, last = logic.visibleRange(columns, 3, 2)
assert(first == 1 and last == 3)
first, last = logic.visibleRange({ columns[1], columns[2] }, 3, 1)
assert(first == 1 and last == 2)

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
