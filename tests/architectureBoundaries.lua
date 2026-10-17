local Assert = require("tests.Assert")
local Fs, Json = require("editor.HostFileSystem"), require("project.Json")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function fixture()
    return assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "AttachedTest_Architecture_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
end

add("Raw package and build reject case variants of source directories without changing files", function()
    local project = fixture()
    local level = require("editor.Level").new()
    assert(project:createEntry("Assets", "level", "L_Test"))
    for _, folder in ipairs({"Assets", "Tools", "docs", ".labo", "Plugins"}) do
        require("project.Workspace").ensureDirectory(Fs.join(project.rootPath, folder))
        local path = Fs.join(project.rootPath, folder .. "/Game.love")
        assert(Fs.writeAtomic(path, "preserve original"))
        local output = Fs.join(project.rootPath, folder:lower() .. "/Game.love")
        local ok, err = require("editor.GamePackage").write(project, level, output)
        Assert.equal(false, ok); Assert.truthy(err:find("overlaps project sources", 1, true))
        Assert.equal(false, require("editor.ProjectBuild").run(project, level, output))
        Assert.equal("preserve original", Fs.read(path))
    end
    local Cli = require("editor.Cli")
    local ok = pcall(Cli.execute, {command = "export.package", project = project.rootPath,
        level = "Assets/L_Test.level", output = Fs.join(project.rootPath, "aSSeTs/Game.love")})
    Assert.equal(false, ok)
    Assert.equal("preserve original", Fs.read(Fs.join(project.rootPath, "Assets/Game.love")))
    assert(require("editor.GamePackage").write(project, level, Fs.join(project.rootPath, "Build/Game.love")))
end)

add("Editor keeps per View captures outside Game View until all buttons are released", function()
    local app = require("editor.EditorApp").new()
    local world = require("core.World").new()
    local object = assert(world:addLObject({transform = {x = 0, y = 0}}))
    local down, up, moves = {}, {}, 0
    local class = require("core.Script"):extend({load = function(self, runtime)
        require("core.Input").registerRegion(runtime, {owner = self, hitTest = function() return true end,
            onDown = function(event) down[event.button] = true; return true end,
            onUp = function(event) up[event.button] = true; return true end,
            onMove = function() moves = moves + 1; return true end})
    end})
    local script = require("core.ScriptRuntime").attach(object, "probe", class)
    assert(object:load(world))
    local view = require("core.Rendering").createView(world, {})
    app.runtimeWorld = world
    local ok, err = pcall(function()
        app:updateSceneViewport()
        local viewport = assert(app:runtimeViewport())
        local x, y = viewport.x + viewport.width / 2, viewport.y + viewport.height / 2
        app:mousepressed(x, y, 1); app:mousepressed(x, y, 2)
        Assert.truthy(down[1] and down[2]); Assert.equal(app.sceneWidget, app.uiRoot.captured)
        app:mousemoved(10, 100, -100, 0); Assert.truthy(moves > 0)
        app:mousereleased(10, 100, 1)
        Assert.truthy(up[1]); Assert.equal(app.sceneWidget, app.uiRoot.captured); Assert.equal(2, app.uiRoot.captureButton)
        app:mousereleased(10, 100, 2)
        Assert.truthy(up[2]); Assert.equal(nil, app.uiRoot.captured); Assert.equal(nil, next(view.pointerCaptures))
        app:mousepressed(x, y, 1); script.enabled = false
        Assert.equal(nil, app:gameCaptureButton()); Assert.equal(nil, next(view.pointerCaptures))
        script.enabled = true; app:mousepressed(x, y, 1)
        assert(app:pausePlay()); Assert.equal(nil, next(view.pointerCaptures)); Assert.equal(nil, app.uiRoot.captured)
    end)
    app:stopPlay()
    assert(ok, err)
end)

add("Project and plugin accept the same validated classes and reject arbitrary metatables", function()
    local project = fixture()
    local Operations = require("editor.PluginOperations")
    assert(Operations.create(project, "Gameplay")); assert(Operations.apply(project, "Gameplay", true, true))
    assert(project:createEntry("Assets", "lua", "Copied", {scriptKind = "script"}))
    local pluginPath = assert(project:resolveSourceFile(project.plugins.scripts.Gameplay.id))
    local projectPath = assert(project:resolveSourceFile("Assets/Copied.lua"))
    local function loadBoth(source, accepted)
        assert(Fs.writeAtomic(pluginPath, source)); assert(Fs.writeAtomic(projectPath, source))
        local load = require("project.LuaScript").loader(project)
        local own, ownError = load("Assets/Copied.lua", "script")
        local plugin, pluginError = load("Gameplay", "script")
        Assert.equal(accepted, own ~= nil, ownError); Assert.equal(accepted, plugin ~= nil, pluginError)
        if accepted then
            Assert.truthy(own:new():isA(require("core.Script")))
            Assert.truthy(plugin:new():isA(require("core.Script")))
            Assert.equal(own, load("Assets/Copied.lua", "script")); Assert.equal(plugin, load("Gameplay", "script"))
        end
    end
    loadBoth(assert(love.filesystem.read("plugins/LaboEssentials/Assets/Camera.lua")), true)
    loadBoth('return {properties = {}}', true)
    loadBoth('return require("Engine").Script', false)
    loadBoth('return setmetatable({properties = {}}, {__index = require("Engine").Script})', false)
    loadBoth('return {properties = {}, build = function() end}', false)
    loadBoth('return require("Engine").Script:extend({properties = {bad = {type = "number", default = "wrong"}}})', false)
    loadBoth([[local class = require("Engine").Script:extend({properties = {}})
function class.sameDefinition() return require("Copied") == class end
return class]], true)
    local load = require("project.LuaScript").loader(project)
    Assert.truthy(assert(load("Assets/Copied.lua", "script")).sameDefinition())
    Assert.truthy(assert(load("Assets/Copied.lua", "script")) ~= assert(require("project.LuaScript").loader(project)("Assets/Copied.lua", "script")))
end)

add("Editor CLI emits one failure JSON and exit one when result persistence or encoding fails", function()
    local project, Cli = fixture(), require("editor.Cli")
    local function invoke(args, execute)
        table.insert(args, 1, "--cli")
        local stdout, quit, originalPrint, originalExecute = io.stdout, love.event.quit, print, Cli.execute
        local chunks, exit = {}, nil
        io.stdout = {write = function(_, bytes) chunks[#chunks + 1] = bytes end, flush = function() end}
        _G.print = function(value) chunks[#chunks + 1] = tostring(value) .. "\n" end
        love.event.quit = function(code) exit = code end
        if execute then Cli.execute = execute end
        local ok, err = pcall(Cli.run, args)
        io.stdout, love.event.quit, _G.print, Cli.execute = stdout, quit, originalPrint, originalExecute
        assert(ok, err)
        local text = table.concat(chunks)
        local response = assert(Json.decode(text))
        Assert.equal(1, response.version)
        return response, exit, text
    end
    local response, exit = invoke({"help", "--result", Fs.join(project.rootPath, "Missing/result.json")})
    Assert.equal(false, response.ok); Assert.equal(1, exit); Assert.truthy(response.error)
    response, exit = invoke({"help", "--result", ""})
    Assert.equal(false, response.ok); Assert.equal(1, exit)
    response, exit = invoke({"help"}, function() return function() end end)
    Assert.equal(false, response.ok); Assert.equal(1, exit); Assert.truthy(response.error:find("Cannot encode", 1, true))
    local path = Fs.join(project.rootPath, "result.json")
    local text
    response, exit, text = invoke({"help", "--result", path})
    Assert.equal(true, response.ok); Assert.equal(0, exit); Assert.equal(text, Fs.read(path))
end)

add("CLI events use View subrect and letterbox for mouse and touch coordinates", function()
    local project = fixture()
    assert(project:createEntry("Assets", "lua", "Events", {scriptKind = "script"}))
    assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/Events.lua")), [[local Engine = require("Engine")
local Events = {properties = {x = {type = "number", default = 0}, y = {type = "number", default = 0}, presses = {type = "number", default = 0}}}
function Events:load(world)
    Engine.Rendering.createView(world, {viewport = {x = 100, y = 50, width = 400, height = 300}, projection = {width = 200, height = 100}})
end
function Events:mousepressed(x, y) self.x, self.y, self.presses = x, y, self.presses + 1 end
function Events:touchpressed(id, x, y) self:mousepressed(x, y) end
return Events]]))
    local level = require("editor.Level").new()
    level:addLObject(0, 0).scripts = {{id = "events", name = "events", source = project:getAssetId("Assets/Events.lua")}}
    local function run(events)
        return require("editor.CliEvents").execute(project, level, {width = 800, height = 600, events = events}).instances[1].scripts.events
    end
    -- 400×300 출력 안의 2:1 투영은 y=100부터 시작한다.
    local state = run({{name = "mousepressed", args = {120, 110, 1}}, {name = "mousepressed", args = {120, 60, 2}},
        {name = "mousepressed", args = {20, 110, 3}}})
    Assert.equal(1, state.presses); Assert.equal(20, state.x); Assert.equal(10, state.y)
    state = run({{name = "touchpressed", args = {1, 120, 110, 0, 0, 1}}})
    Assert.equal(1, state.presses); Assert.equal(20, state.x); Assert.equal(10, state.y)
end)

add("Preview replacement and partial failures release object and scope bindings without lifecycle callbacks", function()
    local Definition, LuaScript = require("project.ObjectDefinition"), require("project.LuaScript")
    local resolve, loader = Definition.resolve, LuaScript.loader
    local handles = {}
    local class = require("core.Script"):extend({configure = function(self)
        handles[#handles + 1] = require("core.Bounds").bind(self, function() return 0, 0, 1, 1 end)
    end, load = function() error("preview must not load") end, unload = function() error("preview must not unload") end})
    local fail = false
    local function loadClass(source) if source == "Bad" then return nil, "broken preview class" end; return class end
    Definition.resolve = function()
        return {attachments = fail and {{id = "good", source = "Good"}, {id = "bad", source = "Bad"}} or {{id = "good", source = "Good"}},
            scripts = {}, scriptLoader = loadClass}
    end
    LuaScript.loader = function() return loadClass end
    local ok, err = pcall(function()
        local layout = require("project.AuthoringLayout").new({})
        local data = {transform = {x = 0, y = 0}}
        assert(layout:preview(data)); local first = handles[#handles]
        data.transform.x = 10; assert(layout:preview(data)); Assert.equal(true, first.released)
        local second = handles[#handles]
        fail = true; data.transform.x = 20; Assert.equal(nil, layout:preview(data))
        Assert.equal(true, second.released); Assert.equal(true, handles[#handles].released)
        layout:clear()
        fail = false; assert(layout:preview(data)); local current = handles[#handles]
        layout:clear(); Assert.equal(true, current.released)
        local assets = require("editor.SpriteAssets").new({})
        for _, scope in ipairs({"project", "level"}) do
            local scopeData = {scripts = {{id = "good", name = "good", source = "Good"}}}
            assert(assets:scopePreview(scopeData, scope)); first = handles[#handles]
            scopeData.scriptOverrides = {good = {enabled = false}}
            assert(assets:scopePreview(scopeData, scope)); Assert.equal(true, first.released); second = handles[#handles]
            scopeData.scripts[2] = {id = "bad", name = "bad", source = "Bad"}
            Assert.equal(nil, assets:scopePreview(scopeData, scope))
            Assert.equal(true, second.released); Assert.equal(true, handles[#handles].released)
            scopeData.scripts[2] = nil; assert(assets:scopePreview(scopeData, scope)); current = handles[#handles]
            assets:clear(); Assert.equal(true, current.released)
        end
    end)
    Definition.resolve, LuaScript.loader = resolve, loader
    assert(ok, err)
end)
return tests
