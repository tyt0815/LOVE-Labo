local Assert = require("tests.Assert")
local Fs = require("editor.HostFileSystem")
local Config = require("editor.GameConfig")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function fixture()
    return assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "AttachedTest_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
end
local function rejects(fn, pattern)
    local ok, err = pcall(fn)
    assert(not ok and (not pattern or tostring(err):find(pattern, 1, true)), tostring(err))
end
add("Game configuration template is preserved and missing legacy configuration is generated", function()
    local project = fixture(); local path = Config.ensure(project)
    Assert.equal(Config.template(project.name), assert(Fs.read(path)))
    local custom = 'function love.conf(config) config.window.title = "Custom" end'
    assert(Fs.writeAtomic(path, custom)); Assert.equal(custom, Config.read(project))
    assert(Fs.removeFile(path)); Assert.equal(path, Config.ensure(project))
    Assert.equal(Config.template(project.name), assert(Fs.read(path)))
end)
add("Game configuration export checks syntax without executing user initialization", function()
    local project = fixture(); local path = Config.ensure(project)
    assert(Fs.writeAtomic(path, 'error("configuration must only execute in the game")'))
    local level = require("editor.Level").new()
    assert(require("editor.GamePackage").write(project, level, Fs.join(project.rootPath, "Build/Game.love")))
    assert(Fs.writeAtomic(path, 'function love.conf(config) broken syntax end'))
    rejects(function() require("editor.GamePackage").write(project, level, Fs.join(project.rootPath, "Build/Bad.love")) end, "conf.lua")
    -- 게임 CLI는 게임의 초기 설정 파일을 로딩하지 않는다.
    assert(require("editor.GamePackage").write(project, level, Fs.join(project.rootPath, "Build/Cli.love"), {cliEntry = "Assets/Commands.lua"}))
end)
add("Configuration wrapper preserves startup settings maps asset icons and protects the save identity", function()
    local project = fixture()
    local code = 'function love.conf(config) config.window.title = "Custom"; config.window.width = 1024; config.window.height = 640; config.window.vsync = 0; config.window.icon = "icon-id" end'
    local environment = setmetatable({love = {filesystem = {read = function() return '{"metadata":{"Assets/Icon.png":{"id":"icon-id"}}}' end}}}, {__index = _G})
    environment.require = function(name)
        if name == "ProjectConf" then local chunk = assert(loadstring(code)); setfenv(chunk, environment); return chunk() end
        return require(name)
    end
    local chunk = assert(loadstring(Config.wrapper(project))); setfenv(chunk, environment); chunk()
    local settings = {window = {}, modules = {}}
    environment.love.conf(settings)
    Assert.equal("Custom", settings.window.title); Assert.equal(1024, settings.window.width); Assert.equal(640, settings.window.height)
    Assert.equal(0, settings.window.vsync); Assert.equal("project/Assets/Icon.png", settings.window.icon)
    Assert.equal(project.saveIdentity, settings.identity)
    code = 'function love.conf(config) config.identity = "other-game" end'
    chunk = assert(loadstring(Config.wrapper(project))); setfenv(chunk, environment); chunk()
    rejects(function() environment.love.conf({window = {}}) end, "preserve the project save identity")
end)
add("Windows export exposes the platform bundles dependencies and keeps love output available", function()
    local project = fixture()
    assert(Fs.writeAtomic(require("editor.ProjectBuild").ensureScript(project), 'return function(builder) builder:log(builder.platform); builder:packageGame() end'))
    local level = require("editor.Level").new()
    local ok, report = require("editor.ProjectBuild").run(project, level, "Build/Windows/Game.exe", {platform = "windows"})
    assert(ok, report)
    Assert.equal("windows", report.platform); Assert.equal("windows", report.logs[2])
    Assert.truthy(#report.artifacts[1].dependencies > 0)
    local bytes = assert(Fs.read(report.output)); Assert.equal("MZ", bytes:sub(1, 2))
    Assert.truthy(Fs.info(Fs.join(report.outputDirectory, "love.dll")))
    Assert.truthy(Fs.info(Fs.join(report.outputDirectory, "license-love.txt")))
    Assert.equal(false, require("editor.ProjectBuild").run(project, level, "Build/Linux/Game.exe", {platform = "linux"}))
    assert(require("editor.ProjectBuild").run(project, level, "Build/Game.love"))
end)
add("Export form validates executable names handles both fields and shows startup access only for Project", function()
    local project = fixture(); local app = require("editor.EditorApp").new(nil, project)
    assert(app:showExportDialog()); local dialog = app.uiRoot.popup
    Assert.equal("windows", dialog.platform)
    dialog:dispatch("keypressed", "tab"); Assert.equal(2, dialog.active)
    dialog:dispatch("textinput", "../../Game.exe"); Assert.equal(false, dialog:submit())
    Assert.equal(dialog, app.uiRoot.popup)
    dialog.fields[2].text = "Game.exe"; dialog.fields[2].replace = true
    assert(dialog:submit()); Assert.equal("Build complete", app.uiRoot.popup.options.title)
    app.uiRoot:dismissPopup()
    local projectTarget = app.scopeInspector:projectTarget()
    Assert.equal("Game startup", projectTarget.documentActions[1].label)
    local editor = require("editor.CodeEditor")
    local original, opened = editor.openStartup, 0
    editor.openStartup = function(target) Assert.equal(project, target); opened = opened + 1; return {} end
    local clicked, clickError = pcall(function()
        app:showProjectInspector(); app:draw()
        local inspector = app.inspector.classInspector
        for _, row in ipairs(inspector.rows) do
            if row.documentAction then
                local rect = inspector:documentActionRect(inspector.propertyTop + row.offset - inspector.scroll)
                inspector:mousepressed(rect.x + 8, rect.y + 8, 1)
                break
            end
        end
        Assert.equal(1, opened)
    end)
    editor.openStartup = original
    assert(clicked, clickError)
    assert(project:createEntry("Assets", "level", "L_Start"))
    local levelTarget = app.scopeInspector:levelTarget(project:getAssetId("Assets/L_Start.level"))
    Assert.equal(nil, levelTarget.documentActions)
end)
return tests
