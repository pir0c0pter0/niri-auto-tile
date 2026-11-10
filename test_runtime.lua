-- Isolated Noctalia runtime: synchronous state watchers, queued process callbacks.
-- No compositor process or real plugin preference path is used by this harness.
local root = os.getenv("NIRI_TEST_ROOT") or "."
local cases, passed = {}, 0
local function test(name, fn) cases[#cases + 1] = { name, fn } end
local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end
local function windows(ws, first, count, focus, floating)
    local result = {}
    for i = 1, count do
        result[i] = { id = first + i - 1, workspace_id = ws,
            is_focused = first + i - 1 == focus, is_floating = floating == true,
            layout = { pos_in_scrolling_layout = { i - 1, 0 } } }
    end
    return result
end
local function append(a, b) for _, value in ipairs(b) do a[#a + 1] = value end return a end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
-- Tokens model serialized snapshots, shared across simulated runtime restarts.
local tokens, tokenId = {}, 0
local function encode(value)
    tokenId = tokenId + 1
    local token = "json:" .. tokenId
    tokens[token] = copy(value)
    return token
end
local function decode(value) return copy(tokens[value]) end
local function mock(options)
    options = options or {}
    local m = { state = options.state or {}, watchers = {}, queue = {}, commands = {},
        writes = {}, logs = {}, streamCalls = {}, streams = {}, tickCount = 0,
        disk = options.disk, files = copy(options.files or {}), writeOK = true, readOK = true, pendingLayouts = 0, maxLayouts = 0,
        workspaces = { { id = 1, idx = 1, output = "DP-1", is_active = true, is_focused = true, active_window_id = 11 } },
        windows = windows(1, 11, 4, 11), spawnFailures = {}, streamResults = options.streamResults or {} }
    m.encode, m.decode = encode, decode
    function m.set(key, value)
        m.state[key] = value
        for _, watcher in ipairs(m.watchers[key] or {}) do watcher.callback(value) end
    end
    local api = {
        pluginDataDir = function() if not options.noDataDir then return "/mock-only" end end,
        getenv = function(name)
            equal(name, "NIRI_SOCKET")
            return options.session == nil and "/mock/niri.sock" or options.session
        end,
        readFile = function(path)
            assert(path == "/mock-only/division" or path == "/mock-only/workspace-divisions.json")
            if not m.readOK then return nil, "temporary read failure" end
            return path == "/mock-only/division" and m.disk or m.files[path]
        end,
        fileExists = function(path) return m.files[path] ~= nil end,
        writeFile = function(path, value)
            equal(path, "/mock-only/workspace-divisions.json.tmp", "writes use a temporary file")
            m.writes[#m.writes + 1] = { path = path, value = value }
            if m.writeOK then m.files[path] = value; return true end
            if m.partialWrite then m.files[path] = "partial JSON" end
            return false, "read-only test filesystem"
        end,
        renameFile = function(from, to)
            equal(from, "/mock-only/workspace-divisions.json.tmp")
            equal(to, "/mock-only/workspace-divisions.json")
            if m.renameOK == false then return false, "test rename failure" end
            m.files[to], m.files[from] = m.files[from], nil
            return true
        end,
        state = { get = function(key) return m.state[key] end, set = m.set,
            watch = function(key, callback)
                m.watchers[key] = m.watchers[key] or {}
                table.insert(m.watchers[key], { callback = callback, owner = m.loading })
            end },
        json = { decode = decode, encode = encode },
        log = function(message) m.logs[#m.logs + 1] = message end,
        setUpdateInterval = function(value) m.interval = value end,
        tr = function(key, params)
            local text = key
            for name, value in pairs(params or {}) do text = text .. " " .. name .. "=" .. tostring(value) end
            return text
        end,
        togglePanel = function(id, output) m.panelContext = output; m.panelId = id end,
        runStream = function(command, callback)
            equal(command, "niri msg -j event-stream")
            m.streamCalls[#m.streamCalls + 1] = m.tickCount
            local accepted = m.streamResults[#m.streamCalls]
            if accepted == nil then accepted = true end
            if accepted then m.streams[#m.streams + 1] = callback end
            return accepted
        end,
        runAsync = function(command, callback)
            local kind = command == "niri msg -j workspaces" and "workspaces"
                or command == "niri msg -j windows" and "windows"
                or command:find("noctalia msg panel-toggle", 1, true) == 1 and "panel" or "layout"
            m.commands[#m.commands + 1] = { kind = kind, command = command }
            if m.spawnFailures[kind] then m.spawnFailures[kind] = nil; return false end
            if kind == "layout" then
                m.pendingLayouts = m.pendingLayouts + 1
                m.maxLayouts = math.max(m.maxLayouts, m.pendingLayouts)
                assert(m.pendingLayouts <= 1, "concurrent layout batches")
            end
            m.queue[#m.queue + 1] = { kind = kind, callback = callback, command = command }
            return true
        end,
    }
    function m.load(component, context, instance)
        local owner = instance or component
        for _, watchers in pairs(m.watchers) do
            for index = #watchers, 1, -1 do
                if watchers[index].owner == owner then table.remove(watchers, index) end
            end
        end
        m.loading = owner
        local env = setmetatable({ noctalia = api }, { __index = _G })
        env.ui = {}
        for _, kind in ipairs({ "column", "row", "label", "button", "scroll" }) do
            env.ui[kind] = function(props, children) return { kind = kind, props = props, children = children } end
        end
        env.panel = { render = function(tree) env.tree = tree end, close = function() end }
        env.barWidget = { outputName = function() return context or "DP-1" end, setGlyph = function(value) env.glyph = value end,
            setText = function(value) env.text = value end, setTooltip = function(value) env.tooltip = value end }
        assert(loadfile(root .. "/niri-auto-tile/" .. component .. ".luau", "t", env))()
        m[owner] = env
        m.loading = nil
        if component == "panel" then env.onOpen(context) end
        if component == "widget" then env.update() end
        return env
    end
    function m.reply(result)
        local item = assert(table.remove(m.queue, 1), "no queued callback")
        if item.kind == "layout" then m.pendingLayouts = m.pendingLayouts - 1 end
        item.callback(result or { exitCode = 0, stdout = m.encode(m[item.kind]), stderr = "" })
        return item
    end
    function m.tick(count)
        for _ = 1, count or 1 do m.tickCount = m.tickCount + 1; m.service.update() end
    end
    function m.drain()
        for _ = 1, 120 do
            if #m.queue > 0 then m.reply() end
            m.tick()
        end
        equal(#m.queue, 0, "bounded drain")
        local count = #m.commands
        m.tick(40)
        equal(#m.commands, count, "no work after stabilization")
    end
    function m.event(event)
        assert(m.streams[1], "stream not accepted")(m.encode(event))
    end
    function m.layouts()
        local result = {}
        for _, item in ipairs(m.commands) do if item.kind == "layout" then result[#result + 1] = item.command end end
        return result
    end
    function m.count(kind)
        local count = 0
        for _, item in ipairs(m.commands) do if item.kind == kind then count = count + 1 end end
        return count
    end
    function m.request(division, workspaceId)
        local previous = m.state.workspaceRequest or {}
        m.set("workspaceRequest", { serial = (previous.serial or 0) + 1,
            workspaceId = workspaceId or 1, division = division })
    end
    function m.ready()
        m.load("service")
        if m.streams[1] then m.event({ WindowsChanged = { windows = m.windows } }) end
        m.drain(); m.commands = {}; return m
    end
    return m
end
local function find(tree, key)
    if tree.props and tree.props.key == key then return tree.props end
    for _, child in ipairs(tree.children or {}) do local result = find(child, key); if result then return result end end
end
local function click(panel, key)
    local props = assert(find(panel.tree, key), "missing control " .. key)
    assert(props.enabled ~= false, "disabled control " .. key)
    assert(panel[props.onClick], "missing handler " .. tostring(props.onClick))()
end
local function hasWidth(command, width)
    assert(command:find("set-column-width " .. width, 1, true), "missing width " .. width .. ": " .. command)
end

test("two monitor widgets show independent workspace divisions 4 and 2", function()
    local m = mock({ state = { workspaces = {
        { id = 1, output = "DP-1", is_active = true, is_focused = true },
        { id = 2, output = "HDMI-A-1", is_active = true, is_focused = false },
    }, workspaceDivisions = { ["1"] = 4, ["2"] = 2 } } })
    local a = m.load("widget", "DP-1", "widgetA")
    local b = m.load("widget", "HDMI-A-1", "widgetB")
    equal(a.text, "4", "DP-1")
    equal(b.text, "2", "HDMI-A-1")
end)

test("manual intent survives busy unrelated workspace events", function()
    local m = mock():ready()
    m.event({ WindowOpenedOrChanged = { window = windows(2, 21, 1)[1] } })
    m.tick(5)
    assert(#m.queue > 0)
    m.event({ WindowOpenedOrChanged = { window = windows(2, 22, 1)[1] } })
    m.request(2); m.request(3); m.request(1)
    m.drain()
    local layouts = m.layouts(); assert(#layouts > 0, "manual request was lost")
    hasWidth(layouts[#layouts], "100")
    for _, command in ipairs(layouts) do assert(not command:find("--id 2", 1, true), "unfocused workspace changed") end
end)

test("old failed query preserves a newer selection", function()
    local m = mock():ready(); m.request(2); m.tick(5)
    m.request(3)
    m.reply({ exitCode = 1, stderr = "old query failed" }); m.drain()
    hasWidth(assert(m.layouts()[1]), "33.333")
    equal(m.state.layoutStatuses["1"], "applied")
end)

test("older batch never confirms newer preference", function()
    for _, fail in ipairs({ false, true }) do
        local m = mock():ready(); m.request(2); m.tick(5)
        m.reply(); m.reply(); equal(m.queue[1].kind, "layout")
        m.request(4); m.reply()
        assert(m.state.layoutStatuses["1"] ~= "applied", "old batch claims new preference applied")
        m.tick(5); m.reply(); m.reply()
        m.reply({ exitCode = fail and 1 or 0, stderr = fail and "resize failed" or "" })
        m.drain(); equal(m.state.layoutStatuses["1"], fail and "error" or "applied")
        hasWidth(m.layouts()[#m.layouts()], "25")
    end
end)

test("focus mismatch retries once without retargeting manual intent", function()
    local m = mock():ready(); m.request(2); m.tick(5); m.reply()
    m.windows = windows(2, 21, 4, 21)
    m.reply(); equal(#m.layouts(), 0)
    m.workspaces = { { id = 2, is_focused = true, active_window_id = 21 } }
    m.drain(); equal(#m.layouts(), 0, "request for A must not resize B")
    equal(m.state.workspaceDivisions["1"], 2)
    equal(m.state.layoutStatuses["1"], "focus-changed")
    m.commands = {}; m.workspaces = { { id = 1, is_focused = true, active_window_id = 11 } }
    m.event({ WorkspacesChanged = { workspaces = m.workspaces } })
    m.request(3); m.drain(); equal(#m.layouts(), 0); equal(m.count("workspaces"), 2)
    equal(m.state.layoutStatuses["1"], "focus-changed")
end)

test("automatic retry never follows focus outside affected workspace", function()
    local m = mock():ready()
    m.event({ WindowOpenedOrChanged = { window = windows(1, 15, 1)[1] } }); m.tick(5); m.reply()
    m.windows = windows(2, 21, 4, 21); m.reply()
    m.workspaces = { { id = 2, is_focused = true, active_window_id = 21 } }; m.drain()
    equal(#m.layouts(), 0)
    assert(m.count("workspaces") <= 2, "verification renewed focus retry budget")
end)

test("query and spawn failures release busy and permit recovery", function()
    for _, kind in ipairs({ "workspaces", "windows", "layout" }) do
        for _, failure in ipairs({ "spawn", "exit", "timeout", "truncated", "invalid" }) do
            if kind ~= "layout" or (failure ~= "invalid" and failure ~= "truncated") then
                local m = mock():ready()
                if failure == "spawn" then m.spawnFailures[kind] = true end
                m.request(2); m.tick(5)
                if kind ~= "workspaces" then m.reply() end
                if kind == "layout" then m.reply() end
                if failure ~= "spawn" then
                    m.reply({ exitCode = failure == "exit" and 1 or 0,
                        timedOut = failure == "timeout", stdoutTruncated = failure == "truncated",
                        stdout = failure == "invalid" and "invalid-json" or m.encode(m[kind]), stderr = "failure" })
                end
                m.drain(); equal(m.state.layoutStatuses["1"], "error", kind .. "/" .. failure)
                if kind ~= "layout" then equal(#m.layouts(), 0) end
                m.request(3); m.drain(); equal(m.state.layoutStatuses["1"], "applied")
            end
        end
    end
end)

test("stream startup retries with capped backoff and stays independent", function()
    local m = mock({ streamResults = { false, false, false, false, false, false, true } })
    m.load("service")
    for _ = 1, 10 do if #m.queue > 0 then m.reply() end end
    equal(#m.streamCalls, 1); equal(m.state.streamError, true)
    local intervals = { 1000, 2000, 4000, 8000, 10000, 10000 }
    for index, delay in ipairs(intervals) do
        local due = m.streamCalls[index] + delay / m.interval
        m.tick(due - m.tickCount - 1); equal(#m.streamCalls, index)
        m.tick(); equal(#m.streamCalls, index + 1)
    end
    equal(#m.streams, 1); equal(m.state.streamError, true, "accepted process is not proof of communication")
    m.request(2); m.drain(); equal(m.state.layoutStatuses["1"], "applied"); equal(m.state.streamError, true)
    m.event({ WindowsChanged = { windows = m.windows } }); m.drain()
    equal(m.state.streamError, false)
    m.tick(500); equal(#m.streamCalls, 7)
end)

test("stream snapshots own topology despite older query responses", function()
    local m = mock(); m.load("service"); m.reply()
    local fresh = append(windows(1, 11, 4, 11), windows(1, 15, 1))
    m.event({ WindowsChanged = { windows = fresh } })
    m.reply(); m.drain(); m.commands = {}
    m.event({ WindowClosed = { id = 15 } }); m.drain()
    assert(m.count("workspaces") > 0, "stale query erased fresh stream snapshot")
    m.commands = {}; m.event({ WindowsChanged = { windows = m.windows } }); m.drain()
    equal(#m.commands, 0, "unchanged snapshot triggered layout")
end)

test("events during a batch coalesce and own unchanged events stabilize", function()
    local m = mock():ready(); m.request(2); m.tick(5); m.reply(); m.reply()
    equal(m.queue[1].kind, "layout")
    local newWindow = windows(1, 15, 1)[1]
    m.windows[#m.windows + 1] = newWindow
    m.event({ WindowOpenedOrChanged = { window = newWindow } })
    m.request(); m.request(); m.request()
    m.drain(); equal(m.maxLayouts, 1)
    m.commands = {}; m.event({ WindowsChanged = { windows = m.windows } }); m.drain()
    equal(#m.commands, 0)
end)

test("no-target queries preserve execution error until successful batch", function()
    local m = mock():ready(); m.request(2); m.tick(5)
    m.reply({ exitCode = 1, stderr = "IPC failed" }); m.drain()
    equal(m.state.layoutStatuses["1"], "error")
    m.windows = {}; m.workspaces[1].active_window_id = nil
    m.request(); m.drain()
    equal(m.state.layoutStatuses["1"], "empty"); equal(m.state.layoutErrors["1"], true)
    m.windows = windows(1, 11, 4, 11); m.workspaces[1].active_window_id = 11
    m.request(); m.drain(); equal(m.state.layoutStatuses["1"], "applied")
    equal(m.state.layoutErrors["1"], false)
end)

test("floating-only events never schedule queries", function()
    local m = mock():ready(); local floating = windows(1, 50, 1, nil, true)[1]
    m.event({ WindowOpenedOrChanged = { window = floating } }); m.drain(); equal(#m.commands, 0)
    floating.workspace_id = 2
    m.event({ WindowOpenedOrChanged = { window = floating } }); m.drain(); equal(#m.commands, 0)
    m.event({ WindowsChanged = { windows = append(windows(1, 11, 4, 11), { floating }) } })
    m.drain(); equal(#m.commands, 0)
    m.event({ WindowClosed = { id = 50 } }); m.drain(); equal(#m.commands, 0)
end)

test("pause and quick resume invalidate old query generations", function()
    local m = mock():ready(); m.request(2); m.tick(5); m.reply()
    equal(m.queue[1].kind, "windows")
    m.set("paused", true); m.request(3); m.request(1); m.set("paused", false)
    m.reply(); equal(#m.layouts(), 0, "stale query launched layout")
    m.drain(); equal(#m.layouts(), 1); hasWidth(m.layouts()[1], "100")
    m.commands = {}; m.set("paused", true)
    m.event({ WindowOpenedOrChanged = { window = windows(1, 15, 1)[1] } }); m.drain()
    equal(#m.commands, 0)
end)

test("pause allows started batch to finish without resurrecting work", function()
    local m = mock():ready(); m.request(2); m.tick(5); m.reply(); m.reply()
    equal(m.queue[1].kind, "layout"); m.set("paused", true); m.reply(); m.drain()
    equal(#m.layouts(), 1); equal(m.pendingLayouts, 0)
end)

test("floating reason remains visible alongside previous execution error", function()
    local m = mock():ready(); local panel = m.load("panel"); local widget = m.load("widget")
    m.request(2); m.tick(5)
    m.reply({ exitCode = 1, stderr = "IPC failed" }); m.drain()
    m.windows = append(windows(1, 11, 4), windows(1, 99, 1, 99, true))
    m.workspaces[1].active_window_id = 99
    click(panel, "reapply"); m.drain()
    equal(m.state.layoutStatuses["1"], "floating"); equal(m.state.layoutErrors["1"], true)
    equal(find(panel.tree, "layout-status").text, "status.floating")
    equal(find(panel.tree, "layout-error").text, "status.error")
    assert(widget.tooltip:find("status.floating", 1, true), "widget floating reason missing")
    assert(widget.tooltip:find("status.error", 1, true), "widget execution error missing")
    panel = m.load("panel"); widget = m.load("widget")
    equal(find(panel.tree, "layout-error").text, "status.error")
    assert(widget.tooltip:find("status.error", 1, true), "reopened widget lost error")
end)

test("failed in-flight batch remains visible while paused", function()
    local m = mock():ready(); local panel = m.load("panel"); local widget = m.load("widget")
    m.request(2); m.tick(5); m.reply(); m.reply()
    equal(m.queue[1].kind, "layout")
    click(panel, "pause")
    m.reply({ exitCode = 1, stderr = "restore failed" }); m.drain()
    equal(m.state.paused, true); equal(m.state.layoutErrors["1"], true)
    equal(find(panel.tree, "automation").text, "status.paused")
    local warning = find(panel.tree, "layout-error") or find(panel.tree, "layout-status")
    equal(warning.text, "status.error")
    assert(widget.tooltip:find("status.paused", 1, true), "widget pause missing")
    assert(widget.tooltip:find("status.error", 1, true), "widget batch failure missing")
    equal(#m.layouts(), 1)
end)

test("floating target ends intent until explicit reapply", function()
    for _, count in ipairs({ 1, 4, 5, 8 }) do
        for _, panelFocus in ipairs({ false, true }) do
            local m = mock():ready()
            local floating = windows(1, 99, 1, 99, true)
            floating[1].is_focused = not panelFocus
            m.windows = append(windows(1, 11, count), floating)
            m.workspaces[1].active_window_id = 99
            m.request(2); m.drain(); equal(#m.layouts(), 0); equal(m.state.layoutStatuses["1"], "floating")
            m.windows = windows(1, 11, count, 11); m.workspaces[1].active_window_id = 11
            m.tick(20); equal(#m.layouts(), 0)
            m.request(); m.drain(); equal(#m.layouts(), 1)
        end
    end
end)

test("normalization is consistent at startup and watcher updates", function()
    for _, value in ipairs({ "invalid", 0, 5, 1.5, false, "3", 2 }) do
        local expected = (value == "3" and 3) or (value == 2 and 2) or 4
        local m = mock({ disk = tostring(value) }); m.load("service"); m.drain()
        hasWidth(assert(m.layouts()[1]), expected == 3 and "33.333" or tostring(math.floor(100 / expected)))
        local panel = m.load("panel"); local widget = m.load("widget")
        equal(widget.text, tostring(expected)); assert(find(panel.tree, "division-" .. expected).selected)
        equal(#m.writes, 0)
        m.set("workspaceDivisions", { ["1"] = "invalid" })
        equal(widget.text, "4"); assert(find(panel.tree, "division-4").selected)
        equal(#m.writes, 0)
    end
    local fresh = mock():ready()
    equal(fresh.load("widget").text, "4")
    assert(find(fresh.load("panel").tree, "division-4").selected)
    equal(#fresh.writes, 0)
end)

test("panel explains positional persistence only for unnamed workspaces", function()
    local m = mock({ state = { workspaces = {
        { id = 1, idx = 1, output = "DP-1", is_active = true, is_focused = true },
    } } })
    local panel = m.load("panel", "DP-1")
    equal(assert(find(panel.tree, "persistence")).text, "panel.positionPersistence")
    m.state.workspaces[1].name = "coding"
    m.set("workspaces", m.state.workspaces)
    equal(find(panel.tree, "persistence"), nil)
    m.state.workspaces[1].name = ""
    m.set("workspaces", m.state.workspaces)
    assert(find(panel.tree, "persistence"))
    m.set("workspaces", {})
    equal(find(panel.tree, "persistence"), nil)
    equal(#m.writes, 0)
end)

test("failed save survives panel recreation and reselect only retries disk", function()
    local m = mock({ disk = "4" }):ready(); local panel = m.load("panel")
    m.writeOK = false; click(panel, "division-2"); m.drain()
    equal(m.state.workspaceDivisions["1"], 2); equal(m.state.saveErrors["1"], true); equal(m.disk, "4")
    panel = m.load("panel"); assert(find(panel.tree, "division-2").selected)
    equal(m.state.saveErrors["1"], true)
    local count = #m.layouts(); m.writeOK = true; click(panel, "division-2"); m.drain()
    equal(m.state.saveErrors["1"], false); equal(m.disk, "4"); equal(#m.layouts(), count)
    local saved = decode(m.files["/mock-only/workspace-divisions.json"])
    equal(saved.byId["1"], 2); equal(saved.version, 2); equal(saved.session, "/mock/niri.sock")
    local restarted = mock({ disk = m.disk, files = m.files }):ready()
    equal(restarted.load("widget").text, "2")
end)

test("missing data directory permits temporary selection and retry", function()
    local options = { noDataDir = true }
    local m = mock(options):ready(); local panel = m.load("panel")
    click(panel, "division-2"); m.drain()
    equal(m.state.workspaceDivisions["1"], 2); equal(m.state.saveErrors["1"], true); equal(#m.writes, 0)
    equal(m.state.layoutStatuses["1"], "applied")
    options.noDataDir = false
    local before = #m.layouts(); click(panel, "division-2"); m.drain()
    equal(decode(m.files["/mock-only/workspace-divisions.json"]).byId["1"], 2)
    equal(m.state.saveErrors["1"], false); equal(#m.layouts(), before)
end)

test("reapply and pause controls preserve independent warnings", function()
    local m = mock({ state = { workspaceDivisions = { ["1"] = 3 }, saveErrors = { ["1"] = true },
        streamError = true, workspaceRequest = { serial = 8, workspaceId = 1, division = 3 } } }):ready()
    m.state.streamError = true
    m.set("saveErrors", { ["1"] = true })
    local panel = m.load("panel"); local widget = m.load("widget")
    local close = find(panel.tree, "close-panel"); assert(close.tooltip or close.text, "close has no label")
    local writes = #m.writes; click(panel, "reapply"); m.drain()
    equal(m.state.workspaceRequest.serial, 9); equal(#m.writes, writes)
    equal(m.state.saveErrors["1"], true); equal(m.state.streamError, true); equal(m.state.layoutStatuses["1"], "applied")
    click(panel, "pause"); equal(m.state.paused, true)
    local reapply = find(panel.tree, "reapply"); assert(reapply.enabled == false or reapply.disabled == true)
    assert(widget.tooltip ~= nil and widget.tooltip:find("paus"), "widget pause missing from text")
    click(panel, "division-2"); m.drain(); equal(m.state.workspaceDivisions["1"], 2)
    local before = #m.layouts(); click(panel, "pause"); m.drain(); equal(#m.layouts(), before + 1)
end)


local function dual()
    local m = mock({ disk = "4" })
    m.workspaces = {
        { id = 1, idx = 1, output = "DP-1", is_active = true, is_focused = true, active_window_id = 11 },
        { id = 2, idx = 2, output = "HDMI-A-1", is_active = true, is_focused = false, active_window_id = 21 },
    }
    m.windows = append(windows(1, 11, 4, 11), windows(2, 21, 4))
    m.ready(); m.request(2, 2); m.drain(); m.commands = {}
    return m
end
local function focus(m, id)
    for _, workspace in ipairs(m.workspaces) do workspace.is_focused = workspace.id == id end
    for _, window in ipairs(m.windows) do window.is_focused = window.id == (id == 1 and 11 or 21) end
    m.event({ WorkspaceActivated = { id = id, focused = true } })
end

test("focus changes indicators only and monitor migration retains divisions", function()
    local m = dual()
    local a = m.load("widget", "DP-1", "widgetA")
    local b = m.load("widget", "HDMI-A-1", "widgetB")
    equal(a.text, "4"); equal(b.text, "2")
    focus(m, 2); m.drain(); equal(a.text, "4"); equal(b.text, "2"); equal(#m.layouts(), 0)
    local panel = m.load("panel", "HDMI-A-1")
    click(panel, "division-3"); m.drain()
    equal(a.text, "4"); equal(b.text, "3"); hasWidth(assert(m.layouts()[1]), "33.333")
    local before = #m.layouts()
    m.workspaces[1].output, m.workspaces[2].output = "HDMI-A-1", "DP-1"
    m.event({ WorkspacesChanged = { workspaces = m.workspaces } }); m.drain()
    equal(a.text, "3"); equal(b.text, "4"); equal(#m.layouts(), before)
    m.set("paused", true); focus(m, 1); m.drain()
    equal(a.text, "3"); equal(b.text, "4"); equal(#m.layouts(), before)
end)

test("panel output context and IPC fallback choose their own workspace", function()
    local m = dual()
    local widget = m.load("widget", "HDMI-A-1")
    widget.onClick()
    local ipc = assert(m.queue[1]); equal(ipc.kind, "panel")
    assert(ipc.command:find("pir0c0pter0/niri-auto-tile:panel", 1, true))
    assert(ipc.command:find("'HDMI-A-1'", 1, true)); m.reply({ exitCode = 0 })
    local panel = m.load("panel", "HDMI-A-1")
    assert(find(panel.tree, "division-2").selected)
    click(panel, "division-3"); m.drain()
    equal(m.state.workspaceRequest.workspaceId, 2); equal(#m.layouts(), 0)
    equal(m.state.workspaceDivisions["1"], 4)
    panel = m.load("panel"); assert(find(panel.tree, "division-4").selected)
    click(panel, "division-1"); m.drain(); equal(m.state.workspaceRequest.workspaceId, 1)
    equal(m.state.workspaceDivisions["2"], 3)
    focus(m, 2); assert(find(panel.tree, "division-3").selected)
end)

test("widget panel IPC quotes output names and reports process failures", function()
    local output = "DP-'odd name'; $(unexpected)"
    local m = mock()
    local widget = m.load("widget", output)
    widget.onClick()
    local command = assert(m.queue[1]).command
    local quoted = "'" .. output:gsub("'", "'\\''") .. "'"
    equal(command, "noctalia msg panel-toggle pir0c0pter0/niri-auto-tile:panel " .. quoted)
    m.reply({ exitCode = 1, stderr = "IPC unavailable" })
    assert(#m.logs > 0, "failed panel IPC was silent")
    local count = #m.logs; m.spawnFailures.panel = true; widget.onClick()
    equal(#m.queue, 0); assert(#m.logs > count, "failed panel launch was silent")
end)

test("delayed panel request for A cannot resize B after focus changes", function()
    local m = dual(); local panel = m.load("panel", "DP-1")
    click(panel, "division-2"); m.tick(5); m.reply()
    focus(m, 2); m.reply(); m.drain()
    equal(#m.layouts(), 0); equal(m.state.workspaceDivisions["1"], 2)
    equal(m.state.workspaceDivisions["2"], 2)
    m.commands = {}; focus(m, 1); m.drain(); equal(#m.layouts(), 0, "focus must not revive old intent")
end)

test("workspace errors stay isolated while global pause and stream warnings are shared", function()
    local m = dual(); local a = m.load("widget", "DP-1", "widgetA")
    local b = m.load("widget", "HDMI-A-1", "widgetB")
    m.set("saveErrors", { ["1"] = true })
    m.set("layoutErrors", { ["1"] = true })
    m.set("layoutStatuses", { ["1"] = "floating", ["2"] = "applied" })
    assert(a.tooltip:find("status.floating", 1, true)); assert(a.tooltip:find("status.error", 1, true))
    assert(not b.tooltip:find("status.floating", 1, true)); assert(not b.tooltip:find("status.error", 1, true))
    local panel = m.load("panel", "HDMI-A-1")
    assert(not find(panel.tree, "layout-error")); assert(not find(panel.tree, "save-error"))
    m.set("paused", true); m.set("streamError", true)
    assert(a.tooltip:find("status.paused", 1, true)); assert(b.tooltip:find("status.paused", 1, true))
end)

test("request serial and service reload never replay prior requests", function()
    local m = mock():ready(); m.request(2); m.drain()
    local before, writes = #m.layouts(), #m.writes
    m.set("workspaceRequest", copy(m.state.workspaceRequest)); m.tick(50)
    equal(#m.layouts(), before); equal(#m.writes, writes)
    local serial = m.state.workspaceRequest.serial
    m.load("panel"); m.load("panel"); equal(m.state.workspaceRequest.serial, serial)
    m.load("service"); m.drain(); equal(#m.writes, writes, "old selection saved again on reload")
    local after = #m.layouts(); m.tick(50); equal(#m.layouts(), after)
    click(m.panel, "reapply"); m.drain()
    equal(m.state.workspaceRequest.serial, serial + 1); equal(#m.writes, writes)
end)

test("new workspace selection supersedes pending queries and finishes started batches", function()
    for _, phase in ipairs({ "pending", "query", "batch" }) do
        local m = dual(); m.request(2, 1)
        if phase ~= "pending" then m.tick(5) end
        if phase == "batch" then m.reply(); m.reply(); equal(m.queue[1].kind, "layout") end
        focus(m, 2); m.request(3, 2); m.drain()
        local layouts = m.layouts()
        equal(#layouts, phase == "batch" and 2 or 1)
        hasWidth(layouts[#layouts], "33.333")
        assert(not layouts[#layouts]:find("--id 11", 1, true), "B request resized A")
        if phase == "batch" then hasWidth(layouts[1], "50") end
        equal(m.state.workspaceDivisions["1"], 2); equal(m.state.workspaceDivisions["2"], 3)
        equal(m.state.layoutStatuses["1"], phase == "batch" and "applied" or "idle", "superseded A status")
    end
end)

test("successful complete-map save clears earlier errors in other workspaces", function()
    local m = dual(); m.writeOK = false; m.request(1, 1); m.drain()
    equal(m.state.saveErrors["1"], true)
    m.writeOK = true; m.request(3, 2); m.drain()
    equal(m.state.saveErrors["1"], false); equal(m.state.saveErrors["2"], false)
    local saved = decode(m.files["/mock-only/workspace-divisions.json"])
    equal(saved.byId["1"], 1); equal(saved.byId["2"], 3)
end)

test("new request supersedes a pending focus mismatch retry", function()
    local m = dual(); m.request(2, 1); m.tick(5); m.reply()
    m.windows = windows(2, 21, 4, 21); m.reply()
    equal(#m.layouts(), 0)
    focus(m, 2); m.request(3, 2); m.drain()
    equal(#m.layouts(), 1); hasWidth(m.layouts()[1], "33.333")
    equal(m.state.layoutStatuses["1"], "idle")
    equal(m.state.layoutStatuses["2"], "applied")
end)

test("saving B after service reload persists A temporary named preference", function()
    local m = dual(); m.workspaces[1].name = "coding"
    m.event({ WorkspacesChanged = { workspaces = m.workspaces } })
    m.request(2, 1); m.drain(); m.writeOK = false; m.request(3, 1); m.drain()
    equal(decode(m.files["/mock-only/workspace-divisions.json"]).byName.coding, 2)
    m.load("service"); m.drain(); m.writeOK = true; m.request(4, 2); m.drain()
    equal(decode(m.files["/mock-only/workspace-divisions.json"]).byName.coding, 3)
    equal(m.state.saveErrors["1"], false)
end)

test("resume applies the currently focused workspace preference", function()
    local m = dual(); m.set("paused", true); m.request(1, 1); focus(m, 2)
    m.drain(); equal(#m.layouts(), 0)
    m.set("paused", false); m.drain()
    equal(#m.layouts(), 1); hasWidth(m.layouts()[1], "50")
    assert(not m.layouts()[1]:find("--id 11", 1, true), "resume used paused request target")
    equal(m.state.workspaceDivisions["1"], 1)
end)

test("shared temporary selection wins over stale disk on service reload", function()
    local m = mock({ disk = "4" }):ready(); m.request(2); m.drain()
    m.writeOK = false; m.request(3); m.drain()
    equal(decode(m.files["/mock-only/workspace-divisions.json"]).byId["1"], 2)
    m.load("service"); m.drain()
    equal(m.state.workspaceDivisions["1"], 3)
    equal(m.state.saveErrors["1"], true)
    equal(m.load("widget").text, "3")
end)

test("unnamed workspaces restore positions on independent monitors after reboot", function()
    local m = dual(); m.workspaces[2].idx = 1
    m.event({ WorkspacesChanged = { workspaces = m.workspaces } })
    m.request(1, 1); m.request(3, 2); m.drain()
    local saved = decode(m.files["/mock-only/workspace-divisions.json"])
    equal(saved.byPosition["DP-1"]["1"], 1)
    equal(saved.byPosition["HDMI-A-1"]["1"], 3)
    local restarted = mock({ files = m.files, session = "/mock/reboot.sock" })
    restarted.workspaces = copy(m.workspaces)
    restarted.workspaces[1].id, restarted.workspaces[2].id = 8, 9
    restarted.windows = append(windows(8, 11, 4, 11), windows(9, 21, 4))
    restarted.ready()
    equal(restarted.state.workspaceDivisions["8"], 1)
    equal(restarted.state.workspaceDivisions["9"], 3)
    equal(#restarted.writes, 0, "restore never rewrites disk")
end)

test("named preferences precede positions and missing positions use defaults", function()
    local saved = encode({ version = 2, session = "old", byId = {}, byName = { coding = 2 },
        byPosition = { ["DP-1"] = { ["1"] = 1 } } })
    for _, row in ipairs({
        { id = 8, name = "coding", idx = 1, output = "DP-1" },
        { id = 8, name = "new-name", idx = 1, output = "DP-1" },
        { id = 8, idx = 1 }, { id = 8, idx = 0, output = "DP-1" },
        { id = 8, idx = 1.5, output = "DP-1" },
    }) do
        local m = mock({ files = { ["/mock-only/workspace-divisions.json"] = saved } })
        row.is_active, row.is_focused = true, true
        m.workspaces = { row }; m.windows = windows(8, 11, 4, 11); m.ready()
        equal(m.state.workspaceDivisions["8"], row.name == "coding" and 2 or 4)
    end
end)

test("position saves follow current slots without automatic writes on reorder", function()
    local m = mock():ready(); m.request(2); m.drain()
    local count = #m.writes
    m.workspaces[1].idx = 2
    m.event({ WorkspacesChanged = { workspaces = m.workspaces } }); m.drain()
    equal(#m.writes, count)
    equal(m.state.workspaceDivisions["1"], 2)
    m.request(2); m.drain()
    equal(decode(m.files["/mock-only/workspace-divisions.json"]).byPosition["DP-1"]["2"], 2)
end)

test("recovered reads preserve untouched preferences and temporary choices", function()
    local saved = encode({ version = 1, session = "/mock/niri.sock",
        byId = { ["1"] = 2, ["2"] = 3 }, byName = { coding = 2, chat = 3, absent = 4 } })
    local m = mock({ files = { ["/mock-only/workspace-divisions.json"] = saved } })
    m.workspaces[1].name = "coding"
    m.workspaces[2] = { id = 2, name = "chat", idx = 2, output = "DP-1" }
    m.readOK = false; m.ready()
    equal(m.state.saveErrors["1"], true, "failed read must be visible")
    m.request(1); m.drain()
    equal(#m.writes, 0, "unread existing file must stay intact")
    m.load("service"); m.drain()
    m.readOK = true; m.request(1); m.drain()
    local result = decode(m.files["/mock-only/workspace-divisions.json"])
    equal(result.byName.coding, 1); equal(result.byName.chat, 3); equal(result.byName.absent, 4)
    equal(result.byId["2"], 3); equal(m.state.workspaceDivisions["2"], 3)
    equal(m.state.saveErrors["1"], false)
end)

test("legacy preferences migrate on explicit save and invalid positions stay untouched", function()
    local legacy = encode({ version = 1, session = "old", byId = {}, byName = { coding = 2 }, byPosition = true })
    local m = mock({ files = { ["/mock-only/workspace-divisions.json"] = legacy } })
    m.workspaces[1].name = "coding"
    m.workspaces[2] = { id = 2, idx = 2, output = "DP-1" }; m.ready()
    equal(m.state.workspaceDivisions["1"], 2); equal(m.state.workspaceDivisions["2"], 4)
    equal(#m.writes, 0)
    m.request(2); m.drain()
    local saved = decode(m.files["/mock-only/workspace-divisions.json"])
    equal(saved.version, 2); assert(type(saved.byPosition) == "table")
    for _, bad in ipairs({
        { version = 2, byId = {}, byName = {}, byPosition = false },
        { version = 2, byId = {}, byName = {}, byPosition = { ["DP-1"] = { ["0"] = 2 } } },
        { version = 2, byId = {}, byName = {}, byPosition = { ["DP-1"] = { ["1"] = 5 } } },
    }) do
        local raw = encode(bad)
        local invalid = mock({ files = { ["/mock-only/workspace-divisions.json"] = raw } }):ready()
        equal(invalid.files["/mock-only/workspace-divisions.json"], raw)
        equal(invalid.state.saveErrors["1"], true); equal(#invalid.writes, 0)
    end
end)

test("failed temporary writes and replacement preserve the saved preferences", function()
    for _, failure in ipairs({ "write", "rename" }) do
        local m = mock():ready(); m.request(2); m.drain()
        local saved = m.files["/mock-only/workspace-divisions.json"]
        if failure == "write" then m.writeOK, m.partialWrite = false, true else m.renameOK = false end
        m.request(3); m.drain()
        equal(m.files["/mock-only/workspace-divisions.json"], saved, "original survives " .. failure)
        equal(m.state.workspaceDivisions["1"], 3); equal(m.state.saveErrors["1"], true)
        m.writeOK, m.renameOK = true, true
        m.request(3); m.drain()
        equal(decode(m.files["/mock-only/workspace-divisions.json"]).byId["1"], 3)
        equal(m.state.saveErrors["1"], false)
    end
end)

test("same session restores IDs and new sessions restore names and positions", function()
    local m = dual(); m.workspaces[2].name = "coding"
    m.event({ WorkspacesChanged = { workspaces = m.workspaces } }); m.request(3, 2); m.request(1, 1); m.drain()
    local saved = decode(m.files["/mock-only/workspace-divisions.json"])
    equal(saved.byId["1"], 1); equal(saved.byId["2"], 3); equal(saved.byName.coding, 3)
    for _, session in ipairs({ "/mock/niri.sock", "/mock/new.sock", "" }) do
        local restarted = mock({ disk = "4", files = m.files, session = session })
        restarted.workspaces = copy(m.workspaces); restarted.ready()
        equal(restarted.state.workspaceDivisions["1"], 1)
        equal(restarted.state.workspaceDivisions["2"], 3)
        equal(#restarted.writes, 0, "restoration must not rewrite disk")
    end
end)

test("renamed and newly named workspaces retain preferences across compositor sessions", function()
    for _, oldName in ipairs({ "coding", false }) do
        local m = mock({ disk = "4" }); m.workspaces[1].name = oldName or nil; m.ready()
        m.request(2); m.drain(); m.commands = {}
        m.workspaces[1].name = "work"
        m.event({ WorkspacesChanged = { workspaces = m.workspaces } }); m.drain()
        equal(#m.layouts(), 0, "renaming must not redistribute")
        equal(m.state.workspaceDivisions["1"], 2)
        local restarted = mock({ disk = "4", files = m.files, session = "/mock/restarted.sock" })
        restarted.workspaces[1].id = 8; restarted.workspaces[1].name = "work"
        restarted.windows = windows(8, 11, 4, 11); restarted.ready()
        equal(restarted.state.workspaceDivisions["8"], 2, "name survives compositor restart")
    end
end)

test("removing a saved workspace name preserves its division after reboot", function()
    for _, newName in ipairs({ false, "" }) do
        local m = mock(); m.workspaces[1].name = "coding"
        m.ready(); m.request(2); m.drain(); m.commands = {}
        local before = #m.writes
        m.workspaces[1].name = newName or nil
        m.event({ WorkspacesChanged = { workspaces = m.workspaces } }); m.drain()
        equal(#m.writes, before + 1); equal(#m.layouts(), 0, "removing a name must not resize")
        equal(decode(m.files["/mock-only/workspace-divisions.json"]).byPosition["DP-1"]["1"], 2)
        local restarted = mock({ files = m.files, session = "/mock/reboot.sock" })
        restarted.workspaces[1].id = 8; restarted.windows = windows(8, 11, 4, 11)
        restarted.ready(); equal(restarted.state.workspaceDivisions["8"], 2)
    end
end)

test("removing a name cannot overwrite unread preferences or save an unknown slot", function()
    local disk = encode({ version = 1, session = "/mock/niri.sock", byId = { ["1"] = 2 },
        byName = { coding = 2, absent = 3 } })
    local unread = mock({ files = { ["/mock-only/workspace-divisions.json"] = disk } })
    unread.workspaces[1].name = "coding"; unread.readOK = false; unread.ready()
    unread.workspaces[1].name = nil
    unread.event({ WorkspacesChanged = { workspaces = unread.workspaces } }); unread.drain()
    equal(#unread.writes, 0); equal(unread.files["/mock-only/workspace-divisions.json"], disk)
    equal(unread.state.saveErrors["1"], true)
    for _, missing in ipairs({ "output", "idx" }) do
        local m = mock(); m.workspaces[1].name = "coding"; m.ready(); m.request(2); m.drain()
        local before = #m.writes
        m.workspaces[1].name, m.workspaces[1][missing] = nil, nil
        m.event({ WorkspacesChanged = { workspaces = m.workspaces } }); m.drain()
        equal(#m.writes, before, "no automatic save for unknown " .. missing)
    end
end)

test("failed rename save preserves temporary preference and exposes warning", function()
    local m = mock():ready(); m.request(2); m.drain(); m.commands = {}
    local disk = m.files["/mock-only/workspace-divisions.json"]
    m.writeOK = false; m.workspaces[1].name = "work"
    m.event({ WorkspacesChanged = { workspaces = m.workspaces } }); m.drain()
    equal(m.state.workspaceDivisions["1"], 2); equal(m.state.saveErrors["1"], true)
    equal(m.files["/mock-only/workspace-divisions.json"], disk); equal(#m.layouts(), 0)
    m.writeOK = true; m.request(2); m.drain()
    equal(m.state.saveErrors["1"], false); equal(#m.layouts(), 0)
    equal(decode(m.files["/mock-only/workspace-divisions.json"]).byName.work, 2)
end)

test("rename cannot overwrite preferences unreadable at startup", function()
    local disk = encode({ version = 1, session = "/mock/niri.sock",
        byId = { ["1"] = 2, ["2"] = 3 }, byName = { coding = 2, chat = 3 } })
    local m = mock({ files = { ["/mock-only/workspace-divisions.json"] = disk } })
    m.workspaces[1].name = "coding"; m.readOK = false; m.ready()
    m.readOK = true; m.workspaces[1].name = "work"
    m.event({ WorkspacesChanged = { workspaces = m.workspaces } }); m.drain()
    equal(#m.writes, 0, "rename overwrote unread preference data")
    equal(m.files["/mock-only/workspace-divisions.json"], disk)
    equal(decode(m.files["/mock-only/workspace-divisions.json"]).byName.chat, 3)
    equal(m.state.saveErrors["1"], true)
    m.request(2); m.drain(); local before = #m.writes
    m.workspaces[1].name = "work-new"
    m.event({ WorkspacesChanged = { workspaces = m.workspaces } }); m.drain()
    equal(#m.writes, before + 1, "explicit successful save authorizes metadata writes")
    equal(decode(m.files["/mock-only/workspace-divisions.json"]).byName["work-new"], 2)
    equal(m.state.saveErrors["1"], false)
end)

test("workspace naming never overwrites malformed persistence automatically", function()
    local bad = "broken json"
    local m = mock({ disk = "3", files = { ["/mock-only/workspace-divisions.json"] = bad } }):ready()
    m.workspaces[1].name = "work"
    m.event({ WorkspacesChanged = { workspaces = m.workspaces } }); m.drain()
    equal(#m.writes, 0); equal(m.files["/mock-only/workspace-divisions.json"], bad)
    equal(m.state.workspaceDivisions["1"], 3)
end)

test("service reload clears orphaned transient statuses and preserves execution errors", function()
    for _, status in ipairs({ "pending", "applying" }) do
        local m = dual(); focus(m, 2)
        m.set("layoutStatuses", { ["1"] = status, ["2"] = "applied" })
        m.set("layoutErrors", { ["1"] = true })
        m.load("service"); m.drain()
        equal(m.state.layoutStatuses["1"], "idle"); equal(m.state.layoutErrors["1"], true)
    end
end)

test("malformed persistence stays untouched until an explicit valid selection", function()
    for _, bad in ipairs({ "broken json", encode({ version = 9, byId = { ["1"] = 1 } }),
        encode({ version = 1, session = "/mock/niri.sock", byId = false, byName = false }) }) do
        local m = mock({ disk = "3", files = { ["/mock-only/workspace-divisions.json"] = bad } }):ready()
        equal(m.state.workspaceDivisions["1"], 3); equal(#m.writes, 0)
        local panel = m.load("panel"); m.load("widget"); panel.onOpen()
        equal(m.files["/mock-only/workspace-divisions.json"], bad); equal(#m.writes, 0)
        click(panel, "division-2"); m.drain()
        equal(decode(m.files["/mock-only/workspace-divisions.json"]).byId["1"], 2)
        equal(m.disk, "3", "legacy default preserved")
    end
end)

test("read failure still permits temporary state and a later successful save", function()
    local m = mock({ disk = "2" }); m.readOK = false; m.ready()
    equal(m.state.workspaceDivisions["1"], 4)
    m.writeOK = false; m.request(3); m.drain()
    equal(m.state.workspaceDivisions["1"], 3); equal(m.state.saveErrors["1"], true)
    m.readOK, m.writeOK = true, true
    local before = #m.layouts(); m.request(3); m.drain()
    equal(m.state.saveErrors["1"], false); equal(#m.layouts(), before)
    equal(decode(m.files["/mock-only/workspace-divisions.json"]).byId["1"], 3)
end)

test("new workspace events win over stale bootstrap queries", function()
    local m = mock(); m.load("service")
    local newer = { { id = 2, idx = 2, output = "DP-1", is_active = true, is_focused = true, active_window_id = 21 } }
    m.event({ WorkspacesChanged = { workspaces = newer } })
    m.reply({ exitCode = 0, stdout = encode(m.workspaces) })
    equal(m.state.workspaces[1].id, 2)
    m.workspaces = newer; m.windows = windows(2, 21, 4, 21); m.drain()
    equal(m.load("widget").text, "4")
    m.event({ WorkspaceActiveWindowChanged = { workspace_id = 2, active_window_id = 22 } })
    equal(m.state.workspaces[1].active_window_id, 22)
end)

test("unknown output disables workspace controls until workspaces arrive", function()
    local m = mock({ state = { workspaces = {}, workspaceDivisions = {} } })
    local panel = m.load("panel", "missing-output")
    equal(find(panel.tree, "division-2").enabled, false)
    equal(find(panel.tree, "reapply").enabled, false)
    equal(m.state.workspaceRequest, nil); equal(#m.writes, 0)
end)


local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function write(path, value)
    local file = assert(io.open(path, "w")); assert(file:write(value)); file:close()
end
local function read(path)
    local file = assert(io.open(path)); local value = file:read("*a"); file:close(); return value
end

test("shell preserves failures and still attempts focus restoration", function()
    local logic = assert(loadfile(root .. "/niri-auto-tile/service.luau", "t", setmetatable({}, { __index = _G })))()
    local command = logic.buildCommand(windows(1, 11, 5, 12), { [1] = 12 }, 4)
    local directory = os.tmpname(); os.remove(directory)
    assert(os.execute("/bin/mkdir " .. quote(directory)))
    local ok, err = pcall(function()
        -- runAsync's documented string-command interpreter is /bin/sh -c.
        -- PATH contains only this fake niri; its script uses shell builtins only.
        write(directory .. "/niri", [[#!/bin/sh
count=0
if [ -f "$TEST_DIR/count" ]; then read -r count < "$TEST_DIR/count"; fi
count=$((count + 1))
printf '%s\n' "$count" > "$TEST_DIR/count"
printf '%s\n' "$*" >> "$TEST_DIR/calls"
if [ "$count" = "$FAIL_AT" ]; then printf 'fake niri failure %s\n' "$count" >&2; exit 7; fi
]])
        assert(os.execute("/bin/chmod +x " .. quote(directory .. "/niri")))
        local function run(failAt)
            write(directory .. "/calls", ""); write(directory .. "/count", "0\n")
            local success = os.execute("PATH=" .. quote(directory) .. " TEST_DIR=" .. quote(directory)
                .. " FAIL_AT=" .. tostring(failAt) .. " /bin/sh -c " .. quote(command)
                .. " >" .. quote(directory .. "/stdout") .. " 2>" .. quote(directory .. "/stderr"))
            local calls = {}
            for line in read(directory .. "/calls"):gmatch("[^\n]+") do calls[#calls + 1] = line end
            return success, calls, read(directory .. "/stderr")
        end
        local success, calls = run(0); assert(success, "fake successful batch failed")
        assert(#calls >= 14, "incomplete batch fixture")
        local resize, anchor, center
        for index, line in ipairs(calls) do
            if not resize and line:find("set-column-width", 1, true) then resize = index end
            if index > 10 and line:find("focus-window", 1, true) and not anchor then anchor = index end
            if line:find("center-visible-columns", 1, true) then center = index end
        end
        for _, index in ipairs({ 1, assert(resize), assert(anchor), assert(center), #calls }) do
            local failed, actual, stderr = run(index)
            assert(not failed, "batch erased action failure at " .. index)
            assert(stderr:find("fake niri failure", 1, true), "stderr discarded")
            equal(actual[#actual], "msg action focus-window --id 12", "restore attempt")
            if index == 1 then
                assert(not actual[2]:find("set-column-width", 1, true), "resize after failed focus")
            end
        end
    end)
    assert(os.execute("/bin/rm -rf -- " .. quote(directory)))
    assert(ok, err)
end)

local function restoredPair()
    local saved = encode({ version = 1, session = "/mock/previous.sock",
        byId = { ["1"] = 1, ["2"] = 4 }, byName = { coding = 2, chat = 3 } })
    local m = mock({ session = "/mock/reboot.sock",
        files = { ["/mock-only/workspace-divisions.json"] = saved } })
    m.workspaces = {
        { id = 8, idx = 1, name = "coding", output = "DP-1", is_active = true,
            is_focused = true, active_window_id = 11 },
        { id = 9, idx = 2, name = "chat", output = "DP-1", is_active = false,
            is_focused = false, active_window_id = 21 },
    }
    m.windows = append(windows(8, 11, 4, 11), windows(9, 21, 4))
    m.ready()
    return m
end
local function activateRestored(m, id, floating)
    for _, workspace in ipairs(m.workspaces) do
        workspace.is_focused = workspace.id == id
        workspace.is_active = workspace.id == id
    end
    for _, window in ipairs(m.windows) do
        window.is_focused = window.id == (id == 8 and 11 or 21)
        if window.is_focused then window.is_floating = floating == true end
    end
    m.event({ WorkspaceActivated = { id = id, focused = true } })
end

test("restored background workspace applies on first activation only", function()
    local m = restoredPair()
    equal(m.state.workspaceDivisions["9"], 3)
    equal(#m.layouts(), 0, "background must remain untouched during startup")
    activateRestored(m, 9); m.drain()
    equal(#m.layouts(), 1); hasWidth(m.layouts()[1], "33.333")
    assert(not m.layouts()[1]:find("--id 11", 1, true), "restoration touched another workspace")
    equal(m.state.pendingRestores["9"], nil)
    activateRestored(m, 8); m.drain(); activateRestored(m, 9); m.drain()
    equal(#m.layouts(), 1, "normal focus must not reapply completed restoration")
end)

test("restored background preference survives service reload until applied", function()
    local m = restoredPair()
    equal(m.state.pendingRestores["9"], true)
    m.load("service"); m.streams[1] = m.streams[#m.streams]; m.drain(); m.commands = {}
    equal(m.state.pendingRestores["9"], true)
    activateRestored(m, 9); m.drain()
    equal(#m.layouts(), 1); hasWidth(m.layouts()[1], "33.333")
    equal(m.state.pendingRestores["9"], nil)
end)

test("restoration waits through pause and retries failure on next activation", function()
    local m = restoredPair()
    m.set("paused", true); activateRestored(m, 9); m.drain()
    equal(#m.layouts(), 0); equal(m.state.pendingRestores["9"], true)
    m.set("paused", false); m.tick(); m.reply(); m.reply()
    equal(#m.layouts(), 1)
    m.reply({ exitCode = 1, stdout = "", stderr = "failed restoration" }); m.drain()
    equal(m.state.pendingRestores["9"], true)
    activateRestored(m, 8); m.drain(); activateRestored(m, 9); m.drain()
    equal(#m.layouts(), 2); equal(m.state.pendingRestores["9"], nil)
end)

test("floating restored workspace waits for a tiled focus event", function()
    local m = restoredPair()
    activateRestored(m, 9, true); m.drain()
    equal(#m.layouts(), 0); equal(m.state.pendingRestores["9"], true)
    m.windows[5].is_floating = false
    m.event({ WindowFocusChanged = { id = 21 } }); m.drain()
    equal(#m.layouts(), 1); hasWidth(m.layouts()[1], "33.333")
    equal(m.state.pendingRestores["9"], nil)
end)

test("restore focus events during a successful batch do not queue another batch", function()
    local m = restoredPair()
    activateRestored(m, 9); m.tick(4); m.reply(); m.reply()
    equal(#m.layouts(), 1)
    m.event({ WindowFocusChanged = { id = 21 } })
    m.reply(); m.drain()
    equal(#m.layouts(), 1)
end)

test("failed restoration ignores delayed focus events until workspace activation", function()
    local m = restoredPair()
    activateRestored(m, 9); m.tick(4); m.reply(); m.reply()
    equal(#m.layouts(), 1)
    m.event({ WindowFocusChanged = { id = 21 } })
    m.reply({ exitCode = 1, stdout = "", stderr = "failed restoration" }); m.drain()
    equal(#m.layouts(), 1, "failed batch must not retry its own focus events")
    equal(m.state.pendingRestores["9"], true)
    m.event({ WindowFocusChanged = { id = 21 } })
    m.event({ WorkspaceActiveWindowChanged = { workspace_id = 9, active_window_id = 21 } })
    m.drain(); equal(#m.layouts(), 1, "late focus events must not retry a failed batch")
    activateRestored(m, 9); m.drain()
    equal(#m.layouts(), 2); equal(m.state.pendingRestores["9"], nil)
end)

test("empty restored workspace keeps its pending layout until windows arrive", function()
    local m = restoredPair()
    while #m.windows > 4 do table.remove(m.windows) end
    activateRestored(m, 9)
    m.event({ WindowsChanged = { windows = m.windows } }); m.drain()
    equal(#m.layouts(), 0); equal(m.state.pendingRestores["9"], true)
    append(m.windows, windows(9, 21, 1, 21))
    m.event({ WindowOpenedOrChanged = { window = m.windows[5] } }); m.drain()
    assert(#m.layouts() > 0); hasWidth(m.layouts()[1], "33.333")
    equal(m.state.pendingRestores["9"], nil)
end)

test("manual selection precedes pending restoration and old success cannot clear it", function()
    local m = restoredPair()
    activateRestored(m, 9); m.request(2, 9); m.drain()
    equal(#m.layouts(), 1); hasWidth(m.layouts()[1], "50")
    equal(m.state.pendingRestores["9"], nil)

    m = restoredPair()
    activateRestored(m, 9); m.tick(4); m.reply(); m.reply()
    equal(#m.layouts(), 1); hasWidth(m.layouts()[1], "33.333")
    m.request(2, 9); m.reply()
    equal(m.state.pendingRestores["9"], true, "old batch cannot confirm newer preference")
    m.drain(); equal(#m.layouts(), 2); hasWidth(m.layouts()[2], "50")
    equal(m.state.pendingRestores["9"], nil)
end)

test("new restoration activation survives a superseded batch callback", function()
    for _, division in ipairs({ 2, 1 }) do
        local m = restoredPair()
        activateRestored(m, 9); m.tick(4); m.reply(); m.reply()
        equal(#m.layouts(), 1)
        activateRestored(m, 8); m.request(division, 8); activateRestored(m, 9)
        m.reply({ exitCode = 1, stdout = "", stderr = "old failure" }); m.drain()
        equal(m.state.pendingRestores["9"], nil, "current restored workspace must still apply")
        equal(#m.layouts(), 2, "new activation survives old callback")
        hasWidth(m.layouts()[2], "33.333")
    end
end)

for _, case in ipairs(cases) do
    if not arg[1] or case[1]:find(arg[1], 1, true) then
        local ok, err = pcall(case[2])
        if not ok then io.stderr:write("FAIL " .. case[1] .. ": " .. tostring(err) .. "\n"); os.exit(1) end
        passed = passed + 1; print("ok " .. case[1])
    end
end
assert(passed > 0, "no matching tests")
print("runtime: " .. passed .. " tests passed")
