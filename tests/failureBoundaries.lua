local Assert = require("tests.Assert")
local World = require("core.World")
local Script = require("core.Script")
local Loader = require("runtime.WorldLoader")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end

add("Editor and runtime reject object maps sparse and mixed level arrays without truncation", function()
    local item = {authoringId = 1, transform = {x = 0, y = 0}}
    local malformed = {
        {oops = item}, {[2] = item}, {[1] = item, [3] = item},
        {[1] = item, extra = item}, {[0] = item}, {[1.5] = item}
    }
    for _, objects in ipairs(malformed) do
        local data = {formatVersion = 3, lobjects = objects}
        Assert.equal(nil, require("editor.Level").fromData(data))
        Assert.equal(nil, World.fromLevelData(data))
        Assert.equal(nil, Loader.prepare({}, data))
    end
    local text = '{"formatVersion":3,"lobjects":{"oops":{"authoringId":1,"transform":{"x":0,"y":0}}}}'
    Assert.equal(nil, require("editor.LevelFile").decode(text))
    for _, objects in ipairs({{}, {item}}) do
        local data = {formatVersion = 3, lobjects = objects}
        Assert.truthy(require("editor.Level").fromData(data))
        assert(assert(World.fromLevelData(data)):dispose())
    end
end)

local function withLoader(loadClass, callback)
    local LuaScript = require("project.LuaScript")
    local previous = LuaScript.loader
    LuaScript.loader = function() return loadClass end
    local ok, err = pcall(callback)
    LuaScript.loader = previous
    assert(ok, err)
end

add("Failed preparation disposes partial project level and object bindings without lifecycle callbacks", function()
    for _, phase in ipairs({"project", "level", "object", "properties"}) do
        local handles, owners, loads, unloads = {}, {}, 0, 0
        local class = Script:extend({
            configure = function(self)
                owners[#owners + 1] = self.owner
                handles[#handles + 1] = require("core.Bounds").bind(self, function() return 0, 0, 1, 1 end)
            end,
            load = function() loads = loads + 1 end,
            unload = function() unloads = unloads + 1 end
        })
        withLoader(function(reference)
            if reference == "bad" then error("preparation failed") end
            return class
        end, function()
            local attachment = {id = "one", name = "one", source = "good"}
            local project = {scripts = {attachment}}
            local data = {lobjects = {}, scripts = {attachment}}
            if phase == "project" then project.scripts[2] = {id = "bad", name = "bad", source = "bad"}
            elseif phase == "level" then data.scripts[2] = {id = "bad", name = "bad", source = "bad"}
            elseif phase == "properties" then data.propertyOverrides = {unknown = 1}
            else
                data.lobjects = {{authoringId = 1, transform = {x = 0, y = 0}, scripts = {
                    attachment, {id = "bad", name = "bad", source = "bad"}}}}
            end
            local world, err = Loader.prepare(project, data)
            Assert.equal(nil, world); Assert.truthy(err)
            Assert.truthy(#handles > 0)
            for _, handle in ipairs(handles) do Assert.equal(true, handle.released) end
            Assert.equal(true, owners[1].disposed)
            Assert.equal(0, loads); Assert.equal(0, unloads)
        end)
    end
end)

add("Failed transition preparation preserves the borrowed project session and its bindings", function()
    local world = assert(Loader.create({}, {lobjects = {}}))
    local script = require("core.ScriptRuntime").attach(world.project, "existing", Script:extend({}))
    local handle = require("core.Bounds").bind(script, function() return 0, 0, 1, 1 end)
    local candidate, err = Loader.prepare({}, {lobjects = {}, propertyOverrides = {unknown = 1}}, world.project)
    Assert.equal(nil, candidate); Assert.truthy(err)
    Assert.equal(world, world.project.world)
    Assert.equal(nil, world.project.disposed); Assert.equal(nil, handle.released)
    assert(world:update(0)); assert(world:dispose())
    Assert.equal(true, handle.released)
end)

add("Validation releases prepared bindings while returning the object count without load or unload", function()
    local handles, projectHost = {}, nil
    local class = Script:extend({configure = function(self)
        if self.owner.scope == "project" then projectHost = self.owner end
        handles[#handles + 1] = require("core.Bounds").bind(self, function() return 0, 0, 1, 1 end)
    end, load = function() error("Validation must not load") end,
        unload = function() error("Validation must not unload") end})
    withLoader(function() return class end, function()
        local attachment = {id = "one", name = "one", source = "good"}
        local result = assert(Loader.validate({scripts = {attachment}}, {
            scripts = {attachment}, lobjects = {{authoringId = 1, transform = {x = 0, y = 0}, scripts = {attachment}}}}))
        Assert.equal(1, result.objects); Assert.equal(3, #handles)
        for _, handle in ipairs(handles) do Assert.equal(true, handle.released) end
        Assert.equal(true, projectHost.disposed)
    end)
end)

add("Game View restores graphics stack color scissor and transform after projection draw and debug errors", function()
    for _, phase in ipairs({"projection", "draw", "debug"}) do
        local world = World.new()
        require("core.Rendering").createView(world, {projection = function()
            if phase == "projection" then error("projection failed") end
            return {width = 100, height = 100}
        end})
        local game = require("editor.GameView").new(); game:setViewport(10, 20, 200, 150)
        if phase == "draw" then game.drawRuntimeLObjects = function() error("draw failed") end end
        if phase == "debug" then world.debug = {drawShapes = function() end,
            drawScreens = function() error("debug failed") end} end
        love.graphics.push("all")
        local ok, err = pcall(function()
            love.graphics.setColor(0.25, 0.5, 0.75, 1)
            love.graphics.setScissor(1, 2, 30, 40)
            love.graphics.translate(3, 4)
            local depth, x, y = love.graphics.getStackDepth(), love.graphics.transformPoint(0, 0)
            local drawn, failure = pcall(game.draw, game, world)
            local after = love.graphics.getStackDepth()
            -- 회귀 시에도 다음 테스트의 그래픽 스택을 오염시키지 않는다.
            while love.graphics.getStackDepth() > depth do love.graphics.pop() end
            Assert.equal(false, drawn); Assert.truthy(tostring(failure):find(phase .. " failed", 1, true))
            Assert.equal(depth, after)
            local red, green, blue, alpha = love.graphics.getColor()
            Assert.equal(0.25, red); Assert.equal(0.5, green); Assert.equal(0.75, blue); Assert.equal(1, alpha)
            local sx, sy, sw, sh = love.graphics.getScissor()
            Assert.equal(1, sx); Assert.equal(2, sy); Assert.equal(30, sw); Assert.equal(40, sh)
            local ax, ay = love.graphics.transformPoint(0, 0)
            Assert.equal(x, ax); Assert.equal(y, ay)
        end)
        love.graphics.pop(); assert(world:dispose()); assert(ok, err)
    end
end)

add("Script attachment and ID lists reject holes maps and mixed keys without truncation", function()
    local Attachments = require("project.ScriptAttachments")
    for _, ids in ipairs({false, {"a", "b", "c", "d"}, {extra = "a"}, {[2] = "a"}, {"a", extra = "b"}}) do
        if type(ids) == "table" and #ids == 4 then ids[2] = nil end
        Assert.equal(nil, Attachments.validateIds(ids))
        local list = ids
        if type(ids) == "table" then
            list = {}; for key, id in pairs(ids) do list[key] = {id = id, source = "Script"} end
        end
        Assert.equal(nil, Attachments.validate(list))
    end
    Assert.truthy(Attachments.validateIds({})); Assert.truthy(Attachments.validate({}))
    Assert.equal(2, #assert(Attachments.validate({{id = "a", source = "Script"}, {id = "b", source = "Script"}})))
end)

add("Editor isolates projection errors during update resize events wheel input and Play startup", function()
    for _, phase in ipairs({"update", "resize", "event", "wheel", "start"}) do
        local app = require("editor.EditorApp").new()
        local world, unloads = World.new(), 0
        local object = assert(world:addLObject({transform = {x = 0, y = 0}}))
        require("core.ScriptRuntime").attach(object, "cleanup", Script:extend({unload = function() unloads = unloads + 1 end}))
        assert(object:load(world))
        require("core.Rendering").createView(world, {projection = function() error("projection failed") end})
        app.gameView:setViewport(0, 0, 800, 600)
        app.runtimeWorld = phase ~= "start" and world or nil
        local create = Loader.create
        if phase == "start" then Loader.create = function() return world end end
        local ok, err = pcall(function()
            if phase == "update" then app:update(0.1)
            elseif phase == "resize" then app:updateSceneViewport()
            elseif phase == "event" then app:gameEvent("focus", true)
            elseif phase == "wheel" then app:wheelmoved(0, 1)
            else app:startPlay() end
        end)
        Loader.create = create
        assert(ok, err)
        Assert.equal(nil, app.runtimeWorld); Assert.equal(true, world.disposed)
        Assert.equal(1, unloads); Assert.truthy(app.runtimeError:find("projection failed", 1, true))
    end
end)

add("Failed Spawn removes its objects after existing objects disappear and reports cleanup errors", function()
    local Fs = require("editor.HostFileSystem")
    local project = assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "Lifecycle_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
    assert(project:createEntry("Assets", "lua", "Failure", {scriptKind = "script"}))
    assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/Failure.lua")), [[
local Failure = {properties = {extra = {type = "prefab", default = false}, cleanupError = {type = "boolean", default = false}}}
function Failure:load(world)
    for _, object in ipairs(world:getObjects()) do if object.name == "Old" then assert(world:removeLObject(object)) end end
    assert(world:spawnLObject(self.extra))
    error("spawn load failed")
end
function Failure:unload()
    self:getWorld().unloads = (self:getWorld().unloads or 0) + 1
    if self.cleanupError then error("cleanup failed") end
end
return Failure
]]))
    assert(project:createEntry("Assets", "prefab", "PF_Extra"))
    assert(project:createEntry("Assets", "prefab", "PF_Failure", {prefabData = {
        formatVersion = 4, name = "Failure", scripts = {{id = "failure", source = project:getAssetId("Assets/Failure.lua")}},
        overrides = {scripts = {failure = {extra = project:getAssetId("Assets/PF_Extra.prefab")}}}}}))
    for _, cleanupError in ipairs({false, true}) do
        local world = assert(Loader.create(project, {lobjects = {
            {authoringId = 1, name = "Keep", transform = {x = 0, y = 0}},
            {authoringId = 2, name = "Old", transform = {x = 0, y = 0}}}}))
        local keep = world.lobjects[1]
        local value, err = world:spawnLObject("Assets/PF_Failure.prefab", nil, {scripts = {failure = {cleanupError = cleanupError}}})
        Assert.equal(nil, value); Assert.truthy(err:find("spawn load failed", 1, true))
        if cleanupError then Assert.truthy(err:find("cleanup failed", 1, true)) end
        Assert.equal(1, #world.lobjects); Assert.equal(keep, world.lobjects[1]); Assert.equal(1, world.unloads)
        assert(world:dispose())
    end
end)

return tests
