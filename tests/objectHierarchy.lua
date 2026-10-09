local Assert = require("tests.Assert")
local Level = require("editor.Level")
local Scene = require("editor.SceneView")
local Transform = require("core.Transform")
local World = require("core.World")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function near(expected, actual) Assert.truthy(math.abs(expected - actual) < 0.00001, tostring(actual) .. " ~= " .. expected) end
add("Object reparent keeps world position and inherits parent rotation and scale", function()
    local level = Level.new()
    local parent, child = level:addLObject(100, 50), level:addLObject(110, 70)
    parent.transform.rotation, parent.transform.scaleX, parent.transform.scaleY = 90, 2, 3
    assert(level:reparent({child}, parent))
    near(10, child.transform.x); near(-10 / 3, child.transform.y)
    local world = level:getWorldTransform(child); near(110, world.x); near(70, world.y)
    parent.transform.x = 200
    world = level:getWorldTransform(child); near(210, world.x)
    assert(level:reparent({child}, nil)); near(210, child.transform.x); near(70, child.transform.y)
end)
add("Object cycles and singular parents reject an entire reparent batch", function()
    local level = Level.new()
    local parent, child, other = level:addLObject(0, 0), level:addLObject(10, 0), level:addLObject(20, 0)
    assert(level:reparent({child}, parent))
    Assert.equal(false, level:reparent({other, parent}, child))
    Assert.equal(nil, other.parentAuthoringId)
    parent.transform.rotationY = 90
    Assert.equal(false, level:reparent({other}, parent))
    Assert.equal(nil, other.parentAuthoringId)
end)
add("Object hierarchy and names round trip with old flat levels supported", function()
    local level = Level.new()
    local root = level:addLObject(30, 40, nil, "PF_Enemy")
    local child = level:addLObject(0, 0, nil, "PF_Enemy")
    assert(level:reparent({child}, root))
    local decoded = assert(Level.fromData(level:toData()))
    Assert.equal("PF_Enemy 1", decoded.lobjects[1].name)
    Assert.equal("PF_Enemy 2", decoded.lobjects[2].name)
    Assert.equal(root.authoringId, decoded.lobjects[2].parentAuthoringId)
    Assert.equal(1, decoded:treeRows()[2].depth)
    Assert.equal(1, #decoded:treeRows({[root.authoringId] = true}))
    local data = level:toData(); data.lobjects[1].parentAuthoringId = child.authoringId
    Assert.equal(nil, Level.fromData(data)); Assert.equal(nil, World.fromLevelData(data))
    data.lobjects[1].parentAuthoringId = 99
    Assert.equal(nil, Level.fromData(data)); Assert.equal(nil, World.fromLevelData(data))
    Assert.truthy(Level.fromData({formatVersion = 1, lobjects = {}}))
end)
add("Runtime root and descendant component follow object parents", function()
    local level = Level.new()
    local root, child = level:addLObject(100, 20), level:addLObject(110, 30)
    assert(level:reparent({child}, root))
    local world = assert(World.fromLevelData(level:toData()))
    local a, b = world.lobjects[1], world.lobjects[2]
    local component = b:addComponent("child", require("core.SceneComponent"), {x = 5, y = 0})
    Assert.equal(a, b.parent); Assert.equal(b, a.children[1])
    near(115, component:getWorldTransform().x)
    a.transform.rotation = 90
    near(90, b:getWorldTransform().x); near(30, b:getWorldTransform().y)
    Assert.equal(false, pcall(a.attachTo, a, b))
end)
add("Multi duplicate copies each selected subtree once and delete includes descendants", function()
    local level = Level.new()
    local root, child, grandchild, other = level:addLObject(1, 2, nil, "PF_Test"), level:addLObject(3, 4), level:addLObject(5, 6), level:addLObject(7, 8)
    assert(level:reparent({child}, root)); assert(level:reparent({grandchild}, child))
    child.propertyOverrides = {health = 5}
    local clones = level:duplicateLObjects({root, child})
    Assert.equal(3, #clones); Assert.equal(clones[1].authoringId, clones[2].parentAuthoringId)
    Assert.equal(clones[2].authoringId, clones[3].parentAuthoringId)
    clones[2].propertyOverrides.health = 10; Assert.equal(5, child.propertyOverrides.health)
    assert(level:removeLObjects({root, child})); Assert.equal(4, #level.lobjects); Assert.equal(other, level.lobjects[1])
end)
add("Viewport marquee and Ctrl toggling share an ordered multi selection", function()
    local level = Level.new(); local a, b, c = level:addLObject(-40, 0), level:addLObject(40, 0), level:addLObject(150, 0)
    local scene = Scene.new(nil, level); scene:setViewport(0, 0, 600, 400)
    scene:mousepressed(200, 150, 1); scene:mousemoved(400, 250, 200, 100); scene:mousereleased(400, 250, 1)
    Assert.equal(2, #scene:getSelection()); Assert.truthy(scene:isSelected(a)); Assert.truthy(scene:isSelected(b)); Assert.equal(false, scene:isSelected(c))
    scene:selectLObject(a, true); Assert.equal(1, #scene:getSelection()); scene:selectLObject(c, true); Assert.equal(2, #scene:getSelection())
end)
add("Multi gizmo moves selected ancestors once and restores the whole drag", function()
    local level = Level.new(); local a, b, c = level:addLObject(100, 50), level:addLObject(120, 70), level:addLObject(200, 50)
    assert(level:reparent({b}, a)); a.transform.rotation = 90
    local scene = Scene.new(nil, level); scene:setViewport(0, 0, 800, 600); scene:setSelection({a, b, c})
    local handles = require("editor.TransformGizmo").handles(scene)
    scene:mousepressed(handles.x + 40, handles.y, 1)
    scene:mousemoved(handles.x + 50, handles.y + 20, 10, 20)
    near(110, a.transform.x); near(210, c.transform.x); near(20, b.transform.x)
    scene:mousemoved(handles.x + 60, handles.y + 50, 10, 30)
    near(120, a.transform.x); near(220, c.transform.x); near(50, a.transform.y)
    scene:keypressed("escape"); near(100, a.transform.x); near(200, c.transform.x); near(20, b.transform.x)
end)
add("Parented primary gizmo converts world movement back into local coordinates", function()
    local level = Level.new(); local a, b = level:addLObject(100, 50), level:addLObject(120, 70)
    assert(level:reparent({b}, a)); a.transform.rotation = 90
    local scene = Scene.new(nil, level); scene:setViewport(0, 0, 800, 600); scene:setSelection({b})
    local h = require("editor.TransformGizmo").handles(scene)
    scene:mousepressed(h.x + 40, h.y, 1); scene:mousemoved(h.x + 50, h.y + 50, 10, 50)
    near(20, b.transform.x); near(10, b.transform.y)
    scene:mousemoved(h.x + 60, h.y + 80, 10, 30)
    near(20, b.transform.x); near(0, b.transform.y)
end)
add("Hierarchy rectangle selection reparent drag and fractional scrolling work", function()
    local level = Level.new(); local a, b, c = level:addLObject(0, 0), level:addLObject(10, 0), level:addLObject(20, 0)
    local view = Scene.new(nil, level); local tree = require("editor.Hierarchy").new(level); tree.sceneView, tree.height = view, 400
    tree:mousepressed(280, 160, 1); tree:mousemoved(20, 45); tree:mousereleased(20, 45, 1)
    Assert.equal(3, #view:getSelection())
    view:setSelection({b, c}); tree:mousepressed(80, 80, 1); tree:mousemoved(80, 50); tree:mousereleased(80, 50, 1)
    Assert.equal(a.authoringId, b.parentAuthoringId); Assert.equal(a.authoringId, c.parentAuthoringId)
    for i = 1, 30 do level:addLObject(i, 0) end
    tree:wheelmoved(-0.1); Assert.equal(0, tree.scroll % 1)
end)
add("Level API queues switches without changing the current update snapshot", function()
    local Json = require("project.Json")
    local map = {["Assets/L_Two.level"] = assert(Json.encode({formatVersion = 2, lobjects = {{authoringId = 1, transform = {x = 5, y = 6}}}}))}
    local project = {getAssetReference = function(_, ref) return ref end, getAssetId = function() end, readAsset = function(_, ref) return map[ref], "missing" end}
    local world = assert(require("runtime.WorldLoader").create(project, {lobjects = {}}))
    Assert.truthy(require("Engine").openLevel(world, "Assets/L_Two.level"))
    Assert.equal(0, #world.lobjects); Assert.equal(false, world:openLevel("Assets/L_Two.level"))
    local nextWorld = assert(world:takeLevelTransition()); Assert.equal(1, #nextWorld.lobjects); Assert.equal(5, nextWorld.lobjects[1].transform.x)
    Assert.equal("Assets/L_Two.level", nextWorld.levelReference); Assert.equal(nil, world:takeLevelTransition())
    Assert.equal(false, nextWorld:openLevel("Assets/No.level")); Assert.equal(1, #nextWorld.lobjects)
    Assert.equal(false, nextWorld:openLevel("Assets/Bad.prefab"))
end)
add("Failed destination beginPlay retains current World and reports a transition error", function()
    local Json = require("project.Json")
    local project = {
        getAssetReference = function(_, ref) return ref end, getAssetId = function() end,
        readAsset = function() return assert(Json.encode({formatVersion = 2, lobjects = {}, scriptReference = "Sources/Fail.lua"})) end,
        getScriptKind = function() return "level" end, resolveSourceFile = function() return "Sources/Fail.lua" end,
        readSource = function() return "return {beginPlay = function() error('destination failed') end}" end
    }
    local world = assert(require("runtime.WorldLoader").create(project, {lobjects = {}}))
    assert(world:openLevel("Assets/Fail.level"))
    local candidate, err = world:takeLevelTransition(); Assert.equal(nil, candidate); Assert.truthy(err:find("destination failed", 1, true)); Assert.equal(err, world.levelTransitionError)
    Assert.equal(0, #world.lobjects); Assert.truthy(world:update(0.1)); Assert.equal(nil, world.pendingLevel)
end)
add("Hierarchy Shift selection handles equal endpoints and both range directions", function()
    local level = Level.new()
    local a, b, c = level:addLObject(0, 0), level:addLObject(10, 0), level:addLObject(20, 0)
    local view = Scene.new(nil, level)
    local tree = require("editor.Hierarchy").new(level); tree.sceneView, tree.height = view, 400
    local original = love.keyboard.isDown
    love.keyboard.isDown = function(key) return key == "lshift" end
    local ok, err = pcall(function()
        tree.anchor = b; view:setSelection({a, b, c})
        tree:mousepressed(100, 80, 1)
        Assert.equal(1, #view:getSelection()); Assert.equal(b, view.selectedLObject)
        tree:mousereleased(100, 80, 1)
        tree.anchor = a; tree:mousepressed(100, 104, 1)
        Assert.equal(3, #view:getSelection()); Assert.truthy(view:isSelected(a)); Assert.truthy(view:isSelected(c))
        tree:mousereleased(100, 104, 1)
        tree.anchor = c; tree:mousepressed(100, 56, 1)
        Assert.equal(3, #view:getSelection()); Assert.truthy(view:isSelected(a)); Assert.truthy(view:isSelected(c))
    end)
    love.keyboard.isDown = original
    assert(ok, err)
end)
add("Single child framing uses world position for direct F and selected paths", function()
    local level = Level.new()
    local parent, child = level:addLObject(100, 50), level:addLObject(0, 0)
    child.parentAuthoringId = parent.authoringId
    child.transform.x, child.transform.y = 20, 20
    local view = Scene.new(nil, level); view:setViewport(30, 40, 600, 400); view.zoom = 2
    view:setSelection({child})
    for _, frame in ipairs({function() assert(view:frameLObject(child)) end, function() assert(view:frameSelected()) end, function() view:keypressed("f", false) end}) do
        view.cameraX, view.cameraY = 0, 0; frame()
        near(-240, view.cameraX); near(-140, view.cameraY)
        local x, y = view:worldToScreen(120, 70); near(330, x); near(240, y)
    end
    parent.transform.rotation, parent.transform.scaleX, parent.transform.scaleY = 90, 2, 3
    assert(view:frameLObject(child)); near(-80, view.cameraX); near(-180, view.cameraY)
end)

return tests
