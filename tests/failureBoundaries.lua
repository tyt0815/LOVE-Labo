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

return tests
