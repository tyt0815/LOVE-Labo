local Assert = require("tests.Assert")
local Fs = require("editor.HostFileSystem")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function fixture()
    local project = assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "DebugTest_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
    assert(project:createEntry("Assets", "lua", "DebugExample", {scriptKind = "script"}))
    assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/DebugExample.lua")), [[local DebugExample = {}
function DebugExample.beginPlay(self)
    self.owner.world.debug:log("Started", {color = {10, 20, 30}})
    self.owner.world.debug:screenLog("Ready", {key = "state", lifespan = 1})
end
function DebugExample.update(self)
    self.owner.world.debug:log("Updated")
    self.owner.world.debug:screenLog("Running", {key = "state", lifespan = 1})
    self.owner.world.debug:line(0, 0, 100, 100, {lifespan = 1})
end
function DebugExample.drawEditor(self, context)
    self.editorDrawn = true
    context:rect(0, 0, 80, 40, {color = {0, 120, 255}})
end
return DebugExample
]]))
    assert(project:rebuildAssetIndex())
    local level = require("editor.Level").new()
    level:addLObject(0, 0).scripts = {{id = "example", source = project:getAssetId("Assets/DebugExample.lua")}}
    return project, level
end
add("Debug queues replace keyed screen messages, expire after presentation, and validate RGB", function()
    local session = require("editor.DebugSession").new()
    session:screenLog("one", {key = 1}); session:screenLog("two", {key = 2}); session:screenLog("three", {key = 1})
    Assert.equal(2, #session.screens); Assert.equal("three", session.screens[1].text); Assert.equal("two", session.screens[2].text)
    session:screenLog("frame", {lifespan = 0}); session:point(10, 20, 3, {lifespan = 0})
    session:update(10); Assert.equal(3, #session.screens); Assert.equal(1, #session.shapes)
    session:finishFrame(); Assert.equal(2, #session.screens); Assert.equal(0, #session.shapes)
    session:update(0); Assert.equal(0, #session.screens)
    session:log("kept"); session:update(100); Assert.equal("kept", session.history[1].text)
    Assert.equal(false, pcall(session.screenLog, session, "bad", {color = {256, 0, 0}}))
    Assert.equal(false, pcall(session.line, session, 0, 0, nil, 1))
end)
add("Debug injection reaches beginPlay and level transitions while standalone Worlds are no-op", function()
    local project, level = fixture()
    local normal = assert(require("runtime.WorldLoader").create(project, level:toData()))
    Assert.equal(require("core.Debug"), normal.debug); assert(normal:update(0))
    local session = require("editor.DebugSession").new()
    local world = assert(require("runtime.WorldLoader").create(project, level:toData(), session))
    Assert.equal("Started", session.history[1].text); assert(world:update(0)); Assert.equal("Updated", session.history[2].text)
    assert(project:createEntry("Assets", "level", "L_Next", {empty = true}))
    assert(Fs.writeAtomic(assert(project:resolveAssetFile("Assets/L_Next.level")), assert(require("project.Json").encode(level:toData()))))
    assert(world:openLevel("Assets/L_Next.level")); local candidate = assert(world:takeLevelTransition())
    Assert.equal(session, candidate.debug); Assert.equal("Started", session.history[3].text)
end)
add("Editor log panel scrolls independently and editing draws callbacks without beginPlay", function()
    local project, level = fixture()
    local app = require("editor.EditorApp").new(nil, project); app.level = level; app.sceneView.level = level
    app:draw(); Assert.equal(0, #app.debugSession.history); Assert.equal(nil, app.spriteAssets.error)
    local browserY, inspectorHeight = app.assetBrowser.y, app.inspector.height
    local buttonY = app.statusWidget:summaryY()
    assert(app:keypressed("`")); Assert.truthy(app.statusWidget.expanded)
    Assert.equal(browserY, app.assetBrowser.y); Assert.equal(inspectorHeight, app.inspector.height)
    Assert.equal(buttonY, app.statusWidget:summaryY()); Assert.equal(36, app.statusHeight)
    Assert.truthy(app.statusWidget.y < app.assetBrowser.y + app.assetBrowser.height)
    for i = 1, 40 do app.debugSession:log("Log " .. i) end
    app:draw(); local scroll = app.statusWidget.scroll
    Assert.truthy(scroll > 0)
    app.statusWidget:dispatch("wheelmoved", 10, app.statusWidget.y + 30, 1)
    Assert.truthy(app.statusWidget.scroll < scroll)
    assert(app:startPlay()); app:draw(); Assert.equal("Started", app.debugSession.history[#app.debugSession.history].text)
    app.runtimeWorld.debug:circle(0, 0, 20); app.runtimeWorld.debug:rect(-50, -50, 100, 100); app:draw(); assert(app:stopPlay())
    Assert.equal(0, #app.debugSession.shapes)
end)
add("Simulation debug option uses the editor service and exports exclude its implementation", function()
    local project, level = fixture()
    local request = require("editor.Cli").parse({"--cli", "level", "simulate", "--debug", "--frames", "2"})
    local result = require("editor.CliSimulation").execute(project, level, request)
    Assert.equal(3, #result.debug.history); Assert.equal(1, #result.debug.screens); Assert.equal("Running", result.debug.screens[1].text)
    Assert.equal(2, #result.debug.shapes)
    assert(project:createEntry("Assets", "level", "L_Debug", {empty = true}))
    assert(Fs.writeAtomic(assert(project:resolveAssetFile("Assets/L_Debug.level")), assert(require("project.Json").encode(level:toData()))))
    request.project, request.level = project.rootPath, "Assets/L_Debug.level"
    Assert.equal(3, #require("editor.Cli").execute(request).debug.history)
    Assert.equal(nil, require("editor.CliSimulation").execute(project, level, {frames = 1}).debug)
    local output = Fs.join(project.rootPath, "Game.love"); assert(require("editor.Export").write(project, level, output))
    local bytes = assert(Fs.read(output))
    Assert.truthy(bytes:find("core/Debug.lua", 1, true)); Assert.equal(nil, bytes:find("editor/DebugSession.lua", 1, true))
    Assert.equal(false, pcall(require("core.Script").extend, require("core.Script"), {properties = {drawEditor = {type = "number", default = 1}}}))
end)
add("Area scripts expose editor outlines and Game View never invokes editor callbacks", function()
    local p, level = fixture(); assert(require("editor.PluginOperations").apply(p, "LaboEssentials", true, true))
    local world = assert(require("core.World").new())
    local object = assert(world:addLObject({transform = {x = 100, y = 50, rotation = 90, scaleX = 2, scaleY = 2}}))
    local rect = assert(object:addScript("area", p.plugins:loadScript("RectBounds"), {width = 20, height = 10}))
    local pointer = assert(object:addScript("pointer", p.plugins:loadScript("Pointer"), {boundsSource = "area"}))
    local context = require("editor.DebugSession").new()
    rect:drawEditor(context); pointer:drawEditor(context)
    Assert.equal(2, #context.shapes)
    for index, value in ipairs(context.shapes[1].points) do Assert.equal(value, context.shapes[2].points[index]) end
    Assert.truthy(math.abs(context.shapes[1].points[1] - 110) < 0.001)
    Assert.truthy(math.abs(context.shapes[1].points[2] - 30) < 0.001)
    Assert.truthy(p.plugins:loadScript("Canvas").drawEditor); Assert.truthy(p.plugins:loadScript("Sprite").drawEditor)
    local app = require("editor.EditorApp").new(nil, p); app.level, app.sceneView.level = level, level
    app:draw(); Assert.equal(true, app.spriteAssets:preview(level.lobjects[1]).scripts.example.editorDrawn)
    assert(app:startPlay()); app:draw(); Assert.equal(nil, app.runtimeWorld.lobjects[1].scripts.example.editorDrawn)
    assert(app:stopPlay())
end)
add("Collapsed log keeps the latest line after time passes", function()
    local p = fixture(); local app = require("editor.EditorApp").new(nil, p)
    app.debugSession:log("Persistent latest"); app.debugSession:update(100); app:draw()
    local Ui, seen = require("editor.Ui"), false
    local original = Ui.text
    Ui.text = function(text, ...) if text == "Persistent latest" then seen = true end; return original(text, ...) end
    local ok, err = pcall(app.statusWidget.render, app.statusWidget); Ui.text = original
    assert(ok, err); Assert.truthy(seen)
end)
return tests
