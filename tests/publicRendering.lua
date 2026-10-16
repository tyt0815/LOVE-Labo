local Assert = require("tests.Assert")
local Engine = require("Engine")
local World, Runtime = require("core.World"), require("core.ScriptRuntime")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function near(a, b) Assert.truthy(math.abs(a - b) < 0.00001, tostring(a) .. " != " .. tostring(b)) end
local function object(world, x, y, parent)
    local value = assert(world:addLObject({transform = {x = x or 0, y = y or 0}}))
    if parent then value:attachTo(parent) end
    return value
end
local function provided(name) return require("plugins.LaboEssentials.Assets." .. name) end
add("Projection data renders without camera scripts plugins or role markers", function()
    local world = World.new(); local origin = 40
    local view = Engine.Rendering.createView(world, {projection = function()
        return {width = 200, height = 100, transform = {x = origin, y = 20, rotation = 90}}
    end})
    local vp = require("core.RenderPipeline").viewport(view, 0, 0, 800, 600)
    near(100, vp.y); near(4, vp.scale)
    local x, y = vp:worldToScreen(40, 20); near(400, x); near(300, y)
    x, y = vp:worldToScreen(40, 30); near(440, x); near(300, y)
    origin = 80; vp = require("core.RenderPipeline").viewport(view, 0, 0, 800, 600)
    x, y = vp:screenToWorld(400, 300); near(80, x); near(20, y)
    view:setProjection(function() return nil end); Assert.equal(false, view:isActive())
    view:setProjection(nil); Assert.equal(true, view:isActive()); assert(world:dispose())
end)
add("Public Transform and Bounds bindings evaluate lazily and preserve authored offsets", function()
    local world = World.new(); local parent = object(world, 100, 50); local child = object(world, 10, 20, parent)
    local offset = 30
    local class = Engine.Script:extend({configure = function(self)
        Engine.Transform.bindLocal(self.owner, {owner = self,
            resolve = function(value) local result = assert(Engine.Transform.copy(value)); result.x = result.x + offset; return result end,
            unresolve = function(value) return {x = value.x - offset, y = value.y} end})
        Engine.Bounds.bind(self, function() return -5, -5, 10, 10 end, {primary = true})
    end})
    local script = Runtime.attach(child, "layout", class)
    near(140, child:getWorldTransform().x); near(10, child.transform.x)
    offset = 60; near(170, child:getWorldTransform().x)
    near(10, Engine.Transform.unresolve(child, {x = 70, y = 20}).x)
    Assert.equal(true, script:hitTest({}, 170, 70))
    script.enabled = false; near(110, child:getWorldTransform().x); Assert.equal(nil, Engine.Bounds.of(child))
    script.enabled = true; near(170, child:getWorldTransform().x)
    Runtime.detach(child, script.id); near(110, child:getWorldTransform().x); Assert.equal(nil, Engine.Bounds.of(child))
    assert(world:dispose())
end)
add("Custom input registration works without Pointer inheritance and cleans up ownership", function()
    local world = World.new(); local owner = object(world); local downs, ups = 0, 0
    local script = Runtime.attach(owner, "custom", Engine.Script:extend({configure = function(self)
        Engine.Bounds.bind(self, function() return -10, -10, 20, 20 end)
    end}))
    local region = Engine.Input.registerRegion(world, {owner = script,
        hitTest = function(context, x, y) return script:hitTest(context, x, y) end,
        onDown = function() downs = downs + 1; return true end,
        onUp = function(event) ups = ups + 1; Assert.equal(false, event.inside); return true end})
    assert(world:dispatchPointer("down", 0, 0, 1)); Assert.equal(1, downs); Assert.equal(region, world.pointerCaptures[1])
    assert(world:dispatchPointer("up", 100, 100, 1)); Assert.equal(1, ups)
    assert(world:dispatchPointer("down", 0, 0, 1)); script.enabled = false
    assert(world:dispatchPointer("up", 100, 100, 1)); Assert.equal(1, ups); Assert.equal(nil, world.pointerCaptures[1])
    script.enabled = true; assert(world:dispatchPointer("down", 0, 0, 1))
    assert(world:removeLObject(owner)); Assert.truthy(region.released); Assert.equal(0, #world.inputRegions)
    Assert.equal(nil, world.pointerCaptures[1]); assert(world:dispose())
end)
add("Canvas and all nine anchors preserve UI pixel size and margins through camera zoom", function()
    local world = World.new(); local cameraObject = object(world, 220, 80)
    local camera = Runtime.attach(cameraObject, "camera", provided("Camera"))
    local canvasObject = object(world, 0, 0, cameraObject)
    local canvas = Runtime.attach(canvasObject, "canvas", provided("Canvas"))
    local view = Engine.Rendering.createView(world, {projection = function() return camera:getProjection() end})
    local points = {topLeft = {0, 0}, top = {0.5, 0}, topRight = {1, 0}, left = {0, 0.5}, center = {0.5, 0.5},
        right = {1, 0.5}, bottomLeft = {0, 1}, bottom = {0.5, 1}, bottomRight = {1, 1}}
    for name, point in pairs(points) do
        local child = object(world, 10, 15, canvasObject)
        local layout = Runtime.attach(child, "rect", provided("RectLayout"), {width = 80, height = 30, anchor = name, pivot = name})
        for _, zoom in ipairs({0.5, 1, 2, 4}) do
            camera.zoom = zoom; cameraObject.transform.rotation = 27
            local vp = require("core.RenderPipeline").viewport(view, 0, 0, 1280, 720)
            local transform = child:getWorldTransform(); local x, y = vp:worldToScreen(transform.x, transform.y)
            near(point[1] * 1280 + 10, x); near(point[2] * 720 + 15, y)
            local left, top, width, height = layout:getBounds()
            near(-point[1] * 80, left); near(-point[2] * 30, top)
            local ax, ay = Engine.Transform.point(transform, width, 0); ax, ay = vp:worldToScreen(ax, ay)
            near(80, math.sqrt((ax - x)^2 + (ay - y)^2)); near(10, child.transform.x)
            Assert.equal(true, layout:hitTest({}, Engine.Transform.point(transform, left + width / 2, top + height / 2)))
        end
    end
    canvas.width, canvas.height = 640, 360; near(640, select(3, canvas:getBounds())); assert(world:dispose())
end)
add("Anchors cross ordinary transformed grouping objects in the same World", function()
    local world = World.new(); local root = object(world, 100, 50)
    Runtime.attach(root, "bounds", provided("RectBounds"), {width = 400, height = 200})
    local group = object(world, 35, 20, root)
    group.transform.rotation, group.transform.scaleX = 25, 2
    local child = object(world, 0, 0, group)
    Runtime.attach(child, "layout", provided("RectLayout"), {anchor = "topRight"})
    local value = child:getWorldTransform()
    near(300, value.x); near(-50, value.y)
    assert(world:dispose())
end)
add("Canvas and View normalize omitted projection transforms without mutating providers", function()
    local world = World.new(); local parent = object(world, 100, 50)
    local data = {width = 1280, height = 720}
    local camera = Runtime.attach(parent, "projection", Engine.Script:extend({getProjection = function() return data end}))
    local canvasObject = object(world, 10, 20, parent)
    Runtime.attach(canvasObject, "canvas", provided("Canvas"))
    local view = Engine.Rendering.createView(world, {projection = function() return camera:getProjection() end})
    for _, width in ipairs({1280, 640}) do
        data.width, data.height = width, width * 720 / 1280
        local projection = view:getProjection(); near(0, projection.transform.x)
        local value = canvasObject:getWorldTransform()
        near(10 * width / 1280, value.x); near(20 * width / 1280, value.y)
        local authored = Engine.Transform.unresolve(canvasObject, Engine.Transform.localValue(canvasObject))
        near(10, authored.x); near(20, authored.y)
        Assert.equal(nil, data.transform)
    end
    data.width = 0
    Assert.equal(false, pcall(view.getProjection, view))
    Assert.equal(false, pcall(canvasObject.getWorldTransform, canvasObject))
    data = false
    Assert.equal(false, pcall(view.getProjection, view))
    Assert.equal(false, pcall(canvasObject.getWorldTransform, canvasObject))
    assert(world:dispose())
end)
add("Screen coordinate drawing is explicit inside draw and restores state on errors", function()
    local world = World.new(); local owner = object(world, 300, 100); local x, y
    Runtime.attach(owner, "overlay", Engine.Script:extend({draw = function(_, context)
        context:withScreen(function() x, y = love.graphics.transformPoint(0, 0); error("screen failure") end)
    end}))
    local vp = require("core.Viewport").new(nil, 10, 20, 300, 200)
    love.graphics.push("all"); love.graphics.origin(); love.graphics.translate(7, 9)
    Assert.equal(false, pcall(require("core.Renderer").drawWorld, world, function() end, vp))
    near(10, x); near(20, y); x, y = love.graphics.transformPoint(0, 0); near(7, x); near(9, y)
    love.graphics.pop(); assert(world:dispose())
    Assert.equal(false, pcall(Engine.Script.extend, Engine.Script, {drawScreen = function() end}))
end)
add("Property choices validate defaults assignments and inherited values", function()
    local class = Engine.Script:extend({properties = {side = {type = "string", default = "left", options = {"left", "right"}}}})
    local value = class:new(); value.side = "right"; Assert.equal("right", value.side)
    Assert.equal(false, pcall(function() value.side = "other" end)); Assert.equal(false, pcall(class.new, class, {side = "other"}))
    Assert.equal(false, pcall(Engine.Script.extend, Engine.Script, {properties = {side = {type = "string", default = "bad", options = {"left"}}}}))
    Assert.equal("right", class:extend({properties = {side = {type = "string", default = "right"}}}):new().side)
end)
add("Transform binding cycles fail without permanently poisoning future evaluation", function()
    local world = World.new(); local object = object(world); local cyclic = true
    Runtime.attach(object, "binding", Engine.Script:extend({configure = function(self)
        Engine.Transform.bindLocal(self.owner, {owner = self, resolve = function(value)
            if cyclic then return self:getWorldTransform() end
            return value
        end})
    end}))
    Assert.equal(false, pcall(object.getWorldTransform, object)); cyclic = false
    near(0, object:getWorldTransform().x); assert(world:dispose())
end)
local function exampleProject(publicOnly)
    local Fs = require("editor.HostFileSystem")
    local project = assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "PublicUi_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
    local result = require("editor.Cli").execute({command = "project.examples-ui", project = project.rootPath, publicOnly = publicOnly})
    project = assert(require("editor.Project").open(project.rootPath))
    return project, result
end
add("Public HUD example runs and receives zoom invariant clicks with all plugins disabled", function()
    local project, result = exampleProject(true)
    project = assert(require("editor.Project").open(project.rootPath))
    Assert.equal(nil, next(project.plugins.enabled))
    Assert.equal(true, require("editor.Cli").execute({command = "project.validate", project = project.rootPath}).valid)
    local level = assert(require("editor.LevelDocument").load(project:resolveAssetFile(result.publicLevel))).level
    local world = assert(require("runtime.WorldLoader").create(project, level:toData()))
    local camera = world.lobjects[1]:getScriptByName("camera")
    local button
    for _, object in ipairs(world.lobjects) do if object.name == "topLeft" then button = object:getScriptByName("button") end end
    local rect = {x = 0, y = 0, width = 1280, height = 720}
    for _, zoom in ipairs({1, 2, 4}) do
        camera.zoom = zoom; camera.owner.transform.x = 300
        local ok, response = require("core.RenderPipeline").pointer(world, "down", 40, 40, 1, 0, 0, function() end, rect)
        Assert.equal(true, ok); Assert.equal(true, response.consumed)
        assert(require("core.RenderPipeline").pointer(world, "up", 40, 40, 1, 0, 0, function() end, rect))
    end
    Assert.equal(3, button.clicks); Assert.equal(nil, camera.camera)
    local canvas = love.graphics.newCanvas(1280, 720)
    love.graphics.push("all"); love.graphics.setCanvas(canvas)
    require("core.RenderPipeline").draw(world, function() end, 0, 0, 1280, 720)
    love.graphics.pop(); canvas:release(); assert(world:dispose())
end)
add("Editor uses effective layout positions and converts world edits back to anchor offsets", function()
    local project, result = exampleProject()
    local app = require("editor.EditorApp").new(nil, project)
    assert(app:openProjectDocument(result.level, true))
    local child
    for _, object in ipairs(app.level.lobjects) do if object.name == "topRight" then child = object end end
    local preview = assert(app.spriteAssets:preview(child), app.spriteAssets.error)
    assert(preview.parent, "Layout preview lost its parent")
    assert(Engine.Bounds.of(preview.parent), app.spriteAssets.error or "Parent preview has no primary bounds")
    Assert.equal("topRight", preview:getScriptByName("layout").anchor)
    local before = app.level:getWorldTransform(child)
    near(620, before.x); near(-340, before.y); near(-20, child.transform.x)
    assert(app.level:setWorldPosition(child, before.x - 30, before.y + 10))
    near(-50, child.transform.x); near(30, child.transform.y)
    local after = app.level:getWorldTransform(child); near(before.x - 30, after.x)
    app.inspectorSource = "scene"; app.sceneView:setSelection({child}); app:updateInspectorTarget(); app:draw()
    local inspector = app.inspector.classInspector
    local id = inspector.preview:getScriptByName("layout").id
    local key = id .. ".anchor"
    Assert.equal(9, #inspector.class.properties[key].options)
    Assert.equal(9, #inspector:choices(key, "topRight").options)
    assert(inspector:setProperty(key, "bottomLeft")); Assert.equal(false, inspector:setProperty(key, "invalid"))
    local camera = app.level.lobjects[1]
    local cameraId = camera.scripts[1].id
    camera.scriptOverrides = camera.scriptOverrides or {}; camera.scriptOverrides[cameraId] = {zoom = 2}
    local position = app.level:getWorldTransform(child)
    near(-345, position.x); near(195, position.y)
    near(-50, child.transform.x); near(30, child.transform.y)
    local view = app.sceneView; view.gizmoMode = "translate"; assert(view:frameSelected())
    local handles = require("editor.TransformGizmo").handles(view)
    view:mousepressed(handles.x, handles.y, 1)
    view:mousemoved(handles.x + 30, handles.y + 20, 30, 20)
    local moved = app.level:getWorldTransform(child)
    near(position.x + view:snapValue(30 / view.zoom), moved.x)
    near(position.y + view:snapValue(20 / view.zoom), moved.y)
    view:cancelDrag(true)
    near(-50, child.transform.x); near(30, child.transform.y)
    -- 명시적 카메라 참조도 프리뷰 객체로 해석하고 변경 후 다시 연결한다.
    local canvas = app.level:getParent(child)
    local canvasPreview = assert(app.spriteAssets:preview(canvas))
    local canvasId = canvasPreview:getScriptByName("canvas").id
    canvas.scriptOverrides = {[canvasId] = {cameraSource = {authoringId = camera.authoringId, script = cameraId}}}
    near(-345, app.level:getWorldTransform(child).x)
    camera.scriptOverrides[cameraId].zoom = 4
    near(-172.5, app.level:getWorldTransform(child).x)
    local layoutObject = assert(app.level:addLObject(10, 20, nil, "Free layout"))
    layoutObject.scripts = {{id = "free-layout", name = "layout", source = project.plugins.scripts.RectLayout.id}}
    layoutObject.scriptOverrides = {["free-layout"] = {anchor = "topRight"}}
    local original = assert(Engine.Transform.copy(app.level:getWorldTransform(layoutObject)))
    assert(app.level:reparent({layoutObject}, canvas))
    local attached = app.level:getWorldTransform(layoutObject)
    near(original.x, attached.x); near(original.y, attached.y)
    assert(app.level:reparent({layoutObject}, nil))
    local detached = app.level:getWorldTransform(layoutObject)
    near(original.x, detached.x); near(original.y, detached.y)
    -- 삭제된 참조를 이전 프리뷰나 대상 오브젝트로 잘못 유지하지 않는다.
    camera.scripts = {}; camera.scriptOverrides = nil
    canvasPreview = assert(app.spriteAssets:preview(canvas))
    Assert.equal(false, canvasPreview:getScriptByName("canvas").cameraSource)
end)
add("CLI reparent preserves effective anchor positions when detaching and attaching", function()
    local project, result = exampleProject()
    local path = project:resolveAssetFile(result.level)
    local document = assert(require("editor.LevelDocument").load(path))
    local level = document.level
    local parent = assert(level:addLObject(100, 50, nil, "Parent rect"))
    parent.scripts = {{id = "bounds", name = "bounds", source = project.plugins.scripts.RectBounds.id}}
    parent.scriptOverrides = {bounds = {width = 400, height = 200}}
    local child = assert(level:addLObject(10, 20, nil, "Anchored"))
    child.parentAuthoringId = parent.authoringId
    child.scripts = {{id = "layout", name = "layout", source = project.plugins.scripts.RectLayout.id}}
    child.scriptOverrides = {layout = {anchor = "topRight"}}
    assert(document:save(path))
    local Cli = require("editor.Cli")
    local function check()
        local response = Cli.execute({command = "instance.list", project = project.rootPath, level = result.level})
        for _, row in ipairs(response.instances) do if row.data.authoringId == child.authoringId then
            near(310, row.worldTransform.x); near(-30, row.worldTransform.y)
        end end
        local saved = assert(require("editor.LevelDocument").load(path)).level
        local world = assert(require("runtime.WorldLoader").prepare(project, saved:toData()))
        local found
        for _, value in ipairs(world.lobjects) do if value.authoringId == child.authoringId then found = value end end
        local transform = assert(found):getWorldTransform()
        near(310, transform.x); near(-30, transform.y)
        assert(world:dispose())
    end
    check()
    for _, parentId in ipairs({false, parent.authoringId, false}) do
        Cli.execute({command = "instance.reparent", project = project.rootPath, level = result.level,
            instance = child.authoringId, parent = parentId})
        check()
    end
    local saved = assert(require("editor.LevelDocument").load(path)).level:findLObject(child.authoringId)
    near(310, saved.transform.x); near(-30, saved.transform.y)
end)
add("Migration dry run preserves files and converts nested legacy Canvas fields once", function()
    local project, result = exampleProject()
    local Json, Fs = require("project.Json"), require("editor.HostFileSystem")
    local path = project:resolveAssetFile(result.level)
    local data = assert(Json.decode(assert(Fs.read(path))))
    data.mainCamera = {authoringId = data.lobjects[1].authoringId, script = data.lobjects[1].scripts[1].id}
    assert(Fs.writeAtomic(path, assert(Json.encode(data, true))))
    assert(project:createEntry("Assets/Examples", "prefab", "PF_LegacyCanvas"))
    local prefabPath = project:resolveAssetFile("Assets/Examples/PF_LegacyCanvas.prefab")
    local id = require("project.AssetId").new()
    local prefab = assert(Json.decode(assert(Fs.read(prefabPath))))
    prefab.children = {{id = "nested", scripts = {{id = id, name = "canvas", source = project.plugins.scripts.Canvas.id}},
        overrides = {scripts = {[id] = {matchViewport = true}}}}}
    assert(Fs.writeAtomic(prefabPath, assert(Json.encode(prefab, true))))
    local before, beforePrefab = assert(Fs.read(path)), assert(Fs.read(prefabPath))
    local Cli = require("editor.Cli")
    local request = Cli.parse({"--cli", "project", "migrate-rendering", "--project", project.rootPath, "--dry-run"})
    local preview = Cli.execute(request)
    Assert.equal(true, preview.dryRun); Assert.equal(2, #preview.changed)
    Assert.equal(before, assert(Fs.read(path))); Assert.equal(beforePrefab, assert(Fs.read(prefabPath)))
    local applied = Cli.execute({command = "project.migrate-rendering", project = project.rootPath})
    Assert.equal(2, #applied.changed)
    local migrated = assert(Json.decode(assert(Fs.read(prefabPath))))
    Assert.equal(true, migrated.children[1].overrides.scripts[id].matchCamera)
    Assert.equal(nil, migrated.children[1].overrides.scripts[id].matchViewport)
    Assert.equal(0, #Cli.execute({command = "project.migrate-rendering", project = project.rootPath}).changed)
    Assert.equal(true, Cli.execute({command = "project.validate", project = project.rootPath}).valid)
end)
return tests
