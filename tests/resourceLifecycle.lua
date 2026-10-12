local Assert = require("tests.Assert")
local World = require("core.World")
local Script = require("core.Script")
local Runtime = require("core.ScriptRuntime")
local Fs = require("editor.HostFileSystem")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function object(world) return assert(world:addLObject({transform = {x = 0, y = 0}})) end
local function fixture()
    return assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "Lifecycle_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
end

add("Object unload runs disabled scripts once child first with owner and world still available", function()
    local world, calls = World.new(), {}
    local parent, child = object(world), object(world); child:attachTo(parent)
    local class = Script:extend({unload = function(self, ...)
        Assert.equal(0, select("#", ...))
        local current = self.owner.world
        Assert.equal(world, current)
        calls[#calls + 1] = self.name
        assert(current:removeLObject(self.owner)) -- 자기 제거 재진입은 중복 종료하지 않는다.
    end})
    local first = Runtime.attach(parent, "first", class)
    Runtime.attach(parent, "second", class); Runtime.attach(child, "child", class)
    assert(parent:load(world)); assert(child:load(world)); first.enabled = false
    assert(world:removeLObject(parent)); Assert.equal("child,second,first", table.concat(calls, ","))
    Assert.equal(nil, first.owner); Assert.equal(0, #world.lobjects)
    assert(world:dispose()); Assert.equal(3, #calls)
end)

add("World disposal continues after unload errors and never initializes or unloads previews", function()
    local world, calls = World.new(), 0
    local loaded, preview = object(world), object(world)
    local class = Script:extend({unload = function() calls = calls + 1 end})
    Runtime.attach(loaded, "good", class); Runtime.attach(preview, "preview", class)
    Runtime.attach(loaded, "bad", Script:extend({unload = function() error("cleanup failed") end}))
    assert(loaded:load(world))
    local ok, err = world:dispose()
    Assert.equal(false, ok); Assert.truthy(err:find("cleanup failed", 1, true))
    Assert.equal(1, calls); Assert.equal(0, #world.lobjects)
    assert(world:dispose()); Assert.equal(1, calls)
    Assert.equal(nil, world:addLObject({transform = {x = 0, y = 0}}))
    Assert.equal(false, world:update(0.1)); Assert.equal(false, world:openLevel("x"))
end)

add("Failed Script load unloads partial resources and editor errors discard the runtime", function()
    local project = fixture()
    assert(project:createEntry("Assets", "lua", "Failure", {scriptKind = "script"}))
    assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/Failure.lua")), [[local Failure = {}
function Failure:load(world) world.debug:log("acquired"); error("load failed") end
function Failure:unload() self.owner.world.debug:log("released") end
return Failure]]))
    local debugSession = require("editor.DebugSession").new()
    local data = {lobjects = {{authoringId = 1, transform = {x = 0, y = 0}, scripts = {
        {id = "failure", source = project:getAssetId("Assets/Failure.lua")}}}}}
    local world, err = require("runtime.WorldLoader").create(project, data, debugSession)
    Assert.equal(nil, world); Assert.truthy(err:find("load failed", 1, true))
    Assert.equal("released", debugSession.history[2].text)
    local app = require("editor.EditorApp").new()
    world = World.new(); local owner = object(world); local released = 0
    Runtime.attach(owner, "error", Script:extend({update = function() error("update failed") end,
        unload = function() released = released + 1 end}))
    assert(owner:load(world)); app.runtimeWorld = world; app.gameView.world = world
    app:update(0.1); Assert.equal(nil, app.runtimeWorld); Assert.equal(1, released)
    Assert.equal(0, #world.lobjects)
end)

add("Audio references select by ID decode FileData and release on object removal and editor Stop", function()
    local root = Fs.join(love.filesystem.getSourceBaseDirectory(), "tests/TestProject")
    local project = assert(require("editor.Project").open(root))
    local level = assert(require("editor.LevelDocument").load(Fs.join(root, "Assets/Examples/L_AudioLifecycle.level")))
    local world = assert(require("runtime.WorldLoader").create(project, level.level:toData()))
    local owner = world.lobjects[#world.lobjects]; local script = owner:getScriptByName("AudioLifecycle")
    Assert.equal(project:getAssetId("Assets/Examples/Tone.wav"), script.sound)
    Assert.equal(true, script.data:typeOf("FileData")); Assert.equal(true, script.audioSource:typeOf("Source"))
    script.audioSource:setVolume(0); script.audioSource:play()
    assert(world:removeLObject(owner)); Assert.equal(nil, script.audioSource); Assert.equal(nil, script.data)
    assert(world:dispose())
    local app = require("editor.EditorApp").new(level, project); app:draw()
    local data = app.level.lobjects[#app.level.lobjects]
    app.sceneView:setSelection({data}); app:updateInspectorTarget(); app:draw()
    local inspector = app.inspector.classInspector
    local name = data.scripts[1].id .. ".sound"
    local id = project:getAssetId("Assets/Examples/Tone.wav")
    Assert.equal(id, inspector:pickCandidate(name, "Assets/Examples/Tone.wav"))
    Assert.equal(nil, inspector:pickCandidate(name, "Assets/Examples/Tile.png"))
    Assert.equal(false, inspector:setProperty(name, project:getAssetId("Assets/Examples/Tile.png")))
    assert(inspector:setProperty(name, id)); app:draw()
    local found = false
    for _, option in ipairs(inspector:choices(name, id).options) do if option.value == id then found = true end end
    Assert.equal(true, found)
    assert(app:startPlay()); local current = app.runtimeWorld.lobjects[#app.runtimeWorld.lobjects]:getScriptByName("AudioLifecycle")
    assert(app:pausePlay()); Assert.equal(false, current.hasUnloaded == true)
    assert(app:stopPlay()); Assert.equal(true, current.hasUnloaded); Assert.equal(nil, current.audioSource)
end)

add("CLI audio validation rejects invalid data and simulation closes its temporary session", function()
    local project = fixture()
    local wav = assert(Fs.read(Fs.join(love.filesystem.getSourceBaseDirectory(), "tests/TestProject/Assets/Examples/Tone.wav")))
    assert(Fs.writeAtomic(assert(project:resolvePath("Assets/Valid.wav")), wav))
    assert(Fs.writeAtomic(assert(project:resolvePath("Assets/Invalid.wav")), "not audio"))
    assert(project:rebuildAssetIndex())
    Assert.equal(true, require("project.AssetData").validateAudio(project, "Assets/Valid.wav"))
    Assert.equal(false, require("project.AssetData").validateAudio(project, "Assets/Invalid.wav"))
    local Cli = require("editor.Cli")
    local root = Fs.join(love.filesystem.getSourceBaseDirectory(), "tests/TestProject")
    local result = Cli.execute({command = "level.simulate", project = root, level = "Assets/Examples/L_AudioLifecycle.level", frames = 1, debug = true})
    local found = false
    for _, entry in ipairs(result.debug.history) do if entry.text:find("AudioLifecycle unloaded", 1, true) then found = true end end
    Assert.equal(true, found)
end)
add("Successful level transitions unload the old objects and keep destination audio alive", function()
    local root = Fs.join(love.filesystem.getSourceBaseDirectory(), "tests/TestProject")
    local project = assert(require("editor.Project").open(root))
    local reference = "Assets/Examples/L_AudioLifecycle.level"
    local data = assert(require("editor.LevelDocument").load(Fs.join(root, reference))).level:toData()
    local world = assert(require("runtime.WorldLoader").create(project, data))
    local oldScript = world.lobjects[#world.lobjects]:getScriptByName("AudioLifecycle")
    assert(world:openLevel(reference))
    local candidate = assert(world:takeLevelTransition())
    Assert.equal(true, world.disposed); Assert.equal(nil, oldScript.audioSource)
    local nextScript = candidate.lobjects[#candidate.lobjects]:getScriptByName("AudioLifecycle")
    Assert.equal(true, nextScript.audioSource:typeOf("Source"))
    assert(candidate:dispose()); Assert.equal(nil, nextScript.audioSource)
end)
add("Export Host quit unloads loaded objects once", function()
    local world = World.new(); local owner = object(world); local calls = 0
    Runtime.attach(owner, "cleanup", Script:extend({unload = function() calls = calls + 1 end}))
    assert(owner:load(world))
    local host = assert(loadstring(assert(love.filesystem.read("runtime/Host.lua")), "@runtime/Host.lua"))()
    local loader = require("runtime.WorldLoader")
    local create, read, requirePath = loader.create, love.filesystem.read, love.filesystem.getRequirePath()
    loader.create = function() return world end
    love.filesystem.read = function(path, ...)
        if path == "game.json" then return "{}" end
        return read(path, ...)
    end
    local ok, err = pcall(function()
        host.load({}); host.quit(); host.quit()
        Assert.equal(1, calls); Assert.equal(0, #world.lobjects)
    end)
    loader.create, love.filesystem.read = create, read
    love.filesystem.setRequirePath(requirePath); assert(ok, err)
end)
return tests
