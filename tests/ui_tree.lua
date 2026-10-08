local Assert = require("tests.assert")
local Widget = require("editor.ui.widget")
local Canvas = require("editor.ui.canvas")
local Root = require("editor.ui.root")
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

add("UI input respects z order visibility clipping and consumption", function()
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

add("UI capture continues drag outside bounds and routes text to focus", function()
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

add("UI unhandled input bubbles to parent and popup dismissal blocks underlying clicks", function()
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
    local Menu = require("editor.ui.context_menu")
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
    root:keypressed("return")
    Assert.equal(0, selected)
    Assert.equal(menu, root.popup)
    root:keypressed("down")
    root:keypressed("return")
    Assert.equal(1, selected)
    Assert.equal(nil, root.popup)
    menu:show(20, 20, { { label = "Delete", action = function() selected = selected + 10 end } })
    root:keypressed("right")
    Assert.equal(1, selected)
    root:keypressed("escape")
    Assert.equal(nil, root.popup)
end)

add("popup blocks background pointer input and receives dialog text", function()
    local canvas, moves = Canvas.new(), 0
    canvas.handlers.mousemoved = function() moves = moves + 1; return true end
    canvas:setBounds(0, 0, 500, 500)
    local root = Root.new(canvas)
    local menu = require("editor.ui.context_menu").new(root)
    menu:show(10, 10, { { label = "New" } })
    root:mousemoved(450, 450, 1, 1)
    Assert.equal(0, moves)
    local value
    local dialog = require("editor.ui.dialog").new(root, { input = true, title = "New",
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

return tests
