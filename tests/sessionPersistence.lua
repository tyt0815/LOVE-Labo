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
    Assert.truthy(archive:find('t.identity = "' .. migrated.saveIdentity .. '"', 1, true))
    Assert.equal(nil, archive:find('t.identity = "labo-exported-game"', 1, true))
    local info = require("editor.Cli").execute({command = "project.info", project = a.rootPath})
    Assert.equal(migrated.saveIdentity, info.saveIdentity)
    local reset = require("editor.Cli").execute({command = "project.reset-save-identity", project = a.rootPath})
    Assert.truthy(reset.id ~= migrated.id); Assert.equal(reset.saveIdentity, assert(Project.open(a.rootPath)).saveIdentity)
    Assert.equal(migrated.name, assert(Project.open(a.rootPath)).name)
end)
return tests
