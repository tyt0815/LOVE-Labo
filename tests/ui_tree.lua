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

return tests
