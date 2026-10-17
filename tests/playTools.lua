local Assert = require("tests.Assert")
local Fs = require("editor.HostFileSystem")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function fixture()
    local project = assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "AttachedTest_PlayTools_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
    assert(project:createEntry("Assets", "lua", "Probe", {scriptKind = "script"}))
    assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/Probe.lua")), [[
local Probe = {properties = {speed = {type = "number", default = 10}, target = {type = "object", default = false}, peer = {type = "script", default = false}}}
function Probe:update(dt)
    self.owner.transform.x = self.owner.transform.x + self.speed * dt
    love.mouse.setVisible(false)
    self.keyDown = love.keyboard.isDown("a")
end
return Probe
]]))
    local app = require("editor.EditorApp").new(nil, project)
    local object = app.level:addLObject(0, 0, nil, "Probe")
    object.scripts = {{id = "probe", name = "Probe", source = project:getAssetId("Assets/Probe.lua")}}
    app.sceneView:setSelection({object}); app:recordHistory()
    return project, app, object
end
add("PIE edits live instances and Stop preserves document selection camera and history", function()
    local _, app, authored = fixture()
    local snapshot = assert(require("editor.LevelFile").encode(app.level))
    app.sceneView.cameraX = 42
    assert(app:startPlay()); assert(app:setFreeExplore(true))
    local object = app.runtimeScene.lobjects[1]
    app.sceneView:setSelection({object}); app:updateInspectorTarget()
    assert(app.inspector.classInspector:setProperty("probe.speed", 120))
    assert(app.inspector.classInspector:setProperty("$transform.x", 30))
    assert(app:update(1 / 60)); Assert.equal(32, object.runtimeObject.transform.x)
    assert(app:pausePlay()); assert(app:stepPlay()); Assert.equal(34, object.runtimeObject.transform.x)
    Assert.equal(true, app.paused); Assert.equal(true, app.freeExplore)
    assert(app:startPlay()); Assert.equal(true, app.freeExplore)
    app.sceneView.cameraX = -100
    app:draw()
    assert(app:stopPlay())
    Assert.equal(authored, app.sceneView.selectedLObject); Assert.equal(42, app.sceneView.cameraX)
    Assert.equal(snapshot, assert(require("editor.LevelFile").encode(app.level)))
    Assert.equal(0, authored.transform.x); Assert.equal(app.level, app.hierarchy.level)
end)
add("PIE selects spawned objects supports references and removes stale selection without unloading inspected scripts", function()
    local _, app = fixture()
    assert(app:startPlay()); assert(app:pausePlay())
    local first = app.runtimeScene.lobjects[1]
    local child = assert(app.runtimeWorld:addLObject({name = "Dynamic", transform = {x = 0, y = 0}}))
    child:attachTo(first.runtimeObject); app:syncRuntimeScene()
    local second = app.runtimeScene.wrappers[child]
    Assert.equal(first.authoringId, second.parentAuthoringId)
    app.sceneView:setSelection({first}); app:updateInspectorTarget()
    assert(app.inspector.classInspector:setProperty("probe.target", second.authoringId))
    assert(app.inspector.classInspector:setProperty("probe.peer", {authoringId = first.authoringId, script = "probe"}))
    Assert.equal(child, first.runtimeObject.scripts.probe.target)
    Assert.equal(first.runtimeObject.scripts.probe, first.runtimeObject.scripts.probe.peer)
    app.sceneView:setSelection({second}); app:updateInspectorTarget()
    Assert.equal(false, first.runtimeObject.scripts.probe.hasUnloaded or false)
    assert(app.runtimeWorld:removeLObject(child)); app:draw()
    Assert.equal(nil, app.sceneView.selectedLObject)
    assert(app:stopPlay())
end)
add("PIE Prefab placement and deletion change only the runtime", function()
    local project, app = fixture()
    assert(project:createEntry("Assets", "prefab", "PF_Test"))
    local bytes = assert(Fs.read(assert(project:resolveAssetFile("Assets/PF_Test.prefab"))))
    assert(app:startPlay()); assert(app:pausePlay())
    local x, y, width, height = app.sceneView:getViewport()
    assert(app:placeAssets({{reference = "Assets/PF_Test.prefab"}, {reference = "Assets/PF_Test.prefab"}}, x + width / 2, y + height / 2))
    Assert.equal(3, #app.runtimeWorld.lobjects); Assert.equal(1, #app.level.lobjects)
    assert(app.sceneView:deleteSelection()); Assert.equal(1, #app.runtimeWorld.lobjects)
    Assert.equal(bytes, Fs.read(assert(project:resolveAssetFile("Assets/PF_Test.prefab"))))
    assert(app:stopPlay())
end)
add("PIE polling and cursor requests remain isolated during exploration and restore on control and Stop", function()
    local _, app = fixture()
    local down = love.keyboard.isDown
    love.keyboard.isDown = function() return true end
    local visible = love.mouse.isVisible()
    local ok, err = pcall(function()
        assert(app:startPlay()); assert(app:setFreeExplore(true)); assert(app:update(1 / 60))
        Assert.equal(false, app.runtimeWorld.lobjects[1].scripts.probe.keyDown)
        Assert.equal(true, love.mouse.isVisible()); Assert.equal(false, love.mouse.getRelativeMode())
        assert(app:setFreeExplore(false)); assert(app:update(1 / 60))
        Assert.equal(true, app.runtimeWorld.lobjects[1].scripts.probe.keyDown)
        Assert.equal(false, love.mouse.isVisible())
        app:focus(false); Assert.equal(true, love.mouse.isVisible()); Assert.equal(true, app.freeExplore)
        assert(app:stopPlay()); Assert.equal(visible, love.mouse.isVisible())
    end)
    love.keyboard.isDown = down
    if app:isPlaying() then app:stopPlay() end
    assert(ok, err)
end)
add("Leaving game control releases held keys and retains relative mouse requests without changing game projection", function()
    local _, app = fixture()
    assert(app:startPlay())
    local world = app.runtimeWorld
    local script = world.lobjects[1].scripts.probe
    script.keypressed = function(self) self.held = true end
    script.keyreleased = function(self) self.held = false end
    local view = require("core.Rendering").createView(world, {projection = {width = 300, height = 200, transform = {x = 700, y = -200}}})
    app:keypressed("a", "a"); Assert.equal(true, script.held)
    assert(app:setFreeExplore(true)); Assert.equal(false, script.held)
    local vx, vy, width, height = app.sceneView:getViewport()
    local x, y = app.sceneView:screenToWorld(vx + width / 2, vy + height / 2)
    Assert.equal(700, x); Assert.equal(-200, y)
    app.playInput.love.mouse.setRelativeMode(true)
    Assert.equal(false, love.mouse.getRelativeMode()); Assert.equal(true, app.playInput.love.mouse.getRelativeMode())
    assert(app:setFreeExplore(false)); Assert.equal(true, love.mouse.getRelativeMode())
    assert(app:pausePlay()); Assert.equal(false, love.mouse.getRelativeMode())
    Assert.equal(700, view:getProjection().transform.x)
    assert(app:stopPlay())
end)
add("Game control cancellation never clicks a pointer region and raw release uses the current position", function()
    local _, app = fixture()
    local position = love.mouse.getPosition
    local ok, err = pcall(function()
        assert(app:startPlay())
        local world = app.runtimeWorld
        local script = world.lobjects[1].scripts.probe
        require("core.Rendering").createView(world, {})
        app:updateSceneViewport()
        local viewport = assert(app:runtimeViewport())
        local x, y = viewport:worldToScreen(0, 0)
        local mouseX, mouseY = x, y
        love.mouse.getPosition = function() return mouseX, mouseY end
        local ups, clicks, releases = 0, 0, {}
        require("core.Input").registerRegion(world, {owner = script,
            hitTest = function(_, wx, wy) return math.abs(wx) <= 4 and math.abs(wy) <= 4 end,
            onDown = function() return true end,
            onUp = function(event) ups = ups + 1; if event.inside then clicks = clicks + 1 end end})
        script.mousereleased = function(_, rx, ry) releases[#releases + 1] = {x = rx, y = ry} end
        app:mousepressed(x, y, 1); app:mousereleased(x, y, 1)
        Assert.equal(1, ups); Assert.equal(1, clicks)
        for _, mode in ipairs({"f8", "focus"}) do
            app:focus(true); assert(app:setFreeExplore(false))
            mouseX, mouseY = x, y
            app:mousepressed(x, y, 1); Assert.equal(1, app:gameCaptureButton())
            mouseX, mouseY = x + 20, y + 10
            app:mousemoved(mouseX, mouseY, 20, 10)
            if mode == "f8" then app:keypressed("f8") else app:focus(false) end
            Assert.equal(1, ups); Assert.equal(1, clicks)
            Assert.equal(nil, app:gameCaptureButton())
            Assert.equal(nil, next(world.pointerCaptures))
            Assert.equal(nil, world.eventCaptures)
            local release = releases[#releases]
            Assert.equal(mouseX - viewport.x, release.x)
            Assert.equal(mouseY - viewport.y, release.y)
        end
        -- 영역 안에 머물러 있어도 소유권 해제는 일반 클릭 해제가 아니다.
        app:focus(true); assert(app:setFreeExplore(false))
        mouseX, mouseY = x, y
        app:mousepressed(x, y, 1); assert(app:pausePlay())
        Assert.equal(1, ups); Assert.equal(1, clicks)
    end)
    love.mouse.getPosition = position
    if app:isPlaying() then app:stopPlay() end
    assert(ok, err)
end)
return tests
