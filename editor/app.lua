local Theme = require("editor.theme")
local World = require("core.world")
local LevelDocument = require("editor.level_document")
local SceneView = require("editor.scene_view")
local GameView = require("editor.game_view")
local Hierarchy = require("editor.hierarchy")
local Inspector = require("editor.inspector")

local EditorApp = {}
EditorApp.__index = EditorApp

function EditorApp.new(document, project)
    local self = setmetatable({}, EditorApp)

    self.sceneView = SceneView.new()
    self.gameView = GameView.new()
    self.hierarchy = Hierarchy.new()
    self.inspector = Inspector.new()

    self.project = project
    self.statusHeight = project and 26 or 0
    self.assetBrowser = project and require("editor.asset_browser").new(project) or nil
    self.assetBrowserHeight = 350
    self.isResizingAssets = false
    self.activePanel = "scene"
    self.documentReference = nil

    -- Play 중에만 존재하는 Runtime World다.
    -- authoring Level과 별도 mutable state를 소유하며 Stop 시 폐기한다.
    self.runtimeWorld = nil

    if not document then
        if project and project.defaultLevelReference then
            local path = project:resolveAssetFile(project.defaultLevelReference)
            -- 기본 레벨 파일이 없으면 저장 경로가 없는 빈 문서로 시작한다.
            if path then
                local loaded, loadError = LevelDocument.load(path)
                if not loaded then error(loadError) end
                document = loaded
            end
        end
    end

    if not document then
        local newDocument, err =
            LevelDocument.new()

        if not newDocument then
            error(err)
        end

        document = newDocument
    end

    self:setDocument(document)
    if project and project.defaultLevelReference and document.path == project:resolvePath(project.defaultLevelReference) then
        self.documentReference = project.defaultLevelReference
    end
    self:initializeUI()

    return self
end

function EditorApp:setDocument(document)
    if not document or not document.level then
        return false
    end
    local reference = self.project and self.project:referenceForPath(document.path)
    self.documentAssetId = reference and self.project:getAssetId(reference) or nil

    -- Runtime World는 현재 document의 Level snapshot에서 만들어진다.
    -- document가 바뀌면 이전 Runtime은 폐기한다.
    self.runtimeWorld = nil

    self.document = document
    self.level = document.level
    self.documentReference = nil

    self.sceneView.level = self.level
    self.hierarchy.level = self.level
    self.inspector.level = self.level

    self.sceneView.selectedLObject = nil
    self.sceneView.isDraggingLObject = false
    self.sceneView.isPanning = false
    self.inspector:cancelEdit()
    self.levelInspectorTarget = {data = self.level, kind = "level", referenceField = "scriptReference", label = "Level",
        getOverrides = function(target) return target.data.propertyOverrides end,
        isDirty = function() return not self.document.path or self.document:isDirty() end,
        setOverrides = function(target, values) target.data.propertyOverrides = values end}
    self.runtimeError = nil
    if self.uiRoot then
        self.uiRoot:dismissPopup()
        self.uiRoot.captured, self.uiRoot.captureButton = nil, nil
        self.uiRoot.focused = self.sceneWidget
    end

    return true
end

function EditorApp:isPlaying()
    return self.runtimeWorld ~= nil
end

function EditorApp:getActiveCenterView()
    if self:isPlaying() then
        return self.gameView
    end

    return self.sceneView
end

function EditorApp:startPlay()
    if self:isPlaying() then
        return false, "editor is already playing"
    end

    -- Inspector의 transient edit을 authoring Level에 먼저 확정한 뒤
    -- 그 시점의 Level snapshot으로 Runtime World를 만든다.
    self.inspector:commitEdit()

    local world, worldError =
        World.fromLevelData(
            self.level:toData()
        )

    if not world then
        self.runtimeError = worldError
        return false, worldError
    end

    local levelClass
    if self.level.scriptReference then
        if not self.project then
            self.runtimeError = "Level script requires a project"
            return false, self.runtimeError
        end
        local ok, script, scriptError = pcall(require("editor.project_script").load, self.project, self.level.scriptReference)
        if not ok then self.runtimeError = tostring(script); return false, self.runtimeError end
        if not script then self.runtimeError = scriptError; return false, scriptError end
        local properties, propertyError = require("editor.lua_class").values(script, self.level.propertyOverrides)
        if not properties then self.runtimeError = propertyError; return false, propertyError end
        world.properties = properties
        levelClass = script
    end

    if not levelClass then
        local properties, propertyError = require("editor.lua_class").values(nil, self.level.propertyOverrides)
        if not properties then self.runtimeError = propertyError; return false, propertyError end
        world.properties = properties
    end
    if self.project then
        local bound, bindError = self:bindRuntimeObjects(world)
        if not bound then self.runtimeError = bindError; return false, bindError end
    end
    if levelClass then
        local attached, loaded, loadError = pcall(world.setLevelScript, world, levelClass)
        if not attached then self.runtimeError = tostring(loaded); return false, self.runtimeError end
        if not loaded then self.runtimeError = loadError; return false, loadError end
    end
    self.runtimeError = nil
    self.runtimeWorld = world

    -- Play 중 hidden Scene View drag/pan 상태가 남아 있지 않게 정리한다.
    self.sceneView.isDraggingLObject = false
    self.sceneView.isPanning = false

    return true
end

function EditorApp:stopPlay()
    if not self:isPlaying() then
        return false, "editor is not playing"
    end

    -- Runtime 변경을 authoring Level에 write-back하지 않고 통째로 폐기한다.
    self.runtimeWorld = nil

    return true
end

function EditorApp:resolveDocumentReferences()
    if self.project then
        self.level.scriptReference = self.project:getAssetId(self.level.scriptReference) or self.level.scriptReference
        for _, object in ipairs(self.level.lobjects) do
            object.definitionReference = self.project:getAssetId(object.definitionReference) or object.definitionReference
        end
    end
end

function EditorApp:bindRuntimeObjects(world)
    local LuaClass = require("editor.lua_class")
    local loadClass = LuaClass.loader(self.project)
    local initialObjects = {}
    for i, object in ipairs(world.lobjects) do initialObjects[i] = object end
    -- 초기 레벨의 배치 객체만 바인딩한다. Lua가 직접 생성한 객체는 자신의 초기화 경로를 사용한다.
    for i, data in ipairs(self.level.lobjects) do
        local object = initialObjects[i]
        local reference, overrides = data.definitionReference, {}
        if reference then
            local pathReference, referenceError = self.project:getAssetReference(reference)
            if not pathReference then return false, referenceError end
            if pathReference:match("^Assets/.+%.prefab$") then
                local path, pathError = self.project:resolveAssetFile(reference)
                if not path then return false, pathError end
                local bytes, readError = require("editor.host_filesystem").read(path)
                if not bytes then return false, readError end
                local prefab, prefabError = require("editor.prefab").decode(bytes)
                if not prefab then return false, prefabError end
                reference, overrides = prefab.definitionReference, prefab.overrides.properties or {}
            end
            local class, classError
            if reference then class, classError = loadClass(reference, "lobject") end
            if reference and not class then return false, classError end
            local properties, propertyError = LuaClass.values(class, overrides)
            if not properties then return false, propertyError end
            local bound, bindError = object:setClass(class, properties, world)
            if not bound then return false, bindError end
        end
    end
    return true
end

function EditorApp:inspectAsset(reference)
    if not reference or not reference:match("^Assets/.+%.prefab$") then return true end
    local id = self.project:getAssetId(reference)
    if self.prefabDocument and self.prefabDocument.assetId == id then return true end
    self.inspector:commitEdit()
    if self.prefabDocument and self.prefabDocument:isDirty() then return false, "Save the edited Prefab first (Ctrl+S)" end
    local document, err = require("editor.prefab_document").load(self.project, reference)
    if not document then return false, err end
    self.prefabDocument = document
    self.prefabInspectorTarget = {data = document.data, kind = "lobject", referenceField = "definitionReference", label = "Prefab",
        isDirty = function() return document:isDirty() end,
        getOverrides = function(target) return target.data.overrides.properties or {} end,
        setOverrides = function(target, values) target.data.overrides.properties = next(values) and values or nil end}
    return true
end

function EditorApp:updateInspectorTarget()
    if not self.inspector.classInspector then return self.sceneView.selectedLObject end
    local selected = self.assetBrowser.selectedReference
    local prefab = (self.activePanel == "assets" or self.activePanel == "inspector") and self.prefabDocument
        and selected and self.project:getAssetId(selected) == self.prefabDocument.assetId
    local object = not prefab and self.sceneView.selectedLObject or nil
    self.inspector.classInspector:setTarget(not object and (prefab and self.prefabInspectorTarget or self.levelInspectorTarget) or nil)
    self.inspector.classInspector:layout(love.graphics.getWidth() - self.inspector.width,
        self.inspector.width, love.graphics.getHeight() - self.statusHeight)
    return object
end

function EditorApp:saveInspectedDocument()
    self.inspector:commitEdit()
    if self.prefabDocument and self.inspector.classInspector and self.inspector.classInspector.target == self.prefabInspectorTarget then
        local saved, err = self.prefabDocument:save(self.project)
        if not saved then self.inspector.classInspector.error = err end
        return saved, err
    end
    local saved, err = self:saveCurrentDocument()
    if not saved then self.runtimeError = err end
    return saved, err
end

function EditorApp:saveCurrentDocument(path)
    if not path and not self.document.path and self.project then
        self:showSaveLevelDialog()
        return true
    end
    if not path and self.project and self.documentAssetId then
        local currentPath, err = self.project:resolveAssetFile(self.documentAssetId)
        if not currentPath then return false, err end
        self.document.path = currentPath
    end
    self.inspector:commitEdit()
    self:resolveDocumentReferences()

    local saved, err =
        self.document:save(path)

    if saved and path ~= nil then
        self.documentReference = nil
    end
    if saved and self.project and self.project:referenceForPath(self.document.path) then
        local indexed, indexError = self.project:rebuildAssetIndex()
        if not indexed then return false, "Level saved; metadata import failed: " .. tostring(indexError) end
        self.documentAssetId = self.project:getAssetId(self.project:referenceForPath(self.document.path))
        self:resolveDocumentReferences()
        self.document.savedSnapshot = assert(require("editor.level_file").encode(self.level))
    end

    return saved, err
end

function EditorApp:saveNewLevel(reference)
    if not self.project then return false, "editor has no project" end
    if type(reference) ~= "string" or not reference:match("^Assets/.+%.level$") then
        return false, "Choose an Assets/*.level path"
    end
    local path, err = self.project:resolvePath(reference)
    if not path then return false, err end
    local folder, name = reference:match("^(.*)/([^/]+)$")
    self.inspector:commitEdit()
    self:resolveDocumentReferences()
    local saved, saveError = self.project:createEntry(folder, "level", name,
        {level = self.level, scriptReference = self.level.scriptReference})
    if not saved then return false, saveError end
    self.document.path = path
    self.document.savedSnapshot = assert(require("editor.level_file").encode(self.level))
    self.documentAssetId = self.project:getAssetId(reference)
    self.documentReference = self.documentAssetId
    if self.assetBrowser then self.assetBrowser:refresh(true) end
    return true
end

function EditorApp:showSaveLevelDialog()
    local folder = self.assetBrowser and self.assetBrowser.folder or "Assets"
    if folder ~= "Assets" and folder:sub(1, 7) ~= "Assets/" then folder = "Assets" end
    require("editor.ui.dialog").new(self.uiRoot, {title = "Save Level", input = true,
        message = "Path inside Assets (existing files are not replaced)",
        value = folder .. "/NewLevel.level", confirmLabel = "Save",
        onConfirm = function(reference) return self:saveNewLevel(reference) end})
end

function EditorApp:saveCurrentDocumentAs(reference)
    if not self.project then
        return false, "editor has no project"
    end

    local path, resolveError =
        self.project:resolvePath(reference)

    if not path then
        return false, resolveError
    end

    local saved, saveError =
        self:saveCurrentDocument(path)

    if not saved then
        return false, saveError
    end

    self.documentReference = reference

    return true
end

function EditorApp:createProjectDocument(
    reference,
    allowDiscard
)
    if not self.project then
        return false, "editor has no project"
    end

    local path, resolveError =
        self.project:resolvePath(reference)

    if not path then
        return false, resolveError
    end

    self.inspector:commitEdit()

    local dirty =
        self.document:isDirty()

    if dirty and not allowDiscard then
        return false,
            "current level has unsaved changes"
    end

    local document, createError =
        LevelDocument.create(path)

    if not document then
        return false, createError
    end

    self:setDocument(document)
    self.documentReference = reference

    return true
end

function EditorApp:openDocument(
    path,
    allowDiscard
)
    self.inspector:commitEdit()

    local dirty =
        self.document:isDirty()

    if dirty and not allowDiscard then
        return false,
            "current level has unsaved changes"
    end

    local document, loadError =
        LevelDocument.load(path)

    if not document then
        return false, loadError
    end

    self:setDocument(document)

    return true
end

function EditorApp:openProjectDocument(
    reference,
    allowDiscard
)
    if not self.project then
        return false, "editor has no project"
    end

    local path, resolveError =
        self.project:resolvePath(reference)

    if not path then
        return false, resolveError
    end

    local opened, openError =
        self:openDocument(
            path,
            allowDiscard
        )

    if not opened then
        return false, openError
    end

    self.documentReference = reference

    return true
end

function EditorApp:initializeUI()
    local Widget = require("editor.ui.widget")
    local Canvas = require("editor.ui.canvas")
    local Root = require("editor.ui.root")
    self.canvas = Canvas.new()
    self.uiRoot = Root.new(self.canvas)
    local function panel(name, handlers)
        local canvas = Canvas.new()
        canvas.panelName = name
        local content = Widget.new(handlers)
        canvas:addChild(content, { fill = true })
        return canvas, content
    end
    local center, sceneWidget = panel("scene", {
        hint = function() return self:isPlaying() and "Game View. F5: stop Play." or "Scene View. A: add. Ctrl+D: duplicate. F: frame. Middle drag: pan. Wheel: zoom." end,
        bounds = function(_, x, y, width, height)
            self.sceneView:setViewport(x, y, width, height)
            self.gameView:setViewport(x, y, width, height)
        end,
        draw = function()
            if self:isPlaying() then self.gameView:draw(self.runtimeWorld)
            else self.sceneView:draw() end
            if self.runtimeError then
                require("editor.ui").text(self.runtimeError, self.sceneView.viewportX + 16, 94,
                    self.sceneView.viewportWidth - 32, Theme.color("error"))
            end
        end,
        mousepressed = function(_, x, y, button)
            if self:isPlaying() then return true end
            self.sceneView:mousepressed(x, y, button)
            return true, self.sceneView.isPanning or self.sceneView.isDraggingLObject
        end,
        mousemoved = function(_, ...)
            if not self:isPlaying() then self.sceneView:mousemoved(...) end
            return true
        end,
        mousereleased = function(_, ...)
            if not self:isPlaying() then self.sceneView:mousereleased(...) end
            return true
        end,
        wheelmoved = function(_, _, _, amount)
            if not self:isPlaying() then self.sceneView:wheelmoved(0, amount) end
            return true
        end,
        keypressed = function(_, key) return self:handleSceneKey(key) end
    })
    self.sceneWidget = sceneWidget
    local hierarchy = panel("hierarchy", {
        hint = function(_, x, y)
            local object = self.hierarchy:getLObjectAtPosition(x, y)
            return object and "Select LObject " .. object.authoringId .. ". Delete: remove. Ctrl+D: duplicate."
                or "Hierarchy: objects in the current level. Click an empty row to inspect the level."
        end,
        bounds = function(_, _, _, _, height) self.hierarchy.height = height end,
        draw = function() self.hierarchy:draw(self.sceneView.selectedLObject) end,
        mousepressed = function(_, x, y, button)
            if not self:isPlaying() and button == 1 then
                self.sceneView.selectedLObject = self.hierarchy:getLObjectAtPosition(x, y)
            end
            return true
        end,
        keypressed = function(_, key) return self:handleSceneKey(key) end
    })
    local inspector, inspectorWidget = panel("inspector", {
        bounds = function(_, _, _, _, height) self.inspector.height = height end,
        hint = function() return "Inspector: edit the selected object, level or Prefab. Ctrl+S: save." end,
        draw = function() self.inspector:draw(self:updateInspectorTarget()) end,
        mousepressed = function(_, x, y, button)
            if not self:isPlaying() then
                self.inspector:mousepressed(x, y, button, love.graphics.getWidth(), self:updateInspectorTarget())
            end
            return true
        end,
        keypressed = function(_, key) return self.inspector:keypressed(key) end,
        textinput = function(_, text) return self.inspector:textinput(text) end,
        wheelmoved = function(_, _, _, amount)
            if not self:isPlaying() and self.inspector.classInspector and self.inspector.classInspector.target then
                self.inspector.classInspector:wheelmoved(amount)
            end
            return true
        end
    })
    self.inspectorWidget = inspectorWidget
    local slots = {
        center = self.canvas:addChild(center),
        hierarchy = self.canvas:addChild(hierarchy),
        inspector = self.canvas:addChild(inspector)
    }
    if self.statusHeight > 0 then
        self.statusWidget = Widget.new({mousepressed = function() return true end, wheelmoved = function() return true end})
        self.statusWidget.focusable = false
        slots.status = self.canvas:addChild(self.statusWidget, {z = 101})
    end
    if self.assetBrowser then
        self.inspector.classInspector = require("editor.class_inspector").new(self.project, self.uiRoot)
        self:updateInspectorTarget()
        self.assetBrowser.onSelect = function(reference) return self:inspectAsset(reference) end
        self.assetBrowser.onRefresh = function()
            self.inspector:commitEdit()
            self.inspector.classInspector:reload()
        end
        self.assetBrowser:setUIRoot(self.uiRoot)
        self.assetBrowser.onOpenFile = function(reference)
            if reference:match("^Assets/.+%.level$") then return self:openProjectDocument(reference) end
            return true
        end
        self.assetBrowser.canDelete = function(reference)
            local path = self.project:resolvePath(reference)
            local currentPath = self.documentAssetId and self.project:resolvePath(self.documentAssetId) or self.document.path
            local documentPath = currentPath and currentPath:gsub("\\", "/")
            if require("ffi").os == "Windows" then
                path, documentPath = path and path:lower(), documentPath and documentPath:lower()
            end
            if path and documentPath and (documentPath == path or documentPath:sub(1, #path + 1) == path .. "/") then
                return false, "This entry contains the currently open level"
            end
            return true
        end
        self.assetBrowser.onMove = function(source, destination)
            local refs = self.moveReferences
            if refs then
                self.level.scriptReference = refs.script
                for i, object in ipairs(self.level.lobjects) do object.definitionReference = refs.objects[i] end
                if refs.clean and self.documentAssetId then
                    self.document.savedSnapshot = assert(require("editor.level_file").encode(self.level))
                end
                self.moveReferences = nil
            end
            local oldPath, newPath = self.project:resolvePath(source), self.project:resolvePath(destination)
            local current = self.document.path and self.document.path:gsub("\\", "/")
            if current and oldPath and (current:lower() == oldPath:lower()
                or current:lower():sub(1, #oldPath + 1) == oldPath:lower() .. "/") then
                self.document.path = newPath .. current:sub(#oldPath + 1)
                self.documentReference = self.project:getAssetId(destination .. current:sub(#oldPath + 1))
            end
        end
        self.assetBrowser.onBeforeMove = function()
            -- 성공 후에만 메모리 참조를 바꾸어 취소·실패가 문서의 dirty 상태를 바꾸지 않게 한다.
            local refs = {clean = not self.document:isDirty(), objects = {},
                script = self.project:getAssetId(self.level.scriptReference) or self.level.scriptReference}
            for i, object in ipairs(self.level.lobjects) do
                refs.objects[i] = self.project:getAssetId(object.definitionReference) or object.definitionReference
            end
            self.moveReferences = refs
        end
        slots.assets = self.canvas:addChild(self.assetBrowser)
    end
    self.uiRoot.focused = sceneWidget
    self.uiRoot.beforeMousepressed = function(target)
        local ancestor = target
        while ancestor and not ancestor.panelName do ancestor = ancestor.parent end
        local name = ancestor and ancestor.panelName
        if name then self.activePanel = name end
        if not self:isPlaying() and name ~= "inspector" then self.inspector:commitEdit() end
        if name ~= "scene" then
            self.sceneView.isDraggingLObject, self.sceneView.isPanning = false, false
        end
    end
    self.uiLayout = require("editor.ui.editor_layout").new(self, self.canvas, slots)
    self:updateSceneViewport()
end

function EditorApp:updateSceneViewport()
    self.uiLayout:arrange(love.graphics.getDimensions())
end

function EditorApp:update(dt)
    self.uiRoot:update(dt)
    if self.runtimeWorld then
        local ok, updated, err = pcall(self.runtimeWorld.update, self.runtimeWorld, dt)
        if not ok then err, updated = tostring(updated), false end
        if updated == false then self.runtimeError = err; self.runtimeWorld = nil end
        return updated, err
    end
end

function EditorApp:draw()
    self:updateSceneViewport()
    local UI = require("editor.ui")
    local x, y = love.mouse.getPosition()
    UI.beginFrame(x, y)
    Theme.clear("background")
    self.uiRoot:draw()
    self:drawStatusBar(x, y)
end

function EditorApp:statusText(x, y)
    local UI = require("editor.ui")
    if self.assetBrowser and self.assetBrowser.drag and self.assetBrowser.drag.active then
        local drag = self.assetBrowser.drag
        return drag.error or "Move to " .. (drag.destination or "") .. ". Esc: cancel."
    end
    local hint = UI.hoverHint or self.uiRoot:getHint(x, y)
    local err = self.runtimeError or self.assetBrowser and self.assetBrowser.error
        or self.inspector.classInspector and self.inspector.classInspector.error
    if err then return "Error: " .. err .. (hint and " | " .. hint or "") end
    if hint then return hint end
    return self.assetBrowser and self.assetBrowser.selectedReference
        or "Double-click a folder or level to open it. Ctrl+S: save. F5: Play / Stop."
end

function EditorApp:drawStatusBar(x, y)
    if self.statusHeight == 0 then return end
    local width, height = love.graphics.getDimensions()
    love.graphics.push("all")
    love.graphics.setScissor(0, height - self.statusHeight, width, self.statusHeight)
    Theme.setColor("background")
    love.graphics.rectangle("fill", 0, height - self.statusHeight, width, self.statusHeight)
    self.statusHint = self:statusText(x, y)
    require("editor.ui").text(self.statusHint, 12, height - self.statusHeight + 6, width - 24, Theme.color("text"))
    love.graphics.pop()
end

function EditorApp:mousepressed(x, y, button, presses)
    self:updateSceneViewport()
    self.uiRoot:mousepressed(x, y, button, presses)
    self:updateSceneViewport()
end

function EditorApp:mousereleased(x, y, button)
    self.uiRoot:mousereleased(x, y, button)
end

function EditorApp:mousemoved(x, y, dx, dy)
    self:updateSceneViewport()
    self.uiLayout:updateCursor(x, y)
    self.uiRoot:mousemoved(x, y, dx, dy)
end

function EditorApp:wheelmoved(_, amount)
    self:updateSceneViewport()
    local x, y = love.mouse.getPosition()
    self.uiRoot:wheelmoved(x, y, amount)
end

function EditorApp:textinput(text)
    if self.uiRoot.popup then return self.uiRoot:textinput(text) end
    if self:isPlaying() then return end
    if self.inspector:isEditing() then self.uiRoot.focused = self.inspectorWidget end
    return self.uiRoot:textinput(text)
end

function EditorApp:handleSceneKey(key)
    if self:isPlaying() then return true end
    local controlDown = love.keyboard.isDown("lctrl", "rctrl")
    local x, y = love.mouse.getPosition()
    local usesMousePosition = (key == "a" and not controlDown) or (key == "d" and controlDown)
    if usesMousePosition and not self.sceneView:containsPoint(x, y) then return true end
    self.sceneView:keypressed(key, controlDown, x, y)
    return true
end

function EditorApp:keypressed(key)
    -- 팝업과 편집 포커스가 입력을 우선 소비한다. 저장·Play는 에디터 전역 명령이다.
    if self.uiRoot.popup then return self.uiRoot:keypressed(key) end
    local controlDown = love.keyboard.isDown("lctrl", "rctrl")
    local shiftDown = love.keyboard.isDown("lshift", "rshift")
    if key == "s" and controlDown and not shiftDown then return self:saveInspectedDocument() end
    if key == "f5" then
        if self:isPlaying() then return self:stopPlay() end
        return self:startPlay()
    end
    if self:isPlaying() then return end
    if self.inspector:isEditing() then self.uiRoot.focused = self.inspectorWidget end
    return self.uiRoot:keypressed(key)
end

return EditorApp
