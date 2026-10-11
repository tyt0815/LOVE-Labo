local Capture = {}
function Capture.run(args)
    local Fs, Json = require("editor.HostFileSystem"), require("project.Json")
    local directory
    for index, value in ipairs(args) do if value == "--capture-guide" then directory = args[index + 1] end end
    local ok, err = xpcall(function()
        assert(directory and directory:sub(1, 2) ~= "--", "--capture-guide requires a new output directory")
        assert(not Fs.info(directory), "Capture directory must not exist")
        assert(Fs.mkdir(directory))
        assert(love.window.setMode(1440, 900, {resizable = false}))
        local project = assert(require("editor.Project").create(directory, "GuideExample"))
        assert(project:createEntry("Assets", "level", "L_Start"))
        local app = require("editor.EditorApp").new(nil, project)
        assert(app:openProjectDocument("Assets/L_Start.level", true))
        app.sceneView.zoom = 0.5
        local report = {width = 1440, height = 900, images = {}}
        local function shot(name)
            local canvas = love.graphics.newCanvas(1440, 900)
            love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear(0.1, 0.1, 0.1, 1)
            app:draw(); love.graphics.setCanvas(); love.graphics.pop()
            local pixels = canvas:newImageData(); local png = pixels:encode("png")
            assert(Fs.writeAtomic(Fs.join(directory, name .. ".png"), png:getString()))
            png:release(); pixels:release(); canvas:release()
            report.images[#report.images + 1] = name
        end
        app:draw(); shot("level-details")
        app.sceneView:setSelection({app.level.lobjects[1]}); app.inspectorSource = "scene"; app:updateInspectorTarget()
        app.inspector.classInspector:selectScript("camera"); shot("camera-details")
        assert(project:createEntry("Assets", "lua", "Player", {scriptKind = "script"}))
        assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/Player.lua")), [[-- labo-script: script
local Player = {extends = "Sprite", properties = {speed = {type = "number", default = 100, group = "Movement"}}}
return Player
]]))
        local image = love.image.newImageData(64, 64)
        image:mapPixel(function() return 0.1, 0.65, 0.95, 1 end)
        local png = image:encode("png"); assert(Fs.writeAtomic(project:resolvePath("Assets/Player.png"), png:getString()))
        png:release(); image:release(); assert(project:rebuildAssetIndex())
        assert(project:createEntry("Assets", "prefab", "PF_Player", {}))
        local prefab = assert(require("editor.PrefabDocument").load(project, "Assets/PF_Player.prefab"))
        prefab.data.name = "PlayerRoot"
        prefab.data.scripts = {{id = "sprite", source = project:getAssetId("Assets/Player.lua")}}
        prefab.data.overrides.scripts = {sprite = {image = project:getAssetId("Assets/Player.png")}}
        assert(prefab:save(project))
        local object = app.level:addLObject(150, 0, project:getAssetId("Assets/PF_Player.prefab"), "PF_Player")
        app.assetBrowser:refresh(); app.sceneView:setSelection({object}); app:updateInspectorTarget()
        app.inspector.classInspector:selectScript("sprite"); shot("sprite-details")
        assert(app.document:save())
        assert(app:inspectAsset("Assets/PF_Player.prefab")); shot("prefab-details")
        assert(app:startPlay()); shot("game-view"); app:stopPlay()
        assert(app.prefabEditor:insertChild(nil, "Child", "root"))
        app.prefabEditor.onSelect("root"); shot("prefab-hierarchy")
        local inspector = app.inspector.classInspector
        for _, row in ipairs(inspector.rows) do if row.scriptActions then inspector:showAddScript(inspector.propertyTop + row.offset - inspector.scroll); break end end
        shot("script-picker"); app.uiRoot:keypressed("escape")
        assert(app.prefabEditor.document:save(project))
        assert(project:createEntry("Assets", "prefab", "PF_Variant", {}))
        local variant = assert(require("editor.PrefabDocument").load(project, "Assets/PF_Variant.prefab"))
        variant.data.definitionReference = project:getAssetId("Assets/PF_Player.prefab")
        assert(variant:save(project)); app.assetBrowser:refresh()
        assert(require("project.PrefabHierarchy").expandAuthoring(project, app.level, object))
        local manual = app.level:addLObject(0, 0); manual.name, manual.parentAuthoringId = "Local Object", object.authoringId
        assert(app:inspectAsset("Assets/PF_Variant.prefab"))
        assert(app.prefabEditor:insertChild(nil, "Local Object", "root"))
        assert(app.prefabEditor:insertChild(project:getAssetId("Assets/PF_Player.prefab"), "Nested Prefab", "root"))
        app.inspector.classInspector.objectTreeHeight = 156
        app.prefabEditor.onSelect("root"); shot("prefab-groups")
        local added, addError, container = app.prefabEditor:insertChild(nil, "Container", "root")
        assert(added, addError); assert(app.prefabEditor:dropObject(container, "root", "before"))
        app.prefabEditor.onSelect("root"); app.inspector.classInspector.objectTreeHeight = 182
        shot("prefab-root-replacement")
        app.inspector.classInspector.objectTree.expanded["root/previousRoot"] = false
        app.inspector.classInspector.objectTree:rebuild()
        app.hierarchy.collapsed[object.authoringId] = true; shot("prefab-collapsed")
        local captureRoot = app.level:addLObject(-150, 100); captureRoot.name = "New Object"
        captureRoot.scripts, captureRoot.scriptOverrides = {{id = "sprite", source = "Sprite"}}, {sprite = {image = project:getAssetId("Assets/Player.png")}}
        local captureChild = app.level:addLObject(50, 0); captureChild.name, captureChild.parentAuthoringId = "New Child", captureRoot.authoringId
        app.inspectorSource = "scene"; app.sceneView:setSelection({captureRoot}); app:updateInspectorTarget()
        assert(app:showCreatePrefabDialog(captureRoot)); shot("create-prefab-dialog")
        app.uiRoot.popup.text = "PF_Captured"; app.uiRoot.popup:submit()
        assert(not app.uiRoot.popup, app.uiRoot.popup and app.uiRoot.popup.error)
        shot("prefab-linked")
        assert(app:inspectAsset("Assets/PF_Player.prefab"))
        app.assetBrowser:showCreateDialog("Assets", "prefab"); shot("inline-rename")
        app.uiRoot.popup:dispatch("textinput", "A_Long_Prefab_Name_For_Multiline_Editing")
        shot("multiline-rename")
        app.uiRoot:keypressed("escape")
        assert(Fs.writeAtomic(Fs.join(directory, "report.json"), assert(Json.encode(report, true))))
    end, debug.traceback)
    if not ok then print(err) end
    love.event.quit(ok and 0 or 1)
end
return Capture
