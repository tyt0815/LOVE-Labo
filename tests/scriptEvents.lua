local Assert = require("tests.Assert")
local World = require("core.World")
local Script = require("core.Script")
local Events = require("core.ScriptEvents")
local Runtime = require("core.ScriptRuntime")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function object(world) return assert(world:addLObject({transform = {x = 0, y = 0}})) end
local function withLoader(world, fn)
    local loader = require("runtime.WorldLoader")
    local create, read, getPosition = loader.create, love.filesystem.read, love.mouse.getPosition
    local requirePath = love.filesystem.getRequirePath()
    loader.create = function() return world end
    local ok, err = pcall(fn)
    loader.create, love.filesystem.read, love.mouse.getPosition = create, read, getPosition
    love.filesystem.setRequirePath(requirePath)
    assert(ok, err)
end
local function sizedWorld(viewWidth, viewHeight)
    local world = World.new()
    world.testViewSize = {width = viewWidth, height = viewHeight}
    require("Engine").Rendering.createView(world, {projection = function()
        return {width = world.testViewSize.width, height = world.testViewSize.height, transform = {x = 0, y = 0}}
    end})
    local script = Runtime.attach(object(world), "size", Script:extend({
        resize = function(self, width, height)
            self.width, self.height = width, height
            self.resizes = (self.resizes or 0) + 1
        end,
        update = function(self)
            assert(self.width and self.height, "resize must precede the first update")
            self.updates = (self.updates or 0) + 1
        end
    }))
    return world, script
end

add("Editor initializes resize before updates on Play resume and level transitions without drawing", function()
    local app = require("editor.EditorApp").new()
    local world, script = sizedWorld(200, 100)
    local candidate, nextScript = sizedWorld(100, 200)
    withLoader(world, function()
        assert(app:startPlay()); Assert.equal(1, script.resizes)
        assert(app:update(1 / 60)); Assert.equal(1, script.updates)
        assert(app:pausePlay())
        -- draw 없이 Pause 중 바뀐 게임 영역을 재개 시 반영한다.
        world.testViewSize.width, world.testViewSize.height = 100, 200
        assert(app:startPlay()); Assert.equal(2, script.resizes)
        local resumedViewport = app.gameView:runtimeViewport(world)
        Assert.equal(resumedViewport.width, script.width); Assert.equal(resumedViewport.height, script.height)
        world.applyLevelRequest = function() world.applyLevelRequest = nil; return candidate end
        assert(app:update(1 / 60)); Assert.equal(candidate, app.runtimeWorld)
        Assert.equal(1, nextScript.resizes); Assert.equal(nil, nextScript.updates)
        local viewport = app.gameView:runtimeViewport(candidate)
        Assert.equal(viewport.width, nextScript.width); Assert.equal(viewport.height, nextScript.height)
        assert(app:update(1 / 60)); Assert.equal(1, nextScript.updates)
        app:draw(); Assert.equal(1, nextScript.resizes)
    end)
end)

add("Editor reports initial resize failures from startPlay before any update", function()
    local app = require("editor.EditorApp").new()
    local world = World.new()
    Runtime.attach(object(world), "fail", Script:extend({resize = function() error("initial size failed") end}))
    withLoader(world, function()
        local ok, err = app:startPlay()
        Assert.equal(false, ok); Assert.equal(nil, app.runtimeWorld)
        Assert.truthy(err:find("initial size failed", 1, true))
    end)
end)

add("Editor wheel uses cursor location independently of keyboard focus and still respects pause popup", function()
    local app = require("editor.EditorApp").new()
    local world, calls = World.new(), 0
    Runtime.attach(object(world), "wheel", Script:extend({wheelmoved = function(_, x, y)
        Assert.equal(2, x); Assert.equal(-3, y); calls = calls + 1
    end}))
    withLoader(world, function()
        assert(app:startPlay()); app.uiRoot.focused = app.inspectorWidget
        local viewport = app.gameView:runtimeViewport(world)
        love.mouse.getPosition = function() return viewport.x + 10, viewport.y + 10 end
        app:wheelmoved(2, -3); Assert.equal(1, calls)
        assert(app:pausePlay()); app:wheelmoved(2, -3); Assert.equal(1, calls)
        assert(app:startPlay()); app.uiRoot.popup = {}
        app:wheelmoved(2, -3); Assert.equal(1, calls); app.uiRoot.popup = nil
        love.mouse.getPosition = function() return viewport.x - 1, viewport.y + 10 end
        app:wheelmoved(2, -3); Assert.equal(1, calls)
    end)
end)

add("Export Host initializes the destination resize before its first update after transition", function()
    local world, script = sizedWorld(200, 100)
    local candidate, nextScript = sizedWorld(100, 200)
    local host = assert(loadstring(assert(love.filesystem.read("runtime/Host.lua")), "@runtime/Host.lua"))()
    withLoader(world, function()
        local read = love.filesystem.read
        love.filesystem.read = function(path, ...)
            if path == "game.json" then return "{}" end
            return read(path, ...)
        end
        host.load({}); Assert.equal(1, script.resizes)
        world.applyLevelRequest = function() world.applyLevelRequest = nil; return candidate end
        host.update(1 / 60)
        Assert.equal(1, script.updates); Assert.equal(1, nextScript.resizes)
        Assert.equal(nil, nextScript.updates)
        local width, height = love.graphics.getDimensions()
        local viewport = require("core.Viewport").new(candidate, 0, 0, width, height)
        Assert.equal(viewport.width, nextScript.width); Assert.equal(viewport.height, nextScript.height)
        host.update(1 / 60); Assert.equal(1, nextScript.updates); Assert.equal(1, nextScript.resizes)
    end)
end)

add("LOVE script events broadcast in hierarchy attachment order and ignore return values", function()
    local world, calls = World.new(), {}
    local child, parent = object(world), object(world); child:attachTo(parent)
    local class = Script:extend({keypressed = function(self, key, scan, repeated)
        calls[#calls + 1] = self.name
        Assert.equal("space", key); Assert.equal("space", scan); Assert.equal(false, repeated)
        return false, "not an error"
    end})
    Runtime.attach(child, "child", class)
    Runtime.attach(parent, "first", class); Runtime.attach(parent, "second", class)
    assert(world:dispatchEvent("keypressed", "space", "space", false))
    Assert.equal("first,second,child", table.concat(calls, ","))
    for _, name in ipairs(Events.names) do
        local received
        local definition = {}; definition[name] = function(_, ...) received = select("#", ...); return true end
        local w = World.new(); Runtime.attach(object(w), "callback", Script:extend(definition))
        assert(w:dispatchEvent(name, 1, nil, false)); Assert.equal(3, received)
        Assert.equal(false, pcall(Script.extend, Script, {[name] = 42}))
        Assert.equal(false, pcall(Script.extend, Script, {properties = {[name] = {type = "number", default = 0}}}))
    end
    Assert.equal(false, world:dispatchEvent("quit"))
end)

add("Script event snapshots recheck enabled removal and defer newly spawned callbacks", function()
    local world, calls = World.new(), 0
    local first, second, doomed = object(world), object(world), object(world)
    local counter = Script:extend({keyreleased = function() calls = calls + 1 end}):extend({})
    local disabled = Runtime.attach(second, "disabled", counter)
    Runtime.attach(doomed, "doomed", counter)
    Runtime.attach(first, "first", Script:extend({keyreleased = function()
        disabled.enabled = false; world:removeLObject(doomed)
        Runtime.attach(object(world), "new", counter)
    end}))
    assert(world:dispatchEvent("keyreleased", "a", "a")); Assert.equal(0, calls)
    assert(world:dispatchEvent("keyreleased", "a", "a")); Assert.equal(1, calls)
    local failing = Runtime.attach(first, "failure", Script:extend({textinput = function() error("bad input") end}))
    local ok, err = world:dispatchEvent("textinput", "한글")
    Assert.equal(false, ok); Assert.truthy(err:find("bad input", 1, true)); Assert.equal(first, failing.owner)
end)

add("Raw mouse and touch events use game origin and preserve outside releases", function()
    local world, received = World.new(), {}
    local definition = {}
    for _, name in ipairs({"mousepressed", "mousereleased", "mousemoved", "touchpressed", "touchreleased"}) do
        local eventName = name
        definition[name] = function(_, ...) received[#received + 1] = {eventName, ...} end
    end
    Runtime.attach(object(world), "input", Script:extend(definition))
    local viewport = {x = 100, y = 200, width = 400, height = 300}
    assert(Events.screen(world, viewport, "mousepressed", 50, 210, 1, false, 2)); Assert.equal(0, #received)
    assert(Events.screen(world, viewport, "mousepressed", 110, 220, 1, false, 2))
    Assert.equal(10, received[1][2]); Assert.equal(20, received[1][3]); Assert.equal(false, received[1][5]); Assert.equal(2, received[1][6])
    assert(Events.screen(world, viewport, "mousemoved", 80, 180, -30, -40, true))
    Assert.equal(-20, received[2][2]); Assert.equal(-30, received[2][4])
    assert(Events.screen(world, viewport, "mousereleased", 80, 180, 1, false, 1))
    assert(Events.screen(world, viewport, "mousemoved", 80, 180, 0, 0, false)); Assert.equal(3, #received)
    local id = {} -- 실제 LÖVE의 터치 식별자도 변환 없이 유지한다.
    assert(Events.screen(world, viewport, "touchpressed", id, 120, 230, 0, 0, 0.5))
    assert(Events.screen(world, viewport, "touchreleased", id, 10, 20, -110, -210, 0))
    Assert.equal(id, received[4][2]); Assert.equal(20, received[4][3]); Assert.equal(-90, received[5][3])
    world:cancelPointer(); Assert.equal(nil, world.eventCaptures)
end)

add("Editor script events honor pause popup focus and report game dimensions", function()
    local app = require("editor.EditorApp").new()
    local world, received = World.new(), {}
    local definition = {}
    for _, name in ipairs({"keypressed", "keyreleased", "textinput", "textedited", "focus", "resize", "gamepadpressed"}) do
        local eventName = name; definition[name] = function(_, ...) received[eventName] = {...} end
    end
    Runtime.attach(object(world), "input", Script:extend(definition))
    app.runtimeWorld = world; app.gameView.world = world; app.uiRoot.focused = app.sceneWidget
    app:updateSceneViewport()
    local viewport = app.gameView:runtimeViewport(world)
    Assert.equal(viewport.width, received.resize[1]); Assert.equal(viewport.height, received.resize[2])
    app:keypressed("a", "a", true); Assert.equal(true, received.keypressed[3])
    app:textinput("한글"); Assert.equal("한글", received.textinput[1])
    app:textedited("ㅎ", 0, 1); Assert.equal(1, received.textedited[3])
    local joystick = {}; app:gameEvent("gamepadpressed", joystick, "a"); Assert.equal(joystick, received.gamepadpressed[1])
    assert(app:pausePlay()); app:gameEvent("keyreleased", "a", "a"); Assert.equal(nil, received.keyreleased)
    assert(app:startPlay()); app.uiRoot.focused = app.inspectorWidget
    app:gameEvent("keyreleased", "a", "a"); Assert.equal(nil, received.keyreleased)
    app.uiRoot.focused = app.sceneWidget; app.uiRoot.popup = {}
    app:gameEvent("keyreleased", "a", "a"); Assert.equal(nil, received.keyreleased)
    app.uiRoot.popup = nil; app:gameEvent("keyreleased", "a", "a"); Assert.equal("a", received.keyreleased[1])
    app:focus(false); Assert.equal(false, received.focus[1])
    local script = world.lobjects[1]:getScriptByName("input")
    script.textinput = function() error("editor event failure") end
    app:textinput("x"); Assert.equal(nil, app.runtimeWorld); Assert.truthy(app.runtimeError:find("editor event failure", 1, true))
end)

add("CLI script events exercise the input example without saving and reject unsupported events", function()
    local Fs = require("editor.HostFileSystem")
    local root = Fs.join(love.filesystem.getSourceBaseDirectory(), "tests/TestProject")
    local path = Fs.join(root, "Assets/Examples/L_InputEvents.level")
    local before = assert(Fs.read(path))
    local request = {command = "level.events", project = root, level = "Assets/Examples/L_InputEvents.level",
        events = {{name = "keypressed", args = {"right", "right", false}},
            {name = "textinput", args = {"Hello"}}, {name = "mousepressed", args = {640, 360, 1, false, 1}},
            {name = "mousereleased", args = {1500, 900, 1, false, 1}}}}
    local result = require("editor.Cli").execute(request)
    local instance = result.instances[#result.instances]
    Assert.equal(20, instance.transform.x); Assert.equal(4, instance.scripts.InputEvents.eventCount)
    Assert.equal("Hello", instance.scripts.InputEvents.inputText)
    Assert.equal(1500, instance.scripts.InputEvents.pointerX)
    Assert.equal(before, Fs.read(path))
    for _, name in ipairs({"quit", "gamepadpressed", "unknown"}) do
        request.events = {{name = name, args = {}}}
        Assert.equal(false, pcall(require("editor.Cli").execute, request))
    end
end)
return tests
