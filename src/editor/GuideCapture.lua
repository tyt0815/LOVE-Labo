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
        for _, name in ipairs({"LaboEssentials"}) do
            assert(require("editor.PluginOperations").apply(project, name, true, true))
        end
        assert(project:createEntry("Assets", "level", "L_Start"))
        local app = require("editor.EditorApp").new(nil, project)
        assert(app:openProjectDocument("Assets/L_Start.level", true))
        app.sceneView.zoom = 0.5
        local report = {width = 1440, height = 900, images = {}}
        local function shot(name, hover)
            local canvas = love.graphics.newCanvas(1440, 900)
            love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear(0.1, 0.1, 0.1, 1)
            local mousePosition = love.mouse.getPosition
            love.mouse.getPosition = function() return hover and hover.x or -1, hover and hover.y or -1 end
            local drawn, drawError = pcall(app.draw, app)
            love.mouse.getPosition = mousePosition
            assert(drawn, drawError); love.graphics.setCanvas(); love.graphics.pop()
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
        assert(project:createEntry("Assets", "folder", "UI"))
        assert(project:createEntry("Assets/UI", "folder", "themes"))
        assert(project:createEntry("Assets/UI", "folder", "widgets"))
        app.assetBrowser.expanded["Assets/UI"] = true; app.assetBrowser:refresh(); app.assetBrowser:openFolder("Assets")
        local linkedRoot = assert(app.level:findLObject(captureRoot.authoringId))
        app.inspectorSource = "scene"; app.sceneView:setSelection({linkedRoot}); app:updateInspectorTarget(); app:draw()
        local childRect = app.hierarchy:nameRect(assert(app.level:findLObject(captureChild.authoringId)))
        shot("hierarchy-hover", {x = childRect.x + 20, y = childRect.y + childRect.h / 2})
        local treeView = app.assetBrowser.treeSlot.widget
        for index, node in ipairs(app.assetBrowser.tree) do if node.reference == "Assets/UI/themes" then
            shot("tree-hover", {x = treeView.x + 90, y = treeView.y + (index - 1 - app.assetBrowser.treeScroll) * 26 + 13})
        end end
        for index, entry in ipairs(app.assetBrowser.entries) do if entry.reference == "Assets/PF_Player.prefab" then
            local rect = app.assetBrowser:entryBounds(index)
            shot("asset-hover", {x = rect.x + 40, y = rect.y + 110})
            app.assetBrowser.viewMode = "list"; app.assetBrowser:clampScroll(); app:draw()
            rect = app.assetBrowser:entryBounds(index); shot("asset-list-hover", {x = rect.x + 70, y = rect.y + 13})
            app.assetBrowser.viewMode = "grid"; app.assetBrowser:clampScroll()
        end end
        app:draw()
        local details = app.inspector.classInspector
        for _, row in ipairs(details.rows) do if row.name == "$transform.x" then
            shot("inspector-hover", {x = details.left + 45, y = details.propertyTop + row.offset - details.scroll + 16})
        end end
        app:showObjectMenu(140, 140, nil); shot("context-empty"); app.uiRoot:keypressed("escape")
        for _, name in ipairs({"OptionalUi", "SampleA", "SampleB", "SampleC"}) do assert(require("editor.PluginOperations").create(project, name)) end
        assert(require("editor.PluginOperations").create(project, "DemoPlugin", {"LaboEssentials", "OptionalUi", "Unavailable"}))
        local pluginDialog = require("editor.ui.PluginDialog").new(app)
        pluginDialog.expanded.DemoPlugin = true; shot("plugins")
        pluginDialog:toggle("LaboEssentials"); assert(pluginDialog.error); shot("plugin-errors")
        app.uiRoot:keypressed("escape")
        local vx, vy, vw, vh = app.sceneView:getViewport()
        assert(app:placeAsset("Assets/Player.lua", vx + vw / 2, vy + vh / 2))
        assert(app.inspector.classInspector:setProperty("s1.image", project:getAssetId("Assets/Player.png")))
        shot("script-placement")
        assert(app.assetBrowser.assetOperations:import(assert(project:resolveAssetFile("Assets/Player.png")), "Assets/UI"))
        app.assetBrowser:openFolder("Assets/UI"); shot("asset-import")
        assert(app:inspectAsset("Assets/PF_Player.prefab"))
        assert(app.previewPanel:setBackground({230, 230, 230})); shot("preview-live")
        assert(app:saveInspectedDocument()); app.assetBrowser:openFolder("Assets"); shot("preview-thumbnail")
        assert(app:inspectAsset("Assets/Player.png")); shot("preview-image")
        local area = app.level:addLObject(260, -100); area.name = "Hit Area"
        area.scripts = {{id = "area", source = "RectBounds"}, {id = "input", source = "Pointer"}}
        area.scriptOverrides = {area = {width = 220, height = 120}, input = {boundsSource = "area"}}
        app.inspectorSource = "scene"; app.sceneView:setSelection({area}); app:updateInspectorTarget(); shot("editor-areas")
        assert(app:startPlay()); app.statusWidget:toggle()
        app.debugSession:log("Play started")
        app.debugSession:log("Object selected", {color = {0, 120, 255}, marker = "!"})
        app.debugSession:log("Debug overlay ready")
        app.debugSession:screenLog("Ready", {key = "state", lifespan = 30})
        app.debugSession:screenLog("Camera active", {lifespan = 30})
        app.debugSession:screenLog("Running", {key = "state", lifespan = 30})
        app.debugSession:circle(0, 0, 140, {color = {0, 120, 255}, lifespan = 30})
        app.debugSession:rect(-220, -120, 440, 240, {lifespan = 30})
        app.debugSession:line(-220, -120, 220, 120, {color = {255, 80, 80}, lifespan = 30})
        shot("debugging"); assert(app:stopPlay()); app.statusWidget:toggle(); shot("log-collapsed")
        assert(Fs.writeAtomic(Fs.join(directory, "report.json"), assert(Json.encode(report, true))))
    end, debug.traceback)
    if not ok then print(err) end
    love.event.quit(ok and 0 or 1)
end
return Capture
