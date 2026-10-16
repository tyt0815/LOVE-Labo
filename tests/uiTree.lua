local Assert = require("tests.Assert")
local Widget = require("editor.ui.Widget")
local Canvas = require("editor.ui.Canvas")
local Root = require("editor.ui.Root")
local tests = {}
local function add(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

add("canvas slots place nested children relative to their parent", function()
    local root, nested, child = Canvas.new(), Canvas.new(), Widget.new()
    root:addChild(nested, { x = 20, y = 30, width = 100, height = 80 })
    nested:addChild(child, { fill = true })
    root:setBounds(50, 60, 400, 300)
    Assert.equal(70, child.x)
    Assert.equal(90, child.y)
    Assert.equal(100, child.width)
    Assert.equal(80, child.height)
    root:setSlotBounds(nested.slot, 10, 15, 220, 140)
    Assert.equal(60, child.x)
    Assert.equal(220, child.width)
    Assert.equal(false, pcall(nested.addChild, nested, root))
end)

add("Ui input respects z order visibility clipping and consumption", function()
    local canvas, clicks = Canvas.new(), {}
    local back = Widget.new({ mousepressed = function() clicks[#clicks + 1] = "back"; return true end })
    local front = Widget.new({ mousepressed = function() clicks[#clicks + 1] = "front"; return true end })
    canvas:addChild(back, { x = 0, y = 0, width = 200, height = 200 })
    canvas:addChild(front, { x = 10, y = 10, width = 200, height = 200, z = 1 })
    canvas:setBounds(0, 0, 100, 100)
    local root = Root.new(canvas)
    root:mousepressed(20, 20, 1)
    Assert.equal("front", clicks[1])
    Assert.equal(1, #clicks)
    front.visible = false
    root:mousepressed(20, 20, 1)
    Assert.equal("back", clicks[2])
    root:mousepressed(150, 150, 1)
    Assert.equal(2, #clicks)
end)

add("Ui capture continues drag outside bounds and routes text to focus", function()
    local canvas, moves, text = Canvas.new(), 0, nil
    local child = Widget.new({
        mousepressed = function() return true, true end,
        mousemoved = function() moves = moves + 1; return true end,
        textinput = function(_, value) text = value; return true end
    })
    canvas:addChild(child, { fill = true })
    canvas:setBounds(0, 0, 100, 100)
    local root = Root.new(canvas)
    root:mousepressed(20, 20, 1)
    root:mousemoved(300, 300, 280, 280)
    Assert.equal(1, moves)
    root:textinput("한글")
    Assert.equal("한글", text)
    root:mousereleased(300, 300, 1)
    Assert.equal(nil, root.captured)
    root:mousemoved(400, 400, 100, 100)
    Assert.equal(1, moves)
end)

add("Ui unhandled input bubbles to parent and popup dismissal blocks underlying clicks", function()
    local canvas, clicks = Canvas.new(), 0
    local child = Widget.new()
    canvas.handlers.mousepressed = function() clicks = clicks + 1; return true end
    canvas:addChild(child, { fill = true })
    canvas:setBounds(0, 0, 300, 200)
    local root = Root.new(canvas)
    root:mousepressed(20, 20, 1)
    Assert.equal(1, clicks)
    local popup = Widget.new()
    popup:setBounds(100, 100, 50, 50)
    root:setPopup(popup)
    root:mousepressed(20, 20, 1)
    Assert.equal(nil, root.popup)
    Assert.equal(1, clicks)
end)

add("context menu clamps panels and supports submenu keyboard actions", function()
    local root = Root.new(Canvas.new())
    local Menu = require("editor.ui.ContextMenu")
    local selected = 0
    local menu = Menu.new(root)
    local width, height = love.graphics.getDimensions()
    menu:show(width - 2, height - 2, {
        { label = "New", children = {
            { label = "Disabled", enabled = false, action = function() error("disabled action") end },
            { label = "Folder", action = function() selected = selected + 1 end }
        } },
        { label = "Delete", action = function() selected = selected + 10 end }
    })
    Assert.truthy(menu.panels[1].x + menu.panels[1].w <= width)
    Assert.truthy(menu.panels[1].y + menu.panels[1].h <= height)
    root:keypressed("right")
    Assert.equal(2, #menu.panels)
    Assert.equal(1, #menu.panels[2].items)
    Assert.equal("Folder", menu.panels[2].items[1].label)
    Assert.equal(menu, root.popup)
    root:keypressed("return")
    Assert.equal(1, selected)
    Assert.equal(nil, root.popup)
    menu:show(20, 20, { { label = "Delete", action = function() selected = selected + 10 end } })
    root:keypressed("right")
    Assert.equal(1, selected)
    root:keypressed("escape")
    Assert.equal(nil, root.popup)
end)

add("context menus remove unavailable branches and do not open empty menus", function()
    local root = Root.new(Canvas.new())
    local menu = require("editor.ui.ContextMenu").new(root)
    menu:show(20, 20, {{label = "Empty", children = {{label = "Unavailable", enabled = false}}},
        {label = "Visible", action = function() end}})
    Assert.equal(1, #menu.panels[1].items); Assert.equal("Visible", menu.panels[1].items[1].label)
    Assert.equal(false, menu:show(20, 20, {{label = "Unavailable", enabled = false}}))
    Assert.equal(nil, root.popup)
end)
add("popup blocks background pointer input and receives dialog text", function()
    local canvas, moves = Canvas.new(), 0
    canvas.handlers.mousemoved = function() moves = moves + 1; return true end
    canvas:setBounds(0, 0, 500, 500)
    local root = Root.new(canvas)
    local menu = require("editor.ui.ContextMenu").new(root)
    menu:show(10, 10, { { label = "New" } })
    root:mousemoved(450, 450, 1, 1)
    Assert.equal(0, moves)
    local value
    local dialog = require("editor.ui.Dialog").new(root, { input = true, title = "New",
        value = "Default", onConfirm = function(text)
            if text == "Fail" then return false, "failed" end
            value = text; return true
        end })
    root:textinput("Fail")
    root:keypressed("return")
    Assert.equal("failed", dialog.error)
    Assert.equal(dialog, root.popup)
    dialog.replace = true
    root:textinput("한글")
    root:keypressed("return")
    Assert.equal("한글", value)
    Assert.equal(nil, root.popup)
end)

add("Prefab palette shares nested source colors and cycles independent roots", function()
    local appearance = require("editor.ui.PrefabAppearance")
    local rows = {}
    local function row(key, group, depth)
        rows[#rows + 1] = {object = {key = key, group = group}, depth = depth}
    end
    row("a", "a", 0); row("member", "a", 1)
    row("b", "a", 1); row("c", "a", 2); row("plain", nil, 1)
    row("d", "b", 0); row("e", "c", 1)
    for i = 3, 7 do row("root" .. i, "root" .. i, 0) end
    local groups = appearance.layout(rows, function(object) return object.key, object.group end, function(object) return object.key end)
    local expected = {1, 1, 1, 1, false, 2, 3, 3, 4, 5, 6, 1}
    for index, color in ipairs(expected) do Assert.equal(color or nil, groups[index].colorIndex) end
end)
add("Prefab colors recalculate when nested placement becomes an independent root", function()
    local appearance = require("editor.ui.PrefabAppearance")
    local rows = {{object = {key = "a", source = "one"}, depth = 0},
        {object = {key = "child", source = "two"}, depth = 1},
        {object = {key = "b", source = "two"}, depth = 0}}
    local function layout()
        return appearance.layout(rows, function(object) return object.key, object.source end, function(object) return object.key end)
    end
    local colors = layout()
    Assert.equal(1, colors[1].colorIndex); Assert.equal(2, colors[2].colorIndex); Assert.equal(2, colors[3].colorIndex)
    rows[2].depth = 0
    colors = layout()
    Assert.equal(1, colors[1].colorIndex); Assert.equal(2, colors[2].colorIndex); Assert.equal(3, colors[3].colorIndex)
    rows[1], rows[3] = rows[3], rows[1]
    colors = layout()
    Assert.equal("b", colors[1].key); Assert.equal(1, colors[1].colorIndex)
    Assert.equal("a", colors[3].key); Assert.equal(3, colors[3].colorIndex)
end)
add("Tree line highlighting covers selected ancestry without highlighting other branches", function()
    local Ui = require("editor.Ui")
    local rows = {{depth = 0}, {depth = 1}, {depth = 2}, {depth = 2},
        {depth = 1}, {depth = 2}, {depth = 0}, {depth = 1}}
    local highlights = Ui.treeLineHighlights(rows, function(row) return row == rows[3] end)
    Assert.equal(true, highlights[2][0])
    Assert.equal(true, highlights[3][0]); Assert.equal(true, highlights[3][1])
    Assert.equal(true, highlights[4][1])
    Assert.equal(true, highlights[6][0]); Assert.equal(false, highlights[6][1])
    Assert.equal(false, highlights[8][0])
    highlights = Ui.treeLineHighlights(rows, function(row) return row == rows[1] or row == rows[7] end)
    Assert.equal(true, highlights[6][0]); Assert.equal(false, highlights[6][1])
    Assert.equal(true, highlights[8][0])
    highlights = Ui.treeLineHighlights(rows, function() return false end)
    Assert.equal(false, highlights[3][0]); Assert.equal(false, highlights[3][1])
end)
add("Tree insertion borders distinguish the last child from the next outside sibling", function()
    local rows = {{depth = 0}, {depth = 1}, {depth = 2}, {depth = 0}}
    local drop = require("editor.ui.TreeDrop")
    local inside = drop.tree(rows, rows[3], 65, 44, 22)
    local outside = drop.tree(rows, rows[4], 67, 66, 22)
    Assert.equal("after", inside.mode); Assert.equal(2, inside.depth); Assert.equal(66, inside.lineY)
    Assert.equal("before", outside.mode); Assert.equal(0, outside.depth); Assert.equal(66, outside.lineY)
end)
add("Native frame hit testing separates menus controls drag edges and maximized bounds", function()
    local frame = require("editor.WindowFrame")
    local function hit(x, y, maximized, blocked) return frame.hitTest(x, y, 1000, 680, maximized, blocked, 216) end
    Assert.equal(1, hit(400, 16)); Assert.equal(0, hit(40, 16)); Assert.equal(0, hit(975, 16))
    Assert.equal(0, hit(400, 40)); Assert.equal(0, hit(400, 16, false, true))
    for _, point in ipairs({{1, 1, 2}, {400, 1, 3}, {999, 1, 4}, {999, 400, 5},
        {999, 679, 6}, {400, 679, 7}, {1, 679, 8}, {1, 400, 9}}) do
        Assert.equal(point[3], hit(point[1], point[2]))
        Assert.equal(point[2] < 32 and point[1] >= 216 and point[1] < 862 and 1 or 0, hit(point[1], point[2], true))
    end
end)
add("Window controls use the normal quit path and toggle maximize restore", function()
    local frame = require("editor.WindowFrame")
    local before = frame.active
    local minimize, maximize, restore, isMaximized, quit = love.window.minimize, love.window.maximize, love.window.restore, love.window.isMaximized, love.event.quit
    local minimized, maximized, closed = false, false, false
    local ok, err = pcall(function()
        frame.active = true
        love.window.minimize = function() minimized = true end
        love.window.maximize = function() maximized = true end
        love.window.restore = function() maximized = false end
        love.window.isMaximized = function() return maximized end
        love.event.quit = function() closed = true end
        local controls = require("editor.ui.WindowControls").new()
        local buttons = controls:buttons(love.graphics.getWidth())
        assert(controls:press(buttons[1].x + 10, 16, 1)); Assert.equal(true, minimized)
        assert(controls:press(buttons[2].x + 10, 16, 1)); Assert.equal(true, maximized)
        assert(controls:press(buttons[2].x + 10, 16, 1)); Assert.equal(false, maximized)
        assert(controls:press(buttons[3].x + 10, 16, 1)); Assert.equal(true, closed)
        Assert.equal(false, controls:press(400, 16, 1))
    end)
    frame.active = before
    love.window.minimize, love.window.maximize, love.window.restore, love.window.isMaximized, love.event.quit = minimize, maximize, restore, isMaximized, quit
    assert(ok, err)
end)
add("Window controls bypass modal dialogs and outside popup dismissal before game or picking input", function()
    local frame = require("editor.WindowFrame")
    local active = frame.active
    local minimize, maximize, restore, isMaximized, quit = love.window.minimize, love.window.maximize, love.window.restore, love.window.isMaximized, love.event.quit
    local actions, maximized = {}, false
    local ok, err = pcall(function()
        frame.active = true
        love.window.minimize = function() actions[#actions + 1] = "minimize" end
        love.window.maximize = function() actions[#actions + 1] = "maximize"; maximized = true end
        love.window.restore = function() actions[#actions + 1] = "restore"; maximized = false end
        love.window.isMaximized = function() return maximized end
        love.event.quit = function() actions[#actions + 1] = "close" end
        local app = require("editor.EditorApp").new(); app:draw()
        app.gameEvent = function() error("Window controls must not deliver game input") end
        app.objectPick = {}; app.pickReferenceAt = function() error("Window controls must not pick references") end
        for _, modal in ipairs({true, false}) do
            local popup
            if modal then popup = require("editor.ui.Dialog").new(app.uiRoot, {title = "Modal", onConfirm = function() return true end})
            else
                popup = require("editor.ui.ContextMenu").new(app.uiRoot)
                popup:show(200, 100, {{label = "Item", action = function() error("Unexpected menu action") end}})
            end
            local before = #actions
            for _, index in ipairs({1, 2, 2, 3}) do
                local button = app.menuBar.windowControls:buttons(love.graphics.getWidth())[index]
                if modal then app:mousepressed(button.x + 20, 16, 1)
                else assert(app.uiRoot:mousepressed(button.x + 20, 16, 1)) end
                Assert.equal(popup, app.uiRoot.popup)
            end
            Assert.equal("minimize", actions[before + 1]); Assert.equal("maximize", actions[before + 2])
            Assert.equal("restore", actions[before + 3]); Assert.equal("close", actions[before + 4])
            app.uiRoot:dismissPopup()
        end
    end)
    frame.active = active
    love.window.minimize, love.window.maximize, love.window.restore, love.window.isMaximized, love.event.quit = minimize, maximize, restore, isMaximized, quit
    assert(ok, err)
end)
return tests
