local Verification = {}

-- 배포된 실행 파일 자체에서 외부 프로젝트와 Ui·런타임 경로를 점검한다.
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
    local Fs = require("editor.HostFileSystem")
    local Json = require("editor.Json")
    local result = {version = 1, ok = false, checks = {}}
    local ownsDirectory = false
    local function check(name, condition)
        assert(condition, name)
        result.checks[#result.checks + 1] = name
    end
    local ok, err = xpcall(function()
        check("fused executable", love.filesystem.isFused())
        check("tests excluded", not love.filesystem.getInfo("tests/Runner.lua"))
        check("settings outside archive", not love.filesystem.getInfo("editor/settings.json"))
        check("fonts bundled", love.filesystem.getInfo("editor/fonts/NanumSquareRoundR.ttf"))
        result.sourceDirectory = love.filesystem.getSourceBaseDirectory()
        local settings = assert(Json.decode(assert(Fs.read(Fs.join(result.sourceDirectory, "settings.json")))))
        check("external theme loaded", require("editor.Theme").name == (settings.theme or "default"))
        assert(not Fs.info(directory), "Verification directory must not exist")
        assert(Fs.mkdir(directory))
        ownsDirectory = true
        local Project = require("editor.Project")
        local project = assert(Project.create(directory, "패키징 검증 프로젝트"))
        assert(project:createEntry("Sources", "lua", "NewClass", {scriptKind = "lobject"}))
        local source = assert(project:resolveSourceFile("Sources/NewClass.lua"))
        check("class template", assert(Fs.read(source)):find("local NewClass = {}", 1, true))
        check("class metadata", Fs.info(source .. ".meta"))
        local classId = assert(project:getAssetId("Sources/NewClass.lua"))
        assert(project:createEntry("Sources", "lua", "Branch", {scriptKind = "component", parentReference = "SceneComponent"}))
        local branchId = project:getAssetId("Sources/Branch.lua")
        assert(Fs.writeAtomic(assert(project:resolveSourceFile(branchId)), [[
local Branch = {extends = "SceneComponent", properties = {speed = {type = "number", default = 2, group = "Movement"}}}
function Branch.build(self) self:addComponent("sprite", require("Engine").SpriteComponent) end
function Branch.beginPlay(self) self.begun = true end
return Branch
]]))
        -- 사용자 프로젝트 코드와 이미지가 패키지 밖에서도 로딩되는지 확인한다.
        assert(Fs.writeAtomic(source, string.format([[-- labo-script: lobject
local NewClass = {properties = {speed = {type = "number", default = 10},
    target = {type = "object", default = false}, projectile = {type = "prefab", default = false}}}
function NewClass.build(self) self:setRootComponent("root", %q) end
function NewClass.beginPlay(self) self.begun = true end
return NewClass
]], branchId)))
        local pixels = love.image.newImageData(16, 16)
        pixels:mapPixel(function() return 0.2, 0.7, 1, 1 end)
        local encoded = pixels:encode("png")
        assert(Fs.writeAtomic(assert(project:resolvePath("Assets/Sprite.png")), encoded:getString()))
        encoded:release(); pixels:release()
        assert(project:rebuildAssetIndex())
        assert(project:createEntry("Assets", "prefab", "NewPrefab", {scriptReference = classId}))
        assert(project:createEntry("Sources", "lua", "NewLevel", {scriptKind = "level"}))
        assert(project:createEntry("Assets", "level", "NewLevel", {scriptReference = project:getAssetId("Sources/NewLevel.lua")}))
        local levelPath = assert(project:resolveAssetFile("Assets/NewLevel.level"))
        local App = require("editor.EditorApp")
        local app = App.new(assert(require("editor.LevelDocument").load(levelPath)), project)
        app:draw()
        local function preview(name)
            local canvas = love.graphics.newCanvas(love.graphics.getDimensions())
            love.graphics.push("all")
            love.graphics.setCanvas(canvas); app:draw(); love.graphics.setCanvas()
            local pixels = canvas:newImageData()
            local png = pixels:encode("png")
            assert(Fs.writeAtomic(Fs.join(directory, name .. ".png"), png:getString()))
            png:release(); pixels:release(); canvas:release()
            love.graphics.pop()
        end
        app.assetBrowser:showCreateDialog("Sources", "lua")
        local componentDialog = app.uiRoot.popup
        local collapsed = true
        for _, expanded in pairs(componentDialog.options.content.expanded) do collapsed = collapsed and not expanded end
        check("Lua class parent tree collapsed", collapsed and #componentDialog.options.content.nodes == 3)
        preview("create-parent-collapsed")
        componentDialog.options.content:choose(componentDialog.options.content.records[branchId])
        preview("create-component-parent")
        componentDialog:submit(); app.uiRoot.popup.text = "ChildBranch"; app.uiRoot.popup:submit()
        check("derived component created", require("project.LuaClass").load(project, project:getAssetId("Sources/ChildBranch.lua"), "component").extends == branchId)
        app.assetBrowser:showCreateDialog("Sources", "lua")
        local dialog = app.uiRoot.popup
        dialog.options.content:choose(dialog.options.content.records[classId])
        preview("create-parent")
        dialog:submit()
        check("creation next step", app.uiRoot.popup and app.uiRoot.popup ~= dialog and app.uiRoot.popup.options.input)
        preview("create-location")
        app.uiRoot.popup.text = "ChildClass"; app.uiRoot.popup:submit()
        check("derived class created", require("project.LuaClass").load(project, project:getAssetId("Sources/ChildClass.lua"), "lobject").extends == classId)
        app.assetBrowser:showCreateDialog("Assets", "prefab")
        dialog = app.uiRoot.popup
        local prefabId = project:getAssetId("Assets/NewPrefab.prefab")
        dialog.options.content:choose(dialog.options.content.records[prefabId])
        preview("create-prefab-parent")
        dialog:submit()
        check("prefab name prefix focused", app.uiRoot.popup.text == "PF_" and not app.uiRoot.popup.contentFocused
            and app.uiRoot.popup.editState.cursor == 3 and app.uiRoot.popup.editState.anchor == 3)
        preview("prefab-name-prefix")
        app.uiRoot.popup.text = "ChildPrefab"; app.uiRoot.popup:submit()
        check("derived prefab created", require("project.Prefab").decode(project:readAsset("Assets/ChildPrefab.prefab")).definitionReference == prefabId)
        local x, y = app.sceneView:worldToScreen(100, 200)
        assert(app:placePrefab("Assets/NewPrefab.prefab", x, y))
        local object = assert(app.sceneView.selectedLObject)
        app:updateInspectorTarget()
        local inspector = app.inspector.classInspector
        check("component hierarchy tree", #inspector.tree.nodes == 3 and inspector.tree.nodes[3].depth == 2)
        preview("object-properties")
        inspector:selectComponent("root")
        local groups = {}; for _, row in ipairs(inspector.rows) do if row.header then groups[row.label] = true end end
        check("selected component groups", groups.Transform and groups.Movement)
        preview("component-properties")
        assert(app:inspectAsset("Assets/NewPrefab.prefab")); app.activePanel = "assets"; app:updateInspectorTarget()
        inspector:selectComponent("root")
        check("prefab root Transform hidden", not inspector.class.properties["root.x"] and not inspector.class.properties["root.scaleX"])
        preview("prefab-root-properties")
        inspector:selectComponent("sprite")
        check("prefab child Transform editable", inspector.class.properties["sprite.rotation"] and inspector.class.properties["sprite.scaleX"])
        preview("prefab-child-properties")
        app.activePanel = "scene"; app.inspectorSource = "scene"; app:updateInspectorTarget()
        inspector:selectComponent(nil)
        assert(inspector:setProperty("speed", 42))
        local function pickResource(reference, name)
            local browser = app.assetBrowser
            inspector:ensurePropertyVisible(name); assert(app:beginObjectPick(name))
            assert(browser:openFolder(reference:match("^(.*)/[^/]+$")))
            browser.viewMode = "list"; app:updateSceneViewport()
            local index
            for i, entry in ipairs(browser.entries) do if entry.reference == reference then index = i end end
            local rect = browser:entryBounds(assert(index))
            app:mousepressed(rect.x + 40, rect.y + 10, 1); app:mousereleased(rect.x + 40, rect.y + 10, 1)
            assert(not app.objectPick, inspector.error)
        end
        pickResource("Assets/Sprite.png", "sprite.image")
        pickResource("Assets/ChildPrefab.prefab", "projectile")
        check("resource eyedropper", object.propertyOverrides.projectile == project:getAssetId("Assets/ChildPrefab.prefab"))
        local target = app.level:addLObject(-100, 40, prefabId)
        app:recordHistory()
        assert(app:beginObjectPick("target"))
        local targetX, targetY = app.sceneView:worldToScreen(-100, 40)
        app:mousepressed(targetX, targetY, 1)
        check("viewport reference eyedropper", object.propertyOverrides.target == target.authoringId and app.sceneView.selectedLObject == object)
        inspector:ensurePropertyVisible("sprite.image")
        app:draw()
        preview("resource-properties")
        check("external image loaded", app.spriteAssets:image(project:getAssetId("Assets/Sprite.png")) ~= nil)
        assert(app:saveAllDocuments())
        check("save all review before writing", app.uiRoot.popup.options.title == "Save All"
            and #app.uiRoot.popup.options.choices == 1 and app.uiRoot.popup.options.choices[1].checked and app.document:isDirty())
        preview("save-all-review")
        local saveDialog = app.uiRoot.popup
        app:mousepressed(saveDialog.choicesRect.x + 12, saveDialog.choicesRect.y + 10, 1)
        saveDialog:submit()
        check("unchecked level remains unsaved", app.document:isDirty() and not app.uiRoot.popup)
        assert(app:saveCurrentDocument(levelPath))
        local reopened = assert(Project.open(project.rootPath))
        local ProjectStart = require("editor.ProjectStart")
        local openedProject
        local launcher = ProjectStart.new(function(opened)
            openedProject = opened
            return true
        end)
        launcher:draw()
        assert(require("editor.Startup").openRequestedProject({"--project", project.rootPath}, launcher, love.filesystem.getWorkingDirectory()))
        check("project startup argument", openedProject and openedProject.rootPath == reopened.rootPath)
        local document = assert(require("editor.LevelDocument").load(levelPath))
        local savedObject = assert(document.level.lobjects[1])
        check("instance placement saved", savedObject.transform.x == 100 and savedObject.transform.y == 200)
        check("property edit saved", savedObject.propertyOverrides.speed == 42)
        app = App.new(document, reopened)
        assert(app:startPlay())
        check("project class beginPlay", app.runtimeWorld.lobjects[1].begun)
        local world = app.runtimeWorld
        local spawned = assert(world:spawnLObject(world.lobjects[1].properties.projectile, {x = 150, y = 50}))
        check("runtime prefab spawn", #world.lobjects == 3 and spawned.begun and spawned.authoringId == nil)
        local classSpawned = assert(world:spawnLObject(classId))
        check("runtime Lua Class spawn", classSpawned.begun and classSpawned.definitionReference == classId)
        app.gameView:draw()
        assert(app:stopPlay())
        local root, child = app.level.lobjects[1], app.level.lobjects[2]
        assert(app.level:reparent({child}, root))
        check("object parenting", child.parentAuthoringId == root.authoringId and #app.level:treeRows() == 2)
        root.transform.rotation = 25
        root.transform.scaleX, root.transform.scaleY = 1.2, 1.2
        app.sceneView:setSelection({root, child})
        app.activePanel, app.inspectorSource = "hierarchy", "scene"
        app:updateInspectorTarget(); app:draw()
        preview("object-hierarchy-multiselect")
        result.projectDirectory = project.rootPath
        result.theme = require("editor.Theme").name
        local canvas = love.graphics.newCanvas(love.graphics.getDimensions())
        love.graphics.push("all")
        love.graphics.setCanvas(canvas); app:draw(); love.graphics.setCanvas()
        local screenshot = canvas:newImageData()
        local png = screenshot:encode("png")
        assert(Fs.writeAtomic(Fs.join(directory, "preview.png"), png:getString()))
        png:release(); screenshot:release(); canvas:release()
        love.graphics.pop()
        result.ok = true
    end, debug.traceback)
    if not ok then result.error = err end
    if not ownsDirectory then
        print(result.error); love.event.quit(1); return
    end
    local written, writeError = Fs.writeAtomic(Fs.join(directory, "report.json"), assert(Json.encode(result, true)) .. "\n")
    if not written then print(writeError) end
    love.event.quit(ok and written and 0 or 1)
end

return Verification
