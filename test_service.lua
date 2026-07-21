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
})
assert(#workspaces == 1 and #workspaces[1].columns == 2)
assert(workspaces[1].focusedColumnIndex == 1)

assert(logic.widths(2, 4)[1] == 50)
assert(logic.widths(4, 4)[1] == 25)
local thirds = logic.widths(5, 3)
for first = 1, 3 do
    assert(math.abs(sum(thirds, first, first + 2) - 100) < 0.000001)
end
assert(math.abs(sum(logic.widths(3, 4)) - 100) < 0.000001)

local columns = {
    { index = 0 }, { index = 1 }, { index = 2 }, { index = 3 }, { index = 4 },
}
assert(logic.anchorIndex(columns, 3, 4) == 3)
assert(logic.anchorIndex(columns, 3, 2) == 1)
assert(logic.anchorIndex({ columns[1], columns[2], columns[3] }, 3, 2) == 1)

local known = {}
local redistribute, verify = logic.shouldRedistribute({
    WindowOpenedOrChanged = { window = {
        id = 10, workspace_id = 1, is_floating = false,
        layout = { pos_in_scrolling_layout = { 0, 0 } },
    } },
}, known)
assert(redistribute and verify)
assert(not logic.shouldRedistribute({
    WindowOpenedOrChanged = { window = {
        id = 10, workspace_id = 1, is_floating = false, title = "new title",
        layout = { pos_in_scrolling_layout = { 0, 0 } },
    } },
}, known))
redistribute, verify = logic.shouldRedistribute({
    WindowOpenedOrChanged = { window = {
        id = 10, workspace_id = 2, is_floating = false,
        layout = { pos_in_scrolling_layout = { 0, 0 } },
    } },
}, known)
assert(redistribute and not verify)
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
