local Assert = require("tests.Assert")
local Fs, Json, Project = require("editor.HostFileSystem"), require("project.Json"), require("editor.Project")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function fixture()
    return assert(Project.create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "Identity_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
end
add("Save identities persist across reopen migration and project renaming and differ between games", function()
    local a, b = fixture(), fixture()
    Assert.truthy(a.id ~= b.id); Assert.truthy(a.saveIdentity ~= b.saveIdentity)
    local path = Fs.join(a.rootPath, "project.labo")
    local data = assert(Json.decode(assert(Fs.read(path)))); data.name = "Renamed game"
    assert(Fs.writeAtomic(path, assert(Json.encode(data))))
    local reopened = assert(Project.open(a.rootPath)); Assert.equal(a.saveIdentity, reopened.saveIdentity)
    data.id = nil; assert(Fs.writeAtomic(path, assert(Json.encode(data))))
    local migrated = assert(Project.open(a.rootPath)); local bytes = assert(Fs.read(path))
    Assert.truthy(require("project.AssetId").isValid(migrated.id))
    Assert.equal(migrated.id, assert(Project.open(a.rootPath)).id); Assert.equal(bytes, assert(Fs.read(path)))
    local output = Fs.join(a.rootPath, "Game.love")
    assert(require("editor.Export").write(migrated, require("editor.Level").new(), output))
    local archive = assert(Fs.read(output))
    Assert.truthy(archive:find('config.identity = "' .. migrated.saveIdentity .. '"', 1, true))
    Assert.equal(nil, archive:find('t.identity = "labo-exported-game"', 1, true))
    local info = require("editor.Cli").execute({command = "project.info", project = a.rootPath})
    Assert.equal(migrated.saveIdentity, info.saveIdentity)
    local reset = require("editor.Cli").execute({command = "project.reset-save-identity", project = a.rootPath})
    Assert.truthy(reset.id ~= migrated.id); Assert.equal(reset.saveIdentity, assert(Project.open(a.rootPath)).saveIdentity)
    Assert.equal(migrated.name, assert(Project.open(a.rootPath)).name)
end)
add("Travel example carries HUD input and saves versioned values then restores a new player", function()
    local project = fixture()
    local result = require("editor.Cli").execute({command = "project.examples-session", project = project.rootPath})
    project = assert(Project.open(project.rootPath))
    Assert.equal(true, require("editor.Cli").execute({command = "project.validate", project = project.rootPath}).valid)
    local stepped = require("editor.Cli").execute({command = "level.events", project = project.rootPath,
        level = result.level, ["step-dt"] = 0, events = {{name = "keypressed", args = {"n", "n", false}}}})
    Assert.equal(result.nextLevel, stepped.levelReference); Assert.equal("B", stepped.levelScripts.stage.stageName)
    Assert.equal(1, stepped.instances[1].scripts.traveller.visits)
    local world = assert(require("runtime.WorldLoader").create(project,
        assert(require("editor.LevelDocument").load(project:resolveAssetFile(result.level))).level:toData()))
    local files, original = {}, {}
    for _, key in ipairs({"read", "write", "createDirectory"}) do original[key] = love.filesystem[key] end
    local ok, err = pcall(function()
        love.filesystem.read = function(path) return files[path], "Missing save" end
        love.filesystem.write = function(path, data) files[path] = data; return true end
        love.filesystem.createDirectory = function() return true end
        local stage = world:getScriptByName("stage"); local player = stage.player
        local traveller = player:getScriptByName("traveller"); local session = world.project:getScriptByName("travelSession")
        local view = player:getScriptByName("view").renderView
        Assert.equal(true, view:isActive())
        Assert.equal(false, session:loadSlot()); Assert.equal(nil, world.pendingLevel)
        traveller.hp, traveller.gold, traveller.keys = 70, 11, 2; player.transform.x = 123
        love.filesystem.createDirectory = function() return false end
        Assert.equal(false, session:saveSlot(traveller, result.level)); Assert.equal("Could not create save directory", session.status)
        love.filesystem.createDirectory = function() return true end
        assert(session:saveSlot(traveller, result.level))
        local saved = assert(Json.decode(files[session.saveFile])); Assert.equal(1, saved.version)
        files[session.saveFile] = "corrupt"; Assert.equal(false, session:loadSlot())
        saved.version = 999; files[session.saveFile] = assert(Json.encode(saved)); Assert.equal(false, session:loadSlot())
        saved.version = 1; files[session.saveFile] = assert(Json.encode(saved))
        stage:keypressed("n"); world = assert(world:takeLevelTransition()); assert(world:update(0))
        local destination = world:getScriptByName("stage")
        Assert.equal(player, destination.player); Assert.equal("B", destination.stageName)
        Assert.equal(view, player:getScriptByName("view").renderView); Assert.equal(true, view:isActive())
        Assert.equal(70, traveller.hp); Assert.equal(123, player.transform.x)
        local rect = {x = 0, y = 0, width = 1280, height = 720}
        assert(require("core.RenderPipeline").pointer(world, "down", 40, 40, 1, 0, 0, function() end, rect))
        Assert.equal(12, traveller.gold)
        destination:keypressed("f"); local failed = world:takeLevelTransition(); Assert.equal(nil, failed)
        Assert.equal(world, player.world); Assert.equal(player, destination.player)
        Assert.equal(true, view:isActive())
        traveller.hp, traveller.gold = 10, 99
        assert(session:loadSlot()); world = assert(world:takeLevelTransition()); assert(world:update(0))
        local restored = world:getScriptByName("stage").traveller
        Assert.truthy(restored.owner ~= player); Assert.equal(70, restored.hp); Assert.equal(11, restored.gold)
        Assert.equal(2, restored.keys); Assert.equal(123, restored.owner.transform.x)
        Assert.equal(session, world.project:getScriptByName("travelSession")); Assert.equal(nil, session.pendingRestore)
        Assert.equal("A", world:getScriptByName("stage").stageName)
    end)
    for key, value in pairs(original) do love.filesystem[key] = value end
    assert(world:dispose()); assert(ok, err)
end)
return tests
