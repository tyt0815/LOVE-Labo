local Assert = require("tests.assert")
local Scene = require("editor.scene_view")
local Level = require("editor.level")
local Gizmo = require("editor.translation_gizmo")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function scene(x, y)
    local level = Level.new()
    local object = level:addLObject(x or 0, y or 0)
    local view = Scene.new(32, level)
    view:setViewport(100, 80, 600, 400)
    view.selectedLObject = object
    return view, object
end
local function grab(view, axis)
    local handles = Gizmo.handles(view)
    if axis == "free" then view:mousepressed(handles.free.x + 8, handles.free.y + 8, 1)
    elseif axis == "x" then view:mousepressed(handles.x + 45, handles.y, 1)
    else view:mousepressed(handles.x, handles.y - 45, 1) end
end

add("Gizmo axes constrain movement and its square permits free movement", function()
    for _, axis in ipairs({"x", "y", "free"}) do
        local view, object = scene(20, 30)
        grab(view, axis)
        Assert.equal(axis, view.drag.axis)
        view:mousemoved(0, 0, 12, -18)
        Assert.equal(axis == "y" and 20 or 32, object.transform.x)
        Assert.equal(axis == "x" and 30 or 12, object.transform.y)
        view:mousereleased(0, 0, 1)
        Assert.equal(nil, view.drag)
    end
end)

add("Object clicks select without dragging and gizmo handles keep their screen size", function()
    local view, object = scene()
    view.selectedLObject = nil
    local x, y = view:worldToScreen(0, 0)
    view:mousepressed(x, y, 1)
    view:mousemoved(x + 50, y + 50, 50, 50)
    Assert.equal(object, view.selectedLObject)
    Assert.equal(false, view.isDraggingLObject)
    Assert.equal(0, object.transform.x)
    for _, zoom in ipairs({0.25, 1, 4}) do
        view.zoom, view.cameraX, view.cameraY = zoom, 15, -20
        local handles = Gizmo.handles(view)
        Assert.equal(16, handles.free.w)
        Assert.equal("x", Gizmo.hit(view, handles.x + 65, handles.y))
        grab(view, "free")
        view:mousemoved(0, 0, 8, -8)
        Assert.equal(8 / zoom, object.transform.x)
        Assert.equal(-8 / zoom, object.transform.y)
        view:keypressed("escape")
        Assert.equal(0, object.transform.x)
        Assert.equal(0, object.transform.y)
    end
end)

add("Snap uses cumulative movement world units and preserves the locked axis", function()
    local view, object = scene(3, 7)
    view.zoom, view.snapEnabled, view.snapUnit = 2, true, 10
    grab(view, "x")
    for _ = 1, 8 do view:mousemoved(0, 0, 1, -2) end
    Assert.equal(10, object.transform.x)
    Assert.equal(7, object.transform.y)
    view:mousereleased(0, 0, 1)
    object.transform.x, object.transform.y = -3, -7
    grab(view, "free")
    view:mousemoved(-100, -100, -8, -8)
    Assert.equal(-10, object.transform.x)
    Assert.equal(-10, object.transform.y)
    view:keypressed("escape")
    Assert.equal(-3, object.transform.x)
    Assert.equal(-7, object.transform.y)
    view.snapEnabled, view.snapUnit = false, 0.5
    Assert.equal(1.3, view:snapValue(1.3))
    view.snapEnabled = true
    Assert.equal(1.5, view:snapValue(1.3))
    Assert.equal(-1.5, view:snapValue(-1.3))
end)

add("Snap panel consumes pointer and text input and rejects invalid units", function()
    local app = require("editor.app").new()
    local controls, view = app.snapControls, app.sceneView
    local object = app.level:addLObject(0, 0)
    view.selectedLObject = object
    local vx, vy, vw = view:getViewport()
    Assert.truthy(controls.x > vx + vw / 2)
    local check, field = controls:rects()
    app:mousepressed(check.x + 5, check.y + 5, 1)
    Assert.equal(true, view.snapEnabled)
    Assert.equal(object, view.selectedLObject)
    Assert.equal(false, view.isPanning)
    local zoom = view.zoom
    app.uiRoot:wheelmoved(check.x + 5, check.y + 5, 2)
    Assert.equal(zoom, view.zoom)
    app:mousepressed(field.x + 5, field.y + 5, 1)
    app:textinput("12.5")
    app:keypressed("return")
    Assert.equal(12.5, view.snapUnit)
    for _, invalid in ipairs({"0", "-10", "nan", "1e999"}) do
        app:mousepressed(field.x + 5, field.y + 5, 1)
        app:textinput(invalid)
        app:keypressed("return")
        Assert.equal(12.5, view.snapUnit)
    end
    app:mousepressed(field.x + 5, field.y + 5, 1)
    app:textinput("50")
    app:keypressed("escape")
    Assert.equal(12.5, view.snapUnit)
    app:mousepressed(field.x + 5, field.y + 5, 1)
    app:textinput("8")
    local sx, sy = view:worldToScreen(0, 0)
    app:mousepressed(sx, sy + 40, 1)
    Assert.equal(8, view.snapUnit)
    app.sceneView.selectedLObject = object
    app:draw()
    if os.getenv("LOVE_LABO_GIZMO_PREVIEW") then
        local canvas = love.graphics.newCanvas(love.graphics.getDimensions())
        love.graphics.push("all")
        love.graphics.setCanvas(canvas)
        app:draw()
        love.graphics.setCanvas()
        local data = canvas:newImageData()
        data:encode("png", "gizmo-preview.png")
        data:release(); canvas:release(); love.graphics.pop()
    end
    assert(app:startPlay())
    app:draw()
    Assert.equal(false, controls.visible)
    assert(app:stopPlay())
    app:draw()
    Assert.equal(true, controls.visible)
end)

add("Gizmo capture survives viewport exit and Escape restores the starting position", function()
    local app = require("editor.app").new()
    local object = app.level:addLObject(0, 0)
    app.sceneView.selectedLObject = object
    local handles = Gizmo.handles(app.sceneView)
    app:mousepressed(handles.free.x + 8, handles.free.y + 8, 1)
    Assert.equal(app.sceneWidget, app.uiRoot.captured)
    app:mousemoved(-50, -50, -100, -100)
    Assert.equal(-100, object.transform.x)
    app:keypressed("escape")
    Assert.equal(0, object.transform.x)
    Assert.equal(0, object.transform.y)
    Assert.equal(nil, app.uiRoot.captured)
    Assert.equal(nil, app.sceneView.drag)
end)
add("Snapped duplication uses world coordinates without sharing transforms", function()
    local view, object = scene(3, 7)
    view.snapEnabled, view.snapUnit, view.zoom = true, 10, 2
    local x, y = view:worldToScreen(24, -16)
    view:keypressed("d", true, x, y)
    Assert.equal(20, view.selectedLObject.transform.x)
    Assert.equal(-20, view.selectedLObject.transform.y)
    Assert.equal(3, object.transform.x)
    Assert.equal(7, object.transform.y)
end)
return tests
