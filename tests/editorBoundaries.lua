local Assert = require("tests.Assert")
local Fs, Json = require("editor.HostFileSystem"), require("project.Json")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function fixture()
    return assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "PreviewTest_Boundaries_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
end

add("Prefab rejects malformed root and nested lists instead of discarding entries", function()
    local Prefab = require("project.Prefab")
    for _, field in ipairs({"children", "bindings", "removedPaths", "previewBackground"}) do
        for _, list in ipairs({Json.null, {lost = {}}, {[2] = {}}, {[1] = {}, [3] = {}}, {[1] = {}, extra = {}}}) do
            local data = {formatVersion = 4, overrides = {}}
            data[field] = list
            local bytes = Json.encode(data)
            if bytes then Assert.equal(nil, Prefab.decode(bytes)) end
            Assert.equal(nil, Prefab.encodeData(data))
        end
    end
    for _, field in ipairs({"children", "removedPaths"}) do
        local child = {id = "child"}; child[field] = {lost = {}}
        local data = {formatVersion = 4, overrides = {}, children = {child}}
        local decoded, err = Prefab.decode(assert(Json.encode(data)))
        Assert.equal(nil, decoded); Assert.truthy(err:find("children[1]." .. field, 1, true))
    end
    for _, data in ipairs({{formatVersion = 4, overrides = {}},
        {formatVersion = 4, overrides = {}, children = {}, bindings = {}, removedPaths = {}},
        {formatVersion = 4, overrides = {}, children = {{id = "child", children = {}, removedPaths = {}}}}}) do
        Assert.truthy(Prefab.decode(assert(Prefab.encodeData(data))))
    end
end)

add("GUI CLI and export reject malformed Prefab lists through the shared decoder", function()
    local project = fixture()
    assert(project:createEntry("Assets", "prefab", "PF_Bad"))
    assert(project:createEntry("Assets", "level", "L_Test"))
    for _, field in ipairs({"children", "bindings", "removedPaths"}) do
        local data = {formatVersion = 4, overrides = {}}; data[field] = {lost = {}}
        assert(Fs.writeAtomic(assert(project:resolveAssetFile("Assets/PF_Bad.prefab")), assert(Json.encode(data))))
        Assert.equal(nil, require("editor.PrefabDocument").load(project, "Assets/PF_Bad.prefab"))
        local validation = require("editor.ProjectValidation").run(project)
        Assert.equal(false, validation.valid); Assert.truthy(#validation.errors > 0)
        local cli = require("editor.Cli").execute({command = "project.validate", project = project.rootPath})
        Assert.equal(false, cli.valid)
        local level = require("editor.Level").new(); level:addLObject(0, 0, project:getAssetId("Assets/PF_Bad.prefab"))
        local ok = require("editor.GamePackage").write(project, level, Fs.join(project.rootPath, "Build/Bad.love"))
        Assert.equal(false, ok)
    end
end)

add("Scene restores canvas stack transform color and scissor after user draw and layout failures", function()
    local Scene, Script = require("editor.SceneView"), require("core.Script")
    for _, phase in ipairs({"draw", "false", "layout"}) do
        local object = assert(require("core.LObject").new(1, {transform = {x = 0, y = 0}}))
        local canvas = love.graphics.newCanvas(64, 64)
        require("core.ScriptRuntime").attach(object, "broken", Script:extend({draw = function()
            love.graphics.setCanvas(canvas); love.graphics.setColor(1, 0, 0, 1)
            love.graphics.translate(30, 40); love.graphics.setScissor(0, 0, 1, 1)
            love.graphics.push("all")
            if phase == "false" then return false, "broken draw" end
            error("broken draw")
        end}))
        local scene = Scene.new(nil, {lobjects = {{}}}); scene:setViewport(10, 10, 100, 100)
        scene.spriteAssets = {setLevel = function() end, preview = function()
            if phase == "layout" then love.graphics.push("all"); error("broken layout") end
            return object
        end}
        love.graphics.push("all")
        local depth = love.graphics.getStackDepth()
        local ok, err = pcall(function()
            love.graphics.setColor(0.25, 0.5, 0.75, 1); love.graphics.setScissor(1, 2, 30, 40)
            love.graphics.translate(3, 4)
            local beforeCanvas = love.graphics.getCanvas()
            local x, y = love.graphics.transformPoint(0, 0)
            Assert.equal(false, pcall(scene.draw, scene))
            Assert.equal(depth, love.graphics.getStackDepth())
            Assert.equal(beforeCanvas, love.graphics.getCanvas())
            local r, g, b = love.graphics.getColor()
            Assert.equal(0.25, r); Assert.equal(0.5, g); Assert.equal(0.75, b)
            local sx, sy, sw, sh = love.graphics.getScissor()
            Assert.equal(1, sx); Assert.equal(2, sy); Assert.equal(30, sw); Assert.equal(40, sh)
            local ax, ay = love.graphics.transformPoint(0, 0)
            Assert.equal(x, ax); Assert.equal(y, ay)
        end)
        -- 실패한 회귀 테스트도 다음 테스트의 그래픽 상태를 오염시키지 않는다.
        while love.graphics.getStackDepth() >= depth do love.graphics.pop() end
        canvas:release(); object:unload(); assert(ok, err)
    end
end)

local bindingSource = [[local Class = {}
function Class:configure() require("Engine").Bounds.bind(self, function() return 0, 0, 1, 1 end) end
function Class:load() error("Inspector must not load") end
function Class:unload() error("Inspector must not unload") end
return Class]]
local function bindingProject()
    local project = fixture()
    assert(project:createEntry("Assets", "lua", "Binding", {scriptKind = "script"}))
    assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/Binding.lua")), bindingSource))
    return project, {id = "binding", name = "binding", source = project:getAssetId("Assets/Binding.lua")}
end
local function handle(inspector) return inspector.preview:getScriptById("binding").boundsBinding end

add("Inspector reload selection None and cached object return release only obsolete bindings", function()
    local project, attachment = bindingProject()
    local app = require("editor.EditorApp").new(nil, project)
    local object = app.level:addLObject(0, 0); object.scripts = {attachment}
    app.sceneView:setSelection({object}); app:updateInspectorTarget()
    local inspector = app.inspector.classInspector
    local first = handle(inspector); inspector:reload(); local second = handle(inspector)
    Assert.equal(true, first.released); Assert.truthy(second.released ~= true)
    inspector:setTarget(nil); Assert.equal(true, second.released); Assert.equal(nil, inspector.preview)
    app:updateInspectorTarget(); local third = handle(inspector)
    Assert.truthy(third ~= second); Assert.truthy(third.released ~= true)
    inspector:setTarget(nil); Assert.equal(true, third.released)
end)

add("Inspector releases partial configuration on class and configure failure without lifecycle callbacks", function()
    for _, failure in ipairs({"class", "configure"}) do
        local handles = {}
        local class = require("core.Script"):extend({configure = function(self)
            handles[#handles + 1] = require("core.Bounds").bind(self, function() return 0, 0, 1, 1 end)
            if failure == "configure" and self.id == "bad" then error("broken configure") end
        end, load = function() error("must not load") end, unload = function() error("must not unload") end})
        local definition = {attachments = {{id = "good", source = "good"}, {id = "bad", source = "bad"}}, scripts = {},
            scriptLoader = function(source) if source == "bad" and failure == "class" then return nil, "broken class" end; return class end}
        local target, err = require("project.ObjectDefinition").inspectorTarget({}, {}, definition)
        Assert.equal(nil, target); Assert.truthy(err); Assert.truthy(#handles > 0)
        for _, binding in ipairs(handles) do Assert.equal(true, binding.released) end
    end
end)

add("Project Level and Prefab Inspector stable targets dispose old bindings on reload and selection", function()
    local project, attachment = bindingProject()
    project.scripts = {attachment}
    local app = require("editor.EditorApp").new(nil, project)
    app.level.scripts = {attachment}
    assert(project:createEntry("Assets", "level", "L_Scope"))
    assert(app.document:save(assert(project:resolveAssetFile("Assets/L_Scope.level"))))
    assert(project:createEntry("Assets", "prefab", "PF_Binding"))
    local data = {formatVersion = 4, overrides = {}, scripts = {attachment}}
    assert(Fs.writeAtomic(assert(project:resolveAssetFile("Assets/PF_Binding.prefab")), assert(require("project.Prefab").encodeData(data))))
    local inspector = app.inspector.classInspector
    for _, select in ipairs({function() app:showProjectInspector() end,
        function() assert(app:inspectAsset("Assets/L_Scope.level")) end,
        function() assert(app:inspectAsset("Assets/PF_Binding.prefab")) end}) do
        select(); local first = handle(inspector)
        inspector:reload(); local second = handle(inspector)
        Assert.equal(true, first.released); Assert.truthy(second.released ~= true)
        inspector:setTarget(nil); Assert.equal(true, second.released)
    end
end)

add("Scene script errors leave editor UI and unsaved document usable and recover after refresh", function()
    local project, attachment = bindingProject()
    local path = assert(project:resolveSourceFile("Assets/Binding.lua"))
    assert(Fs.writeAtomic(path, 'return {draw = function() error("broken scene") end}'))
    local app = require("editor.EditorApp").new(nil, project)
    local object = app.level:addLObject(10, 20); object.scripts = {attachment}
    app.sceneView:setSelection({object}); app:updateInspectorTarget()
    local before = assert(require("editor.LevelFile").encode(app.level))
    local depth = love.graphics.getStackDepth()
    app:draw(); app:draw()
    Assert.equal(depth, love.graphics.getStackDepth()); Assert.truthy(app.runtimeError:find("broken scene", 1, true))
    Assert.equal(before, require("editor.LevelFile").encode(app.level)); Assert.truthy(app.document:isDirty())
    local history = #app.debugSession.history
    app:draw(); Assert.equal(history, #app.debugSession.history)
    assert(Fs.writeAtomic(path, 'return {draw = function() return true end}')); assert(app:refreshProject(false))
    app:draw(); Assert.equal(depth, love.graphics.getStackDepth())
    app.inspector.classInspector:setTarget(nil); app.spriteAssets:clear()
end)

add("Inspector configuration failure clears stale rows and recovers after source repair", function()
    local project, attachment = bindingProject()
    local app = require("editor.EditorApp").new(nil, project)
    local object = app.level:addLObject(0, 0); object.scripts = {attachment}
    app.sceneView:setSelection({object}); app:updateInspectorTarget()
    local inspector = app.inspector.classInspector
    local previous = handle(inspector)
    local path = assert(project:resolveSourceFile("Assets/Binding.lua"))
    assert(Fs.writeAtomic(path, 'return {configure = function() error("broken inspector") end}'))
    Assert.equal(false, inspector:reload()); Assert.equal(true, previous.released)
    Assert.equal(nil, inspector.preview); app:draw()
    assert(Fs.writeAtomic(path, bindingSource)); assert(inspector:reload())
    Assert.truthy(handle(inspector).released ~= true); app:draw()
    inspector:setTarget(nil); app.spriteAssets:clear()
end)

add("Scope Inspector rebuild failure reports the error and discards its obsolete preview", function()
    local project, attachment = bindingProject(); project.scripts = {attachment}
    local app = require("editor.EditorApp").new(nil, project); app:showProjectInspector()
    local inspector = app.inspector.classInspector; local previous = handle(inspector)
    local path = assert(project:resolveSourceFile("Assets/Binding.lua"))
    assert(Fs.writeAtomic(path, 'return {configure = function() error("broken scope") end}'))
    local ok, err = inspector:reload()
    Assert.equal(false, ok); Assert.truthy(err:find("broken scope", 1, true))
    Assert.equal(true, previous.released); Assert.equal(nil, inspector.preview)
    assert(Fs.writeAtomic(path, bindingSource)); assert(inspector:reload()); app:draw()
    Assert.truthy(handle(inspector).released ~= true)
    inspector:setTarget(nil); app.spriteAssets:clear()
end)

add("Temporary tree capture duplicate and CLI targets release bindings on success and failure", function()
    local project, attachment = bindingProject()
    assert(project:createEntry("Assets", "prefab", "PF_Binding"))
    assert(Fs.writeAtomic(assert(project:resolveAssetFile("Assets/PF_Binding.prefab")), assert(require("project.Prefab").encodeData(
        {formatVersion = 4, overrides = {}, scripts = {attachment}}))))
    assert(project:createEntry("Assets", "level", "L_Test"))
    local level = require("editor.Level").new(); local object = level:addLObject(0, 0)
    object.scripts = {attachment}; level.scripts = {attachment}; project.scripts = {attachment}
    assert(project:saveScripts())
    assert(require("editor.LevelFile").save(assert(project:resolveAssetFile("Assets/L_Test.level")), level))
    local Definition = require("project.ObjectDefinition")
    local factory, handles = Definition.inspectorTarget, {}
    Definition.inspectorTarget = function(...)
        local target, err = factory(...)
        if target then
            local script = target.preview:getScriptById("binding")
            if script then handles[#handles + 1] = script.boundsBinding end
        end
        return target, err
    end
    local ok, err = pcall(function()
        local function check(fn)
            local start = #handles; fn(); Assert.truthy(#handles > start)
            for i = start + 1, #handles do Assert.equal(true, handles[i].released) end
        end
        check(function() require("editor.ui.ClassTree").new(project, "prefab") end)
        local hierarchy = require("project.PrefabHierarchy")
        check(function() assert(hierarchy.capture(project, level, object)) end)
        check(function() assert(hierarchy.duplicateData(project, level, object)) end)
        for _, command in ipairs({"instance.get", "instance.rename", "prefab.get", "prefab.set-parent", "project.script.get", "level.script.get",
            "instance.set", "prefab.set", "project.script.set", "level.script.set"}) do
            check(function()
                local request = {command = command, project = project.rootPath, level = "Assets/L_Test.level",
                    prefab = "Assets/PF_Binding.prefab", instance = 1, name = "Renamed", property = "missing", value = 1, parent = false}
                local called = pcall(require("editor.Cli").execute, request)
                Assert.equal(not command:match("%.set$"), called)
                Assert.equal(nil, Fs.info(Fs.join(project.rootPath, ".labo-cli.lock")))
            end)
        end
    end)
    Definition.inspectorTarget = factory
    assert(ok, err)
end)

return tests
