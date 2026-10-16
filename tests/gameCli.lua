local Assert = require("tests.Assert")
local Fs, Json = require("editor.HostFileSystem"), require("project.Json")
local Workspace, Commands = require("project.Workspace"), require("project.GameCommands")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function fixture()
    return assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "AttachedTest_Build_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
end
local function rejects(fn, pattern)
    local ok, err = pcall(fn)
    assert(not ok and (not pattern or tostring(err):find(pattern, 1, true)), tostring(err))
end
add("Project build template is created once and legacy export initializes only a missing script", function()
    local project = fixture()
    local build = require("editor.ProjectBuild")
    local path = build.ensureScript(project)
    Assert.equal(require("editor.BuildTemplate").text, assert(Fs.read(path)))
    assert(Fs.writeAtomic(path, 'return function(b) b:log("custom"); b:packageGame() end'))
    local output = Fs.join(project.rootPath, "Build/Game.love")
    local ok, report = build.run(project, require("editor.Level").new(), output)
    assert(ok, report); Assert.equal("custom", report.logs[2]); Assert.equal(1, #report.artifacts)
    Assert.truthy(assert(Fs.read(path)):find('"custom"', 1, true))
    assert(Fs.removeFile(path)); assert(Fs.removeDirectory(Fs.parent(path)))
    assert(build.run(project, require("editor.Level").new(), output))
    Assert.equal(require("editor.BuildTemplate").text, assert(Fs.read(path)))
end)
add("Build errors preserve logs and low level packaging bypasses the custom script", function()
    local project = fixture(); local root = Workspace.new(project.rootPath)
    root:write("Tools/Build.lua", 'return function(b) b:log("before failure"); error("broken build") end')
    local ok, err, report = require("editor.ProjectBuild").run(project, require("editor.Level").new(), "Build/Game.love")
    Assert.equal(false, ok); Assert.truthy(err:find("broken build", 1, true)); Assert.equal("before failure", report.logs[2])
    assert(project:createEntry("Assets", "level", "L_Test"))
    local result = require("editor.Cli").execute({command = "export.package", project = project.rootPath,
        level = "Assets/L_Test.level", output = Fs.join(project.rootPath, "Build/Raw.love")})
    Assert.truthy(Fs.info(result.output))
    Assert.equal(false, require("editor.ProjectBuild").run(project, require("editor.Level").new(), "Assets/Bad.love"))
end)
add("Workspace rejects escapes and detects revisions while releasing locks after errors", function()
    local project = fixture(); local workspace = Workspace.new(project.rootPath)
    for _, path in ipairs({"../escape", "x/../escape", "C:/escape", "x\\escape", "x//escape", "x/CON.txt", "x/escape.", "x:stream"}) do
        rejects(function() workspace:path(path) end)
    end
    local revision = workspace:writeJson("Content/Stage.json", {value = 1}, false)
    local data, actual = workspace:readJson("Content/Stage.json"); Assert.equal(revision, actual); Assert.equal(1, data.value)
    rejects(function() workspace:writeJson("Content/Stage.json", {}, false) end, "Revision conflict")
    local nextRevision = workspace:writeJson("Content/Stage.json", {value = 2}, revision)
    rejects(function() workspace:writeJson("Content/Stage.json", {}, revision) end, "Revision conflict")
    Assert.equal(nextRevision, select(2, workspace:read("Content/Stage.json")))
    workspace:withLock(function() rejects(function() workspace:withLock(function() end) end, "Workspace is busy") end)
    rejects(function() workspace:withLock(function() error("expected failure") end) end, "expected failure")
    Assert.equal(nil, Fs.info(workspace:path(".labo-content.lock")))
end)
add("Command schemas handle boolean false numeric conversion required and unknown parameters", function()
    local definition = {commands = {edit = {parameters = {enabled = {type = "boolean", required = true},
        count = {type = "integer", default = 2}}, run = function(_, args) return args end}}}
    local request = Commands.parse({"edit", "--enabled", "false", "--count", "-3"})
    local result = Commands.execute(definition, request)
    Assert.equal(false, result.enabled); Assert.equal(-3, result.count)
    Assert.equal("boolean", Commands.execute(definition, {command = "schema"}).commands.edit.parameters.enabled.type)
    rejects(function() Commands.execute(definition, {command = "edit", arguments = {}}) end, "Missing parameter")
    rejects(function() Commands.execute(definition, {command = "edit", arguments = {enabled = true, count = 1.5}}) end, "Invalid parameter")
    rejects(function() Commands.execute(definition, {command = "edit", arguments = {enabled = true, unknown = 2}}) end, "Unknown parameter")
    rejects(function() Commands.parse({"edit", "--enabled", "true", "--enabled", "false"}) end, "Duplicate parameter")
end)
add("Game commands and in game editor share stage validation and detect external changes", function()
    local project = fixture(); local example = require("editor.GameCliExamples").create(project)
    local workspace = Workspace.new(project.rootPath)
    local entry = example.entry
    local function run(command, arguments)
        return require("runtime.CliHost").execute(project, entry, {command = command, arguments = arguments, workspace = project.rootPath})
    end
    run("create", {name = "Test"})
    local first = run("inspect", {}); run("add", {beat = 4, lane = 3, revision = first.revision})
    rejects(function() run("add", {beat = 4, lane = 9}) end, "Invalid note lane")
    rejects(function() run("add", {beat = 4, lane = 1, revision = first.revision}) end, "Revision conflict")
    Assert.equal(1, #run("inspect", {}).data.notes)
    local level = assert(require("editor.LevelDocument").load(assert(project:resolveAssetFile(example.level)))).level
    level.scriptOverrides = {[level.scripts[1].id] = {workspace = project.rootPath}}
    local world = assert(require("runtime.WorldLoader").create(project, level:toData()))
    local editor = world:getScriptByName("stageEditor")
    Assert.equal(3, editor.data.notes[1].lane)
    editor:keypressed("left"); run("add", {beat = 8, lane = 4}); editor:keypressed("s")
    Assert.truthy(editor.status:find("Revision conflict", 1, true))
    editor:keypressed("r"); Assert.equal(2, #editor.data.notes); Assert.equal(3, editor.data.notes[1].lane)
    editor:keypressed("left"); editor:keypressed("s"); Assert.equal(2, run("inspect", {}).data.notes[1].lane)
    assert(world:dispose())
    assert(require("editor.Cli").execute({command = "project.validate", project = project.rootPath}).valid)
end)
add("CLI package bundles its runtime and documentation without Editor modules", function()
    local project = fixture(); local example = require("editor.GameCliExamples").create(project)
    local level = assert(require("editor.LevelDocument").load(assert(project:resolveAssetFile(example.level)))).level
    local ok, report = require("editor.ProjectBuild").run(project, level, "Build/Game.love")
    assert(ok, report); Assert.equal(4, #report.artifacts)
    local folder = report.outputDirectory
    Assert.truthy(Fs.info(Fs.join(folder, "Game-cli.exe"))); Assert.truthy(Fs.info(Fs.join(folder, "love.dll")))
    Assert.equal(require("editor.GameCliExamples").guide, assert(Fs.read(Fs.join(folder, "README.md"))))
    local bytes = assert(Fs.read(Fs.join(folder, "Game-cli.exe")))
    Assert.truthy(bytes:find('t.window = false', 1, true)); Assert.truthy(bytes:find('t.modules.audio = false', 1, true))
    Assert.equal(nil, bytes:find('editor/EditorApp.lua', 1, true))
    Assert.equal(nil, bytes:find('editor/HostFileSystem.lua', 1, true))
end)
add("Export GUI retains build reports and opens the result dialog", function()
    local project = fixture(); local app = require("editor.EditorApp").new(nil, project)
    assert(app:showExportDialog()); local dialog = app.uiRoot.popup
    dialog:submit()
    Assert.equal("Build complete", app.uiRoot.popup.options.title)
    Assert.truthy(app.lastBuildReport.artifacts[1].files > 0)
    app.uiRoot:dismissPopup(); assert(app:showBuildResults())
    Assert.equal("Close", app.uiRoot.popup.options.cancelLabel)
end)
add("Object and array parameters reject JSON null before invoking handlers", function()
    local calls = 0
    for _, kind in ipairs({"object", "array"}) do
        local definition = {commands = {edit = {parameters = {data = {type = kind, required = true}},
            run = function() calls = calls + 1 end}}}
        local request = assert(Json.decode('{"command":"edit","arguments":{"data":null}}'))
        rejects(function() Commands.execute(definition, request) end, "Invalid parameter: data")
        rejects(function() Commands.execute(definition, Commands.parse({"edit", "--data", "null"})) end, "Invalid parameter: data")
        local data = kind == "array" and Json.array({}) or {}
        Commands.execute(definition, {command = "edit", arguments = {data = data}})
    end
    Assert.equal(2, calls)
    rejects(function() Commands.execute({commands = {}}, assert(Json.decode('{"command":"help","arguments":null}'))) end, "Expected arguments object")
end)
add("Workspace JSON preserves false and its revision while rejecting malformed data", function()
    local workspace = Workspace.new(fixture().rootPath)
    local revision = workspace:writeJson("Content/False.json", false, false)
    local data, actual = workspace:readJson("Content/False.json")
    Assert.equal(false, data); Assert.equal(revision, actual)
    workspace:write("Content/False.json", "invalid", revision)
    rejects(function() workspace:readJson("Content/False.json") end)
end)
add("CLI host returns JSON and failure exit codes for invalid options and response write failures", function()
    local Host = require("runtime.CliHost")
    local workspace = Workspace.new(fixture().rootPath)
    local original = {stdout = io.stdout, quit = love.event.quit, read = love.filesystem.read,
        execute = Host.execute, writeAtomic = Fs.writeAtomic}
    local output, exitCode, calls = "", nil, 0
    local ok, err = pcall(function()
        io.stdout = {write = function(_, bytes) output = output .. bytes end, flush = function() end}
        love.event.quit = function(code) exitCode = code end
        love.filesystem.read = function(path, ...)
            if path == "game.json" then return '{"cliEntry":"Assets/Commands.lua"}' end
            return original.read(path, ...)
        end
        Host.execute = function() calls = calls + 1; return {valid = true} end
        local function run(args)
            output, exitCode = "", nil
            Host.run(args)
            Assert.equal(1, exitCode)
            local response = assert(Json.decode(output))
            Assert.equal(1, response.version); Assert.equal(false, response.ok)
            Assert.equal("string", type(response.error))
            return response.error
        end
        for _, option in ipairs({"result", "workspace", "request"}) do
            for _, value in ipairs({true, false, Json.null, 1, {}}) do
                workspace:writeJson("request.json", {command = "help", [option] = value})
                Assert.truthy(run({"--request", workspace:path("request.json")}):find("Invalid host option: " .. option, 1, true))
            end
        end
        Assert.equal(0, calls)
        Fs.writeAtomic = function() error("response write exception") end
        Assert.truthy(run({"help", "--result", workspace:path("result.json")}):find("response write exception", 1, true))
        Fs.writeAtomic = function() return false, "response write failure" end
        Assert.equal("response write failure", run({"help", "--result", workspace:path("result.json")}))
        Fs.writeAtomic = original.writeAtomic
        output, exitCode = "", nil
        Host.run({"help", "--result", workspace:path("result.json")})
        Assert.equal(0, exitCode); Assert.equal(output, assert(Fs.read(workspace:path("result.json"))))
        Assert.equal(true, assert(Json.decode(output)).ok)
    end)
    io.stdout, love.event.quit, love.filesystem.read = original.stdout, original.quit, original.read
    Host.execute, Fs.writeAtomic = original.execute, original.writeAtomic
    assert(ok, err)
end)
return tests
