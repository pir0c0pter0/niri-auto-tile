local dataDir = noctalia.pluginDataDir()
local dataPath = dataDir and dataDir .. "/division" or nil

local function normalize(value)
    local number = tonumber(value)
    if number == nil or number % 1 ~= 0 or number < 1 or number > 4 then
        return 4
    end
    return number
end

local division = normalize(noctalia.state.get("division")
    or (dataPath and noctalia.readFile(dataPath) or nil))

local function labelFor(value)
    if value == 1 then
        return noctalia.tr("panel.single")
    end
    return noctalia.tr("panel.columns", { count = value })
end

local function render()
    local buttons = {}
    for value = 1, 4 do
        table.insert(buttons, ui.button({
            key = "division-" .. value,
            text = tostring(value),
            tooltip = labelFor(value),
            selected = value == division,
            variant = value == division and "primary" or "default",
            controlSize = "lg",
            flexGrow = 1,
            onClick = "select" .. value,
        }))
    end

    panel.render(ui.column({ gap = 18, padding = 20 }, {
        ui.row({ align = "center", justify = "space_between" }, {
            ui.label({
                text = noctalia.tr("panel.title"),
                fontSize = 18,
                fontWeight = "bold",
                color = "primary",
                flexGrow = 1,
            }),
            ui.button({ glyph = "close", variant = "ghost", onClick = "closePanel" }),
        }),
        ui.row({ gap = 10, align = "center" }, buttons),
    }))
end

local function select(value)
    division = value
    if dataPath then
        local ok, err = noctalia.writeFile(dataPath, tostring(value))
        if not ok then
            noctalia.log("failed to persist division: " .. (err or "unknown error"))
        end
    end
    noctalia.state.set("division", value)
    render()
end

function select1() select(1) end
function select2() select(2) end
function select3() select(3) end
function select4() select(4) end
function closePanel() panel.close() end

noctalia.state.watch("division", function(value)
    division = normalize(value)
    render()
end)

function onOpen()
    render()
end
