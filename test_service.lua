local logic = dofile("service.luau")

assert(logic.normalizeDivision("4") == 4)
assert(logic.normalizeDivision("0") == 4)
assert(logic.normalizeDivision("invalid") == 4)

local workspaces = logic.groupColumns({
    { id = 1, workspace_id = 7, is_floating = false, layout = { pos_in_scrolling_layout = { 0, 0 } } },
    { id = 2, workspace_id = 7, is_floating = false, layout = { pos_in_scrolling_layout = { 0, 1 } } },
    { id = 3, workspace_id = 7, is_floating = false, layout = { pos_in_scrolling_layout = { 1, 0 } } },
    { id = 4, workspace_id = 7, is_floating = true, layout = { pos_in_scrolling_layout = { 2, 0 } } },
})
assert(#workspaces == 1 and #workspaces[1].columns == 2)

assert(table.concat(logic.widths(2, 4), ",") == "50,50")
assert(table.concat(logic.widths(4, 4), ",") == "25,25,25,25")
assert(table.concat(logic.widths(5, 3), ",") == "33,33,33,33,34")

local known = { [10] = true }
assert(not logic.shouldRedistribute({
    WindowOpenedOrChanged = { window = { id = 10, title = "new title" } },
}, known))
assert(logic.shouldRedistribute({
    WindowOpenedOrChanged = { window = { id = 11 } },
}, known))
assert(logic.shouldRedistribute({ WindowClosed = { id = 11 } }, known))

print("service logic ok")
