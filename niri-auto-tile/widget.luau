local division = tonumber(noctalia.state.get("division")) or 4

local function render()
    barWidget.setGlyph("columns-3")
    barWidget.setText(tostring(division))
    barWidget.setTooltip(noctalia.tr("bar.tooltip", { count = division }))
end

noctalia.state.watch("division", function(value)
    division = tonumber(value) or 4
    render()
end)

function update()
    render()
end

function onClick()
    noctalia.togglePanel("pir0c0pter0/niri-auto-tile:panel")
end
