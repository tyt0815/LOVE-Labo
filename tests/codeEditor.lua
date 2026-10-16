local Assert = require("tests.Assert")
local Editor = require("editor.CodeEditor")
local Fs = require("editor.HostFileSystem")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
add("Code editor discovers VS Code and encodes arguments without a command shell", function()
    local path = Editor.detect({}, function(name) if name == "PATH" then return 'C:/Tools/VS Code/bin' end end,
        function(file) if file == 'C:/Tools/VS Code/Code.exe' then return {type = "file"} end end)
    Assert.equal('C:/Tools/VS Code/Code.exe', path)
    Assert.equal('"C:/한글 파일/$(unsafe)&.lua"', Editor.quote('C:/한글 파일/$(unsafe)&.lua'))
    Assert.equal('"a\\\"b\\\\"', Editor.quote('a"b\\'))
    Assert.equal(false, pcall(Editor.quote, "bad\0path"))
end)
add("Code opening resolves IDs and protects plugin sources with readonly preview copies", function()
    local project = assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "CodeEditor_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
    assert(project:createEntry("Assets", "folder", "한글 폴더"))
    assert(project:createEntry("Assets/한글 폴더", "lua", "Movement", {scriptKind = "script"}))
    local id = project:getAssetId("Assets/한글 폴더/Movement.lua")
    local settings = {executable = "C:/Program Files/LOVE/lovec.exe", arguments = {"--reuse-window", "{file}"}}
    local calls = 0
    local plan = Editor.open(project, id, false, settings, function(request)
        calls = calls + 1; Assert.equal(2, #request.arguments); return 123
    end)
    Assert.equal(1, calls); Assert.equal(123, plan.processId); Assert.equal(false, plan.readOnly)
    Assert.equal(project:resolveSourceFile(id), plan.path)
    assert(require("editor.PluginOperations").apply(project, "LaboEssentials", true, true))
    local original = assert(project:readSource(project.plugins.scripts.Camera.id))
    local preview = Editor.open(project, "Camera", false, settings, function() return 124 end)
    Assert.equal(true, preview.readOnly); Assert.truthy(preview.path:find("/.labo/CodePreview/", 1, true))
    Assert.equal(original, Fs.read(preview.path))
    Assert.equal(false, Fs.writeAtomic(preview.path, "modified"))
    Assert.equal(original, project:readSource(project.plugins.scripts.Camera.id))
    Editor.open(project, "Camera", false, settings, function() return 125 end)
    local request = require("editor.Cli").parse({"--cli", "script", "open", "--project", project.rootPath, "--script", id, "--dry-run"})
    Assert.equal("script.open", request.command); Assert.equal(true, request["dry-run"])
end)
return tests
