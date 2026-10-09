local Verification = {}

-- 배포된 실행 파일 자체에서 외부 프로젝트와 UI·런타임 경로를 점검한다.
-- 검사 결과와 생성 파일은 호출자가 지정한 새 폴더에만 남긴다.
function Verification.run(args)
    local directory
    for index, value in ipairs(args or {}) do
        if value == "--verify-package" then directory = args[index + 1] end
    end
    if not directory or directory:sub(1, 2) == "--" then
        print("--verify-package requires a new verification directory")
        love.event.quit(1); return
    end
    local FS = require("editor.host_filesystem")
    local Json = require("editor.json")
    local result = {version = 1, ok = false, checks = {}}
    local ownsDirectory = false
    local function check(name, condition)
        assert(condition, name)
        result.checks[#result.checks + 1] = name
    end
    local ok, err = xpcall(function()
        check("fused executable", love.filesystem.isFused())
        check("tests excluded", not love.filesystem.getInfo("tests/runner.lua"))
        check("settings outside archive", not love.filesystem.getInfo("editor/settings.json"))
        check("fonts bundled", love.filesystem.getInfo("editor/fonts/NanumSquareRoundR.ttf"))
        result.sourceDirectory = love.filesystem.getSourceBaseDirectory()
        local settings = assert(Json.decode(assert(FS.read(FS.join(result.sourceDirectory, "settings.json")))))
        check("external theme loaded", require("editor.theme").name == (settings.theme or "default"))
        assert(not FS.info(directory), "Verification directory must not exist")
        assert(FS.mkdir(directory))
        ownsDirectory = true
        local Project = require("editor.project")
        local project = assert(Project.create(directory, "패키징 검증 프로젝트"))
        assert(project:createEntry("Sources", "lua", "NewClass", {scriptKind = "lobject"}))
        local source = assert(project:resolveSourceFile("Sources/NewClass.lua"))
        check("class template", assert(FS.read(source)):find("local NewClass = {}", 1, true))
        check("class metadata", FS.info(source .. ".meta"))
        local classId = assert(project:getAssetId("Sources/NewClass.lua"))
        -- 사용자 프로젝트 코드와 이미지가 패키지 밖에서도 로딩되는지 확인한다.
        assert(FS.writeAtomic(source, [[-- labo-script: lobject
local NewClass = {properties = {speed = {type = "number", default = 10}}}
function NewClass.build(self) self:addComponent("sprite", require("engine").SpriteComponent) end
function NewClass.BeginPlay(self) self.begun = true end
return NewClass
]]))
        local pixels = love.image.newImageData(16, 16)
        pixels:mapPixel(function() return 0.2, 0.7, 1, 1 end)
        local encoded = pixels:encode("png")
        assert(FS.writeAtomic(assert(project:resolvePath("Assets/Sprite.png")), encoded:getString()))
        encoded:release(); pixels:release()
        assert(project:rebuildAssetIndex())
        assert(project:createEntry("Assets", "prefab", "NewPrefab", {scriptReference = classId}))
        assert(project:createEntry("Sources", "lua", "NewLevel", {scriptKind = "level"}))
        assert(project:createEntry("Assets", "level", "NewLevel", {scriptReference = project:getAssetId("Sources/NewLevel.lua")}))
        local levelPath = assert(project:resolveAssetFile("Assets/NewLevel.level"))
        local App = require("editor.app")
        local app = App.new(assert(require("editor.level_document").load(levelPath)), project)
        app:draw()
        local x, y = app.sceneView:worldToScreen(100, 200)
        assert(app:placePrefab("Assets/NewPrefab.prefab", x, y))
        local object = assert(app.sceneView.selectedLObject)
        app:updateInspectorTarget()
        local inspector = app.inspector.classInspector
        assert(inspector:setProperty("speed", 42))
        assert(inspector:setProperty("sprite.image", project:getAssetId("Assets/Sprite.png")))
        inspector:ensurePropertyVisible("sprite.image")
        app:draw()
        check("external image loaded", app.spriteAssets:image(project:getAssetId("Assets/Sprite.png")) ~= nil)
        assert(app:saveCurrentDocument(levelPath))
        local reopened = assert(Project.open(project.rootPath))
        local ProjectStart = require("editor.project_start")
        local openedProject
        local launcher = ProjectStart.new(function(opened)
            openedProject = opened
            return true
        end)
        launcher:draw()
        assert(require("editor.startup").openRequestedProject({"--project", project.rootPath}, launcher, love.filesystem.getWorkingDirectory()))
        check("project startup argument", openedProject and openedProject.rootPath == reopened.rootPath)
        local document = assert(require("editor.level_document").load(levelPath))
        local savedObject = assert(document.level.lobjects[1])
        check("instance placement saved", savedObject.transform.x == 100 and savedObject.transform.y == 200)
        check("property edit saved", savedObject.propertyOverrides.speed == 42)
        app = App.new(document, reopened)
        assert(app:startPlay())
        check("project class BeginPlay", app.runtimeWorld.lobjects[1].begun)
        app.gameView:draw()
        assert(app:stopPlay())
        app:draw()
        result.projectDirectory = project.rootPath
        result.theme = require("editor.theme").name
        local canvas = love.graphics.newCanvas(love.graphics.getDimensions())
        love.graphics.push("all")
        love.graphics.setCanvas(canvas); app:draw(); love.graphics.setCanvas()
        local screenshot = canvas:newImageData()
        local png = screenshot:encode("png")
        assert(FS.writeAtomic(FS.join(directory, "preview.png"), png:getString()))
        png:release(); screenshot:release(); canvas:release()
        love.graphics.pop()
        result.ok = true
    end, debug.traceback)
    if not ok then result.error = err end
    if not ownsDirectory then
        print(result.error); love.event.quit(1); return
    end
    local written, writeError = FS.writeAtomic(FS.join(directory, "report.json"), assert(Json.encode(result, true)) .. "\n")
    if not written then print(writeError) end
    love.event.quit(ok and written and 0 or 1)
end

return Verification
