local Verification = {}
-- 배포된 실행 파일의 실제 에디터·CLI·런타임 경로를 새 프로젝트에서 검증한다.
function Verification.run(args)
    local directory
    for index, value in ipairs(args or {}) do if value == "--verify-package" then directory = args[index + 1] end end
    local Fs, Json = require("editor.HostFileSystem"), require("project.Json")
    local result, ownsDirectory = {version = 1, ok = false, checks = {}}, false
    local function check(name, condition) assert(condition, name); result.checks[#result.checks + 1] = name end
    local ok, err = xpcall(function()
        assert(directory and directory:sub(1, 2) ~= "--", "--verify-package requires a new directory")
        check("fused executable", love.filesystem.isFused())
        check("tests excluded", not love.filesystem.getInfo("tests/Runner.lua"))
        check("external settings", not love.filesystem.getInfo("editor/settings.json"))
        check("bundled fonts", love.filesystem.getInfo("editor/fonts/NanumSquareRoundR.ttf"))
        check("component API removed", require("Engine").SceneComponent == nil and require("Engine").LObjectComponent == nil)
        check("script API available", require("Engine").Script and love.filesystem.getInfo("plugins/LaboEssentials/plugin.json"))
        assert(not Fs.info(directory), "Verification directory must not exist")
        assert(Fs.mkdir(directory)); ownsDirectory = true
        local project = assert(require("editor.Project").create(directory, "PackageTest"))
        for _, name in ipairs({"LaboEssentials"}) do assert(require("editor.PluginOperations").apply(project, name, true, true)) end
        local Cli = require("editor.Cli")
        local function run(command, fields)
            fields = fields or {}; fields.command, fields.project = command, project.rootPath
            local response = Cli.execute(fields); assert(project:rebuildAssetIndex()); return response
        end
        local source = run("script.create", {name = "Movement"}).assetId
        run("script.set-source", {class = source, source = [[-- labo-script: script
local Movement = {properties = {speed = {type = "number", default = 10, group = "Movement"},
started = {type = "boolean", default = false}}}
function Movement.load(self) self.started = true end
function Movement.update(self, dt) self.owner.transform.x = self.owner.transform.x + self.speed * dt end
return Movement
]]})
        local prefab = run("prefab.create", {name = "PF_Player"}).assetId
        run("prefab.script.add", {prefab = prefab, source = source, script = "movement"})
        run("prefab.script.add", {prefab = prefab, source = "Sprite", script = "sprite"})
        local image = love.image.newImageData(64, 64); image:mapPixel(function() return 0.1, 0.65, 0.95, 1 end)
        local png = image:encode("png"); assert(Fs.writeAtomic(project:resolvePath("Assets/Player.png"), png:getString()))
        png:release(); image:release(); assert(project:rebuildAssetIndex())
        run("prefab.set", {prefab = prefab, property = "sprite.image", value = project:getAssetId("Assets/Player.png")})
        local level = run("level.create", {name = "L_Start"}).assetId
        run("project.set-default", {level = level})
        run("instance.add", {prefab = prefab, x = 0, y = 0})
        check("single Assets root", Fs.info(Fs.join(project.rootPath, "Assets")) and not Fs.info(Fs.join(project.rootPath, "Sources")))
        check("project AI instructions", Fs.info(Fs.join(project.rootPath, "AGENTS.md")) and Fs.info(Fs.join(project.rootPath, "Docs/EngineGuide.md")))
        check("CLI validation", run("project.validate").valid)
        local app = require("editor.EditorApp").new(nil, project)
        assert(app:openProjectDocument("Assets/L_Start.level", true))
        assert(app:inspectAsset("Assets/L_Start.level"))
        app:draw(); check("level Main Camera", app.inspector.classInspector.class.properties["$mainCamera"])
        assert(app.inspector.classInspector.target:addScript("Script", "levelState")); app.inspector.classInspector:reload()
        app:showProjectInspector()
        assert(app.inspector.classInspector.target:addScript("Script", "sessionState")); app.inspector.classInspector:reload()
        check("Project Inspector", app.inspector.classInspector.target.label == "Project")
        local camera = app.spriteAssets:preview(app.level.lobjects[1]):getScriptByName("Camera")
        check("camera outline", #app.sceneView:getCameraBounds(camera) == 8)
        local player = app.level.lobjects[2]; app.inspectorSource = "scene"; app.sceneView:setSelection({player}); app:updateInspectorTarget(); app:draw()
        local inspector = app.inspector.classInspector
        check("instance local scripts editable", inspector.target.instance and inspector.target.addScript and inspector.target.removeScript)
        check("single object Transform", inspector.class.properties["$transform.x"] and not inspector.class.properties["sprite.x"])
        check("nested script groups", inspector.tree == nil and inspector.class.properties[inspector.preview:getScriptByName("movement").id .. ".speed"])
        assert(app:inspectAsset("Assets/PF_Player.prefab")); app:draw(); app:recordHistory()
        check("Prefab scripts editable", inspector.target.addScript and inspector.target.removeScript)
        assert(inspector.target:addScript("RectBounds", "rect")); inspector:reload(); app:recordHistory()
        check("attachment visible", inspector.preview:getScriptByName("rect") ~= nil)
        assert(app:undoRedo(-1)); check("attachment Undo", inspector.preview:getScriptByName("rect") == nil)
        assert(app:undoRedo(1)); check("attachment Redo", inspector.preview:getScriptByName("rect") ~= nil)
        assert(inspector.target:removeScript("rect")); inspector:reload()
        assert(inspector:setProperty("movement.speed", 25))
        assert(app:startPlay()); check("runtime load", app.runtimeWorld.lobjects[2]:getScriptByName("movement").started)
        check("Project and Level runtime attachments", app.runtimeWorld.project:getScriptByName("sessionState") and app.runtimeWorld:getScriptByName("levelState"))
        assert(app.runtimeWorld:update(1)); check("live unsaved override", app.runtimeWorld.lobjects[2].transform.x == 25)
        app:draw(); app:stopPlay(); check("Stop preserves authoring", player.transform.x == 0)
        check("unsaved draft Export", require("editor.Export").write(project, app.level, Fs.join(directory, "Game.love")))
        local canvas = love.graphics.newCanvas(love.graphics.getDimensions())
        love.graphics.push("all"); love.graphics.setCanvas(canvas); app:draw(); love.graphics.setCanvas(); love.graphics.pop()
        local pixels = canvas:newImageData(); local preview = pixels:encode("png")
        assert(Fs.writeAtomic(Fs.join(directory, "preview.png"), preview:getString()))
        preview:release(); pixels:release(); canvas:release()
        result.projectDirectory, result.theme, result.ok = project.rootPath, require("editor.Theme").name, true
    end, debug.traceback)
    if not ok then result.error = err end
    if not ownsDirectory then print(result.error); love.event.quit(1); return end
    local saved, saveError = Fs.writeAtomic(Fs.join(directory, "report.json"), assert(Json.encode(result, true)))
    if not saved then print(saveError) end
    love.event.quit(ok and saved and 0 or 1)
end
return Verification
