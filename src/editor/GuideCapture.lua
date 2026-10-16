local Capture = {}
function Capture.run(args)
    local Fs, Json = require("editor.HostFileSystem"), require("project.Json")
    local directory, theme
    for index, value in ipairs(args) do
        if value == "--capture-guide" then directory = args[index + 1]
        elseif value == "--theme" then theme = args[index + 1] end
    end
    local ok, err = xpcall(function()
        assert(directory and directory:sub(1, 2) ~= "--", "--capture-guide requires a new output directory")
        if theme then
            assert(require("editor.Theme").load(function(path)
                if path == "editor/settings.json" then return assert(Json.encode({version = 1, theme = theme})) end
                return love.filesystem.read(path)
            end))
        end
        assert(not Fs.info(directory), "Capture directory must not exist")
        assert(Fs.mkdir(directory))
        assert(love.window.setMode(1440, 900, {resizable = false}))
        assert(require("editor.WindowFrame").install())
        local project = assert(require("editor.Project").create(directory, "GuideExample"))
        for _, name in ipairs({"LaboEssentials"}) do
            assert(require("editor.PluginOperations").apply(project, name, true, true))
        end
        assert(project:createEntry("Assets", "level", "L_Start"))
        local app = require("editor.EditorApp").new(nil, project)
        assert(app:openProjectDocument("Assets/L_Start.level", true))
        local camera = app.level:addLObject(0, 0, nil, "Camera")
        camera.scripts = {{id = "guideCamera", name = "Camera", source = "Camera"}, {id = "guideView", name = "View", source = "View"}}
        camera.scriptOverrides = {guideView = {cameraSource = {authoringId = camera.authoringId, script = "guideCamera"}}}
        app.sceneView.zoom = 0.5
        local report = {width = 1440, height = 900, images = {}}
        local function shot(name, hover)
            local canvas = love.graphics.newCanvas(1440, 900)
            love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.origin(); love.graphics.setScissor()
            love.graphics.clear(0.1, 0.1, 0.1, 1)
            local mousePosition = love.mouse.getPosition
            love.mouse.getPosition = function() return hover and hover.x or -1, hover and hover.y or -1 end
            local drawn, drawError = pcall(app.draw, app)
            if app.menuBar then
                assert(app.menuBar.x == 0 and app.menuBar.y == 0, "Menu bar must stay at the window top")
            end
            love.mouse.getPosition = mousePosition
            assert(drawn, drawError); love.graphics.setCanvas(); love.graphics.pop()
            local pixels = canvas:newImageData(); local png = pixels:encode("png")
            assert(Fs.writeAtomic(Fs.join(directory, name .. ".png"), png:getString()))
            png:release(); pixels:release(); canvas:release()
            report.images[#report.images + 1] = name
        end
        local function expandPropertyGroups()
            local inspector = app.inspector.classInspector
            for _, row in ipairs(inspector.rows) do
                if row.header and not row.scriptId and not row.builtIn then inspector.groupExpanded[row.groupKey] = true end
            end
            inspector:rebuildRows()
        end
        local browser = require("editor.ProjectStart").new(function() return true end, nil,
            {entries = {{path = project.rootPath, name = project.name}}, saveRecent = function() end})
        browser:selectEntry(2)
        local editorApp = app
        app = browser; shot("project-browser"); app = editorApp
        browser:selectEntry(1)
        app = browser; shot("project-browser-create"); app = editorApp
        assert(app:inspectAsset("Assets/L_Start.level")); app:draw(); shot("level-details")
        assert(project:createEntry("Assets", "lua", "Session", {scriptKind = "script"}))
        assert(Fs.writeAtomic(project:resolveSourceFile("Assets/Session.lua"), [[local Session = {properties = {
    score = {type = "number", default = 0, group = "Game"},
    title = {type = "string", default = "Project state"}
}}
return Session
]]))
        assert(project:rebuildAssetIndex()); app.assetBrowser:refresh()
        app:showProjectInspector()
        assert(app.inspector.classInspector.target:addScript(project:getAssetId("Assets/Session.lua"), "session"))
        app.inspector.classInspector:reload(); expandPropertyGroups(); shot("project-details")
        local scriptId = app.inspector.classInspector.preview:getScriptByName("session").id
        local toggle = assert(app.inspector.classInspector:ensurePropertyVisible(scriptId .. ".enabled"))
        shot("script-enabled")
        app.inspector.classInspector:mousepressed(toggle.x + toggle.w / 2, toggle.y + toggle.h / 2, 1)
        shot("script-disabled")
        app.inspector.classInspector:mousepressed(toggle.x + toggle.w / 2, toggle.y + toggle.h / 2, 1)
        app.menuBar:openAt(100, 14); shot("project-inspector-menu"); app.uiRoot:keypressed("escape")
        assert(app.inspector.classInspector.target:removeScript("session")); app.inspector.classInspector:reload()
        app.sceneView:setSelection({app.level.lobjects[1]}); app.inspectorSource = "scene"; app:updateInspectorTarget()
        app.inspector.classInspector:selectScript(app.level.lobjects[1].scripts[1].id)
        app.inspector.classInspector.groupExpanded["object/Transform"] = false
        app.inspector.classInspector:rebuildRows(); expandPropertyGroups(); shot("camera-details")
        app.inspector.classInspector:ensurePropertyVisible(app.level.lobjects[1].scripts[2].id .. ".cameraSource"); shot("view-details")
        app.inspector.classInspector.scroll = 0
        assert(project:createEntry("Assets", "lua", "Player", {scriptKind = "script"}))
        assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/Player.lua")), [[-- labo-script: script
local Player = {extends = "0619e599-48f0-49c5-92b5-aa4a81476f8c", properties = {speed = {type = "number", default = 100, group = "Movement"}}}
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
        app.inspector.classInspector:selectScript("sprite")
        app.inspector.classInspector.groupExpanded["object/Transform"] = false
        app.inspector.classInspector:rebuildRows(); shot("sprite-groups-collapsed")
        expandPropertyGroups(); shot("sprite-details")
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
        local placed = app.inspector.classInspector
        assert(placed:setProperty(placed.preview.scriptOrder[1] .. ".image", project:getAssetId("Assets/Player.png")))
        shot("script-placement")
        app:draw()
        for _, row in ipairs(placed.rows) do
            if row.header and row.scriptId then
                local y = placed.propertyTop + row.offset - placed.scroll
                if y >= placed.propertyTop and y + row.height <= placed.propertyTop + placed.propertyHeight then
                    placed:mousepressed(placed.left + 60, y + 12, 2)
                    shot("script-context"); app.uiRoot:keypressed("escape"); break
                end
            end
        end
        assert(app.assetBrowser.assetOperations:import(assert(project:resolveAssetFile("Assets/Player.png")), "Assets/UI"))
        app.assetBrowser:openFolder("Assets/UI"); shot("asset-import")
        for index, entry in ipairs(app.assetBrowser.entries) do
            if entry.type == "file" then
                local rect = app.assetBrowser:entryBounds(index)
                app.assetBrowser:showContextMenu(rect.x + rect.w / 2, rect.y + rect.h / 2)
                shot("asset-copy-id"); app.uiRoot:keypressed("escape"); break
            end
        end
        local function u32(value)
            return string.char(value % 256, math.floor(value / 256) % 256, math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
        end
        local pcm = string.rep("\0", 4410)
        local wav = "RIFF" .. u32(36 + #pcm) .. "WAVEfmt " .. u32(16) .. string.char(1, 0, 1, 0)
            .. u32(22050) .. u32(44100) .. string.char(2, 0, 16, 0) .. "data" .. u32(#pcm) .. pcm
        assert(Fs.writeAtomic(assert(project:resolvePath("Assets/UI/Tone.wav")), wav))
        assert(project:createEntry("Assets", "lua", "AudioDemo", {scriptKind = "script"}))
        assert(Fs.writeAtomic(assert(project:resolveSourceFile("Assets/AudioDemo.lua")), [[local AudioDemo = {properties = {clip = {type = "audio", default = false}}}
return AudioDemo]]))
        assert(project:rebuildAssetIndex()); app.assetBrowser:refresh()
        assert(app:placeAsset("Assets/AudioDemo.lua", vx + vw / 2, vy + vh / 2))
        local audioInspector = app.inspector.classInspector
        local audioField = audioInspector.preview.scriptOrder[1] .. ".clip"
        assert(audioInspector:setProperty(audioField, project:getAssetId("Assets/UI/Tone.wav")))
        for _, row in ipairs(audioInspector.rows) do
            if row.name == audioField then audioInspector.scroll = math.max(0, row.offset - 150) end
        end
        shot("audio-property")
        assert(app:inspectAsset("Assets/PF_Player.prefab"))
        app:draw()
        local picker = app.previewPanel:openBackgroundPicker()
        local function inputColor(value)
            local field = picker.fields[4]
            picker:dispatch("mousepressed", field.x + 4, field.y + 4, 1)
            picker:dispatch("textinput", value); picker:dispatch("keypressed", "return")
        end
        inputColor("1C242E")
        shot("background-picker")
        app.uiRoot:dismissPopup()
        picker = app.viewportToolbar:openBackgroundPicker(app)
        inputColor("1C242E")
        local tab = picker.tabs[2]
        picker:dispatch("mousepressed", tab.x + 4, tab.y + 4, 1)
        inputColor("52677B"); shot("scene-background-picker")
        app.uiRoot:dismissPopup()
        assert(app.sceneView:setBackground({28, 36, 46})); shot("scene-background")
        assert(app.sceneView:setBackground(nil, true))
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
        app.menuBar.active = nil; app.menuBar:openAt(100, 15); shot("project-menu"); app.uiRoot:dismissPopup()
        assert(app:startPlay()); shot("play-running"); assert(app:pausePlay()); shot("play-paused"); assert(app:stopPlay())
        assert(Fs.rename(assert(project:resolveSourceFile("Assets/Player.lua")), assert(project:resolvePath("Assets/UI/Player.lua"))))
        assert(app:refreshProject()); shot("asset-repair")
        local repair = app.uiRoot.popup
        repair.plan.rows[1].expanded = true; repair:layout(); shot("asset-repair-picker")
        assert(repair:submit())
        assert(require("editor.ApiExamples").create(project))
        app.assetBrowser:refresh()
        assert(app:openProjectDocument("Assets/L_ApiExamples.level", true))
        assert(app:startPlay()); shot("api-examples"); assert(app:stopPlay())
        assert(project:createEntry("Assets", "lua", "ScopeVisual", {scriptKind = "script"}))
        assert(Fs.writeAtomic(project:resolveSourceFile("Assets/ScopeVisual.lua"), [[local Visual = {}
function Visual:drawWorld(context)
    if self.owner.scope == "level" then
        love.graphics.setColor(0.15, 0.65, 0.85, 1)
        love.graphics.circle("line", 0, 0, 150)
    end
end
function Visual:drawOverlay(context)
    if not self:getWorld():getScriptByName("levelOverlay") then return end
    local project = self.owner.scope == "project"
    local y = project and 20 or 48
    love.graphics.setColor(0.08, 0.12, 0.18, 0.95)
    love.graphics.rectangle("fill", 12, y - 3, context.viewport.width - 24, 24)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(project and "Project screen drawing: game-area pixels" or "Level draw: camera space | Level screen drawing: screen space", 20, y)
end
function Visual:draw(context)
    self:drawWorld(context)
    context:withScreen(function() self:drawOverlay(context) end)
end
return Visual
]]))
        assert(project:rebuildAssetIndex())
        local scoped = require("project.ScopedScripts")
        local source = project:getAssetId("Assets/ScopeVisual.lua")
        assert(assert(scoped.inspectorTarget(project, project, nil, "Project")):addScript(source, "overlay"))
        assert(assert(scoped.inspectorTarget(project, app.level, app.level, "Level")):addScript(source, "levelOverlay"))
        assert(app:startPlay()); shot("scope-drawing"); assert(app:stopPlay())
        local uiExamples = require("editor.UiExamples").create(project)
        app.assetBrowser:refresh()
        assert(app:openProjectDocument(uiExamples.level, true))
        app.inspectorSource = "scene"
        local anchorObject
        for _, object in ipairs(app.level.lobjects) do if object.name == "topRight" then anchorObject = object end end
        app.sceneView:setSelection({anchorObject}); app:updateInspectorTarget(); app:draw()
        local inspector = app.inspector.classInspector
        local layoutId = inspector.preview:getScriptByName("layout").id
        inspector.groupExpanded["object/Transform"] = false
        local rect = assert(inspector:ensurePropertyVisible(layoutId .. ".anchor"))
        shot("ui-anchor")
        inspector:mousepressed(rect.x + 6, rect.y + 6, 1); shot("ui-anchor-picker"); app.uiRoot:keypressed("escape")
        assert(app:startPlay()); shot("ui-hud"); assert(app:stopPlay())
        assert(app:openProjectDocument(uiExamples.publicLevel, true))
        for _, object in ipairs(app.level.lobjects) do if object.name == "topRight" then app.sceneView:setSelection({object}) end end
        app.inspectorSource = "scene"; app:updateInspectorTarget()
        assert(app:startPlay()); shot("ui-public"); assert(app:stopPlay())
        assert(Fs.writeAtomic(Fs.join(directory, "report.json"), assert(Json.encode(report, true))))
    end, debug.traceback)
    if not ok then print(err) end
    love.event.quit(ok and 0 or 1)
end
return Capture
