local Assert = require("tests.Assert")
local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function fixture()
    return assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "AttachedTest_Review_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
end
local function sameGraphics(callback)
    love.graphics.push("all")
    love.graphics.translate(7, 9); love.graphics.setColor(0.25, 0.5, 0.75, 1); love.graphics.setScissor(1, 2, 30, 40)
    local depth, canvas = love.graphics.getStackDepth(), love.graphics.getCanvas()
    local x, y = love.graphics.transformPoint(0, 0)
    local called, err = pcall(function()
        callback()
        Assert.equal(depth, love.graphics.getStackDepth()); Assert.equal(canvas, love.graphics.getCanvas())
        local ax, ay = love.graphics.transformPoint(0, 0)
        Assert.equal(x, ax); Assert.equal(y, ay)
        local r, g, b = love.graphics.getColor()
        Assert.equal(0.25, r); Assert.equal(0.5, g); Assert.equal(0.75, b)
        local sx, sy, sw, sh = love.graphics.getScissor()
        Assert.equal(1, sx); Assert.equal(2, sy); Assert.equal(30, sw); Assert.equal(40, sh)
    end)
    while love.graphics.getStackDepth() >= depth do love.graphics.pop() end
    assert(called, err)
end
add("Game Preview and screen scopes recover nested user pushes on success false and exception", function()
    for _, mode in ipairs({"success", "false", "error"}) do
        local world = require("core.World").new()
        local object = assert(world:addLObject({transform = {x = 0, y = 0}}))
        local script = require("core.ScriptRuntime").attach(object, "draw", require("core.Script"):extend({draw = function()
            love.graphics.push("all"); love.graphics.translate(100, 100); love.graphics.setScissor(); love.graphics.setColor(1, 0, 0, 1)
            if mode == "error" then error("nested draw failure") end
            if mode == "false" then return false, "nested draw failure" end
        end}))
        require("core.Rendering").createView(world, {})
        local game = require("editor.GameView").new(); game:setViewport(0, 0, 100, 100)
        sameGraphics(function() Assert.equal(mode == "success", pcall(game.draw, game, world)) end)
        local preview = setmetatable({world = world, objects = world.lobjects, images = {}, background = {0, 0, 0}}, require("editor.Preview"))
        sameGraphics(function()
            local ok, err = preview:draw({x = 0, y = 0, w = 100, h = 100})
            Assert.equal(mode == "success", ok)
            if mode ~= "success" then Assert.truthy(err:find("nested draw failure", 1, true)) end
        end)
        local canvas = love.graphics.newCanvas(16, 16)
        sameGraphics(function()
            local ok = pcall(require("core.Rendering").withScreen, {viewport = {x = 3, y = 4}}, function()
                love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.translate(20, 30)
                if mode == "error" then error("nested screen failure") end
            end)
            Assert.equal(mode ~= "error", ok)
        end)
        script.draw = function() love.graphics.push("all"); error("PNG draw failure") end
        sameGraphics(function()
            local ok, err = preview:png(Fs.join(fixture().rootPath, "failed.png"), 16)
            Assert.equal(false, ok); Assert.truthy(err:find("PNG draw failure", 1, true))
        end)
        preview:release(); canvas:release()
    end
end)
add("Unbalanced successful draw cannot shift the next script", function()
    local world = require("core.World").new()
    local first = assert(world:addLObject({transform = {x = 0, y = 0}}))
    local second = assert(world:addLObject({transform = {x = 10, y = 20}}))
    local x, y
    require("core.ScriptRuntime").attach(first, "first", require("core.Script"):extend({draw = function()
        love.graphics.push("all"); love.graphics.translate(300, 400)
    end}))
    require("core.ScriptRuntime").attach(second, "second", require("core.Script"):extend({draw = function()
        x, y = love.graphics.transformPoint(0, 0)
    end}))
    sameGraphics(function()
        require("core.Renderer").drawObjects(world.lobjects, function() end, function(wx, wy) return wx, wy end, 1)
    end)
    Assert.equal(10, x); Assert.equal(20, y); assert(world:dispose())
end)
add("Editor click picking framing and drag errors preserve selection document and capture", function()
    local project = fixture()
    assert(project:createEntry("Assets", "lua", "Hit", {scriptKind = "script"}))
    local path = assert(project:resolveSourceFile("Assets/Hit.lua"))
    assert(Fs.writeAtomic(path, 'return {draw = function() end, hitTest = function() error("broken hit") end}'))
    local app = require("editor.EditorApp").new(nil, project)
    local object = app.level:addLObject(0, 0)
    object.scripts = {{id = "hit", source = project:getAssetId("Assets/Hit.lua")}}
    local selected = app.level:addLObject(300, 200)
    app.sceneView:setSelection({selected}); app:updateInspectorTarget(); app:draw()
    local before = assert(require("editor.LevelFile").encode(app.level))
    local x, y = app.sceneView:worldToScreen(0, 0)
    app:mousepressed(x, y, 1)
    Assert.equal(selected, app.sceneView.selectedLObject)
    Assert.equal(nil, app.uiRoot.captured); Assert.truthy(app.hierarchy.error:find("broken hit", 1, true))
    Assert.equal(before, require("editor.LevelFile").encode(app.level))
    app.sceneView.onContextMenu = nil
    app:mousepressed(x, y, 2)
    -- 스포이드도 같은 보호 경계를 사용한다.
    local picked, err = app.sceneView:interact("findLObjectAtWorldPosition", 0, 0)
    Assert.equal(nil, picked); Assert.truthy(err:find("broken hit", 1, true))
    local transform = app.level.getWorldTransform
    app.level.getWorldTransform = function() error("broken layout") end
    Assert.equal(nil, app.sceneView:interact("frameSelected"))
    app.level.getWorldTransform = transform
    local view = app.sceneView
    view:setSelection({selected})
    local handles = require("editor.TransformGizmo").handles(view)
    app:mousepressed(handles.x + 40, handles.y, 1)
    Assert.truthy(view.drag)
    app.level.setWorldPosition = function() error("broken inverse") end
    app:mousemoved(handles.x + 50, handles.y, 10, 0)
    app.level.setWorldPosition = nil
    Assert.equal(300, selected.transform.x); Assert.equal(200, selected.transform.y)
    Assert.equal(nil, view.drag); Assert.equal(nil, app.uiRoot.captured)
    Assert.equal(before, require("editor.LevelFile").encode(app.level))
    assert(Fs.writeAtomic(path, 'return {draw = function() end, hitTest = function() return true end}'))
    assert(app:refreshProject(false))
    app:mousepressed(x, y, 1); app:mousereleased(x, y, 1)
    Assert.equal(object, app.sceneView.selectedLObject)
end)
local function prefabLayout(project, provided)
    assert(require("editor.PluginOperations").apply(project, "LaboEssentials", true, true))
    assert(project:createEntry("Assets", "lua", "Layout", {scriptKind = "script"}))
    assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/Layout.lua")), [[local Engine = require("Engine")
local Layout = {properties = {anchor = {type = "string", default = "right"}}}
function Layout:configure()
    Engine.Transform.bindLocal(self.owner, {owner = self, resolve = function(value)
        local t = assert(Engine.Transform.copy(value)); local _, _, w = Engine.Bounds.parent(self.owner)
        t.x = t.x + (w or 0) / 2; return t
    end, unresolve = function(value)
        local t = assert(Engine.Transform.copy(self.owner.transform)); local _, _, w = Engine.Bounds.parent(self.owner)
        t.x, t.y = value.x - (w or 0) / 2, value.y; return t
    end})
end
return Layout]]))
    assert(project:createEntry("Assets", "prefab", "PF_Layout"))
    local doc = assert(require("editor.PrefabDocument").load(project, "Assets/PF_Layout.prefab"))
    project.draftAssets = {[doc.assetId] = doc}
    doc.data.scripts = {{id = "bounds", source = "RectBounds"}}
    doc.data.overrides = {scripts = {bounds = {width = 1000, height = 1000}}}
    doc.data.children = {
        {id = "item", name = "Item", transform = {x = 10, y = 20}, scripts = {{id = "layout", source = provided and "RectLayout" or project:getAssetId("Assets/Layout.lua")}},
            overrides = {scripts = {layout = {anchor = "right"}}}},
        {id = "group", name = "Group", transform = {x = 100, y = 0}, scripts = {{id = "bounds", source = "RectBounds"}},
            overrides = {scripts = {bounds = {width = 200, height = 200}}}}
    }
    return doc, require("editor.PrefabEditor").new(project, doc, function() end, function() end)
end
local function itemPosition(project, doc)
    local world = assert(require("runtime.WorldLoader").prepare(project, {lobjects = {
        {authoringId = 1, transform = {x = 0, y = 0}, definitionReference = doc.assetId}}}))
    local x, y
    for _, object in ipairs(world.lobjects) do if object.name == "Item" then local t = object:getWorldTransform(); x, y = t.x, t.y end end
    assert(world:dispose()); return x, y
end
add("Prefab GUI and CLI preserve provided and custom layout positions through parent changes", function()
    for _, provided in ipairs({true, false}) do
        local project = fixture()
        local doc, editor = prefabLayout(project, provided)
        for _, action in ipairs({{"root/item", "root/group", "attach"}, {"root/group/item", "root", "detach"},
            {"root/item", "root/group", "after"}, {"root/item", "root/group", "before"}}) do
            local x, y = itemPosition(project, doc)
            Assert.equal(510, x); Assert.equal(20, y)
            assert(editor:dropObject(unpack(action)))
            local ax, ay = itemPosition(project, doc); Assert.equal(x, ax); Assert.equal(y, ay)
        end
        assert(doc:save(project)); project.draftAssets = nil
        local Cli = require("editor.Cli")
        Cli.execute({command = "prefab.child.move", project = project.rootPath, prefab = doc.assetId,
            node = "root/item", destination = "root/group", mode = "attach"})
        doc = assert(require("editor.PrefabDocument").load(project, doc.assetId))
        local x, y = itemPosition(project, doc); Assert.equal(510, x); Assert.equal(20, y)
    end
end)
add("Failed Prefab and Level inverse layout changes restore the entire edit", function()
    local project = fixture()
    local doc, editor = prefabLayout(project, false)
    local source = project:getAssetId("Assets/Layout.lua")
    local path = project:resolveSourceFile(source)
    local bytes = assert(Fs.read(path)):gsub('unresolve = function%(value%)', 'unresolve = function(value) error("inverse failed");', 1)
    assert(Fs.writeAtomic(path, bytes))
    local before = assert(Json.encode(doc.data)); local selected = editor.selected
    local ok, err = editor:dropObject("root/item", "root/group", "attach")
    Assert.equal(false, ok); Assert.truthy(err:find("inverse failed", 1, true))
    Assert.equal(before, Json.encode(doc.data)); Assert.equal(selected, editor.selected)
    -- 같은 부모 안의 순서 변경에는 위치 역변환이 필요하지 않다.
    assert(editor:dropObject("root/item", "root/group", "after"))
    local level = require("editor.Level").new()
    local a, b, parent = level:addLObject(10, 20), level:addLObject(30, 40), level:addLObject(100, 0)
    local set = level.setWorldPosition
    level.setWorldPosition = function(self, object, x, y)
        if object == b then error("second inverse failed") end
        return set(self, object, x, y)
    end
    before = assert(require("editor.LevelFile").encode(level))
    ok, err = level:reparent({a, b}, parent)
    Assert.equal(false, ok); Assert.truthy(err:find("second inverse failed", 1, true))
    Assert.equal(nil, a.parentAuthoringId); Assert.equal(10, a.transform.x)
    Assert.equal(before, require("editor.LevelFile").encode(level))
end)
add("Prefab root promotion preserves effective relative positions", function()
    local project = fixture()
    local doc, editor = prefabLayout(project, true)
    local beforeX, beforeY = itemPosition(project, doc)
    assert(editor:dropObject("root/item", "root", "before"))
    local world = assert(require("runtime.WorldLoader").prepare(project, {lobjects = {
        {authoringId = 1, transform = {x = 0, y = 0}, definitionReference = doc.assetId}}}))
    Assert.equal("Item", doc.data.name)
    local group
    for _, object in ipairs(world.lobjects) do if object.name == "Group" then group = object end end
    local t = group:getWorldTransform()
    Assert.equal(100 - beforeX, t.x); Assert.equal(-beforeY, t.y)
    assert(world:dispose())
end)
add("Asset repair and ordinary deletion refuse incomplete usage scans and allow retry", function()
    local project = fixture()
    assert(project:createEntry("Assets", "lua", "Missing", {scriptKind = "script"}))
    assert(project:createEntry("Assets", "prefab", "PF_Use"))
    local id = project:getAssetId("Assets/Missing.lua")
    local doc = assert(require("editor.PrefabDocument").load(project, "Assets/PF_Use.prefab"))
    assert(require("editor.PrefabEditor").new(project, doc, function() end, function() end):addScript("root", id, "use")); assert(doc:save(project))
    assert(Fs.removeFile(project:resolvePath("Assets/Missing.lua"))); assert(project:rebuildAssetIndex())
    local catalog = assert(Fs.read(Fs.join(project.rootPath, "assets.json")))
    local read = project.readAsset
    project.readAsset = function(self, reference)
        if reference == "Assets/PF_Use.prefab" then return nil, "transient I/O failure" end
        return read(self, reference)
    end
    local Repair = require("editor.AssetRepair")
    local ok, err = Repair.apply(project, {revision = Repair.plan(project).revision, changes = {{id = id, delete = true}}})
    Assert.equal(false, ok); Assert.truthy(err:find("transient I/O failure", 1, true))
    ok, err = project:deleteEntry("Assets/Missing.lua")
    Assert.equal(false, ok); Assert.truthy(err:find("transient I/O failure", 1, true))
    Assert.equal(catalog, Fs.read(Fs.join(project.rootPath, "assets.json")))
    project.readAsset = nil
    Assert.equal(false, Repair.apply(project, {revision = Repair.plan(project).revision, changes = {{id = id, delete = true}}}))
    assert(project:deleteEntry("Assets/PF_Use.prefab"))
    assert(Repair.apply(project, {revision = Repair.plan(project).revision, changes = {{id = id, delete = true}}}))
    Assert.equal(nil, project:getAssetReference(id))
end)
add("CLI parses step dt and applies a real level transition while rejecting invalid values", function()
    local project = fixture()
    local Cli = require("editor.Cli")
    local example = Cli.execute({command = "project.examples-session", project = project.rootPath})
    local request = Cli.parse({"--cli", "level", "events", "--project", project.rootPath, "--level", example.level,
        "--step-dt", "0", "--events-json", '[{"name":"keypressed","args":["n","n",false]}]'})
    local result = Cli.execute(request)
    Assert.equal(example.nextLevel, result.levelReference)
    for _, value in ipairs({"-1", "bad", "1e999"}) do
        request["step-dt"] = value
        Assert.equal(false, pcall(Cli.execute, request))
    end
end)
return tests
