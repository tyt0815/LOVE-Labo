local Theme = require("editor.Theme")
local LevelDocument = require("editor.LevelDocument")
local SceneView = require("editor.SceneView")
local GameView = require("editor.GameView")
local Hierarchy = require("editor.Hierarchy")
local Inspector = require("editor.Inspector")

local EditorApp = {}
EditorApp.__index = EditorApp

function EditorApp.new(document, project, preferences)
    local self = setmetatable({}, EditorApp)
    self.histories = setmetatable({}, {__mode = "k"})
    self.assetActions, self.assetActionIndex, self.historyClock = {}, 0, 0

    self.sceneView = SceneView.new()
    if preferences then
        self.sceneView.snapSettings = require("editor.SnapSettings").copy(preferences.snapSettings)
        self.sceneView.onSnapChanged = preferences.saveSnapSettings
    end
    self.gameView = GameView.new()
    self.hierarchy = Hierarchy.new()
    self.inspector = Inspector.new()
    -- 이전 필드의 확정과 다음 필드의 편집 시작 사이에 Undo 경계를 둔다.
    self.inspector.onCommitEdit = function() self:recordHistory() end

    self.project = project
    if project then
        self.prefabDocuments = {}
        project.draftAssets = self.prefabDocuments
        self.spriteAssets = require("editor.SpriteAssets").new(project)
        self.sceneView.spriteAssets, self.gameView.spriteAssets = self.spriteAssets, self.spriteAssets
    end
    self.statusHeight = project and 26 or 0
    self.assetBrowser = project and require("editor.AssetBrowser").new(project) or nil
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
    if self.assetBrowser then
        self.assetBrowser.assetOperations = require("editor.AssetOperations").new(self, self.assetBrowser)
    end

    return self
end

function EditorApp:setDocument(document)
    if not document or not document.level then
        return false
    end
    self:cancelObjectPick()
    local reference = self.project and self.project:referenceForPath(document.path)
    self.documentAssetId = reference and self.project:getAssetId(reference) or nil

    -- Runtime World는 현재 document의 Level snapshot에서 만들어진다.
    -- document가 바뀌면 이전 Runtime은 폐기한다.
    self.runtimeWorld = nil

    self.document = document
    self.inspectedAssetReference = nil
    self.inspectorSource = "scene"
    self.sceneView.ping = nil
    self.instanceInspectorObject, self.instanceInspectorTarget = nil, nil
    if self.spriteAssets then self.spriteAssets:clear() end
    self.level = document.level
    if self.project then self.level.beforeReparent = function(roots, parent)
        return require("project.PrefabHierarchy").prepareReparent(self.project, self.level, roots, parent)
    end end
    if self.project then self.level.duplicateData = function(object)
        return require("project.PrefabHierarchy").duplicateData(self.project, self.level, object)
    end end
    if not self.histories[document] then
        self.histories[document] = require("editor.History").new(assert(require("editor.LevelFile").encode(self.level)))
    end
    self.documentReference = nil

    self.sceneView.level = self.level
    if self.spriteAssets then self.spriteAssets.level = self.level end
    self.hierarchy.level = self.level
    self.inspector.level = self.level

    self.sceneView:setSelection({})
    self.sceneView:cancelDrag(false)
    self.sceneView.isPanning = false
    self.inspector:cancelEdit()
    self.levelInspectorTarget = {data = self.level, level = self.level, kind = "level", referenceField = "scriptReference", label = "Level",
        getDisplayName = function()
            local path = self.documentAssetId and self.project:getAssetReference(self.documentAssetId) or self.document.path
            return path and path:gsub("\\", "/"):match("([^/]+)%.level$") or "Untitled Level"
        end,
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
    self:cancelObjectPick()
    if self:isPlaying() then
        return false, "editor is already playing"
    end

    -- Inspector의 transient edit을 authoring Level에 먼저 확정한 뒤
    -- 그 시점의 Level snapshot으로 Runtime World를 만든다.
    self.inspector:commitEdit()
    if self.viewportControls then self.viewportControls:commit() end

    local called, world, worldError = pcall(require("runtime.WorldLoader").create, self.project, self.level:toData())
    if not called then worldError, world = tostring(world), nil end
    if not world then self.runtimeError = worldError; return false, worldError end
    self.runtimeError, self.runtimeWorld = nil, world

    -- Play 중 hidden Scene View drag/pan 상태가 남아 있지 않게 정리한다.
    self.sceneView:cancelDrag(false)
    self.sceneView.isPanning = false
    if self.uiRoot.focused == self.viewportControls then self.uiRoot.focused = self.sceneWidget end

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

function EditorApp:prepareInspectedAsset(reference)
    if not reference or not reference:match("^Assets/.+%.prefab$") then return true end
    local id = self.project:getAssetId(reference)
    self.inspector:commitEdit(); self:recordHistory()
    self.prefabDocuments = self.prefabDocuments or {}
    local document, err = self.prefabDocuments[id]
    if not document then document, err = require("editor.PrefabDocument").load(self.project, reference) end
    if not document then return false, err end
    local editor = require("editor.PrefabEditor").new(self.project, document, function()
        self.project.draftRevision = (self.project.draftRevision or 0) + 1
        self.instanceInspectorObject = nil
    end, function(path)
        local target, err = self.prefabEditor:target(path)
        if not target then self.inspector.classInspector.error = err; return false, err end
        self.prefabInspectorTarget = target
        self:updateInspectorTarget()
    end)
    local target, targetError = editor:target("root")
    if not target then return false, targetError end
    self.prefabDocuments[id] = document
    self.project.draftAssets = self.prefabDocuments
    self.prefabDocument, self.prefabEditor, self.prefabInspectorTarget = document, editor, target
    self.inspectedAssetReference, self.inspectorSource = id, "assets"
    self.histories[document] = self.histories[document] or require("editor.History").new(assert(require("editor.Prefab").encodeData(document.data)))
    self.prefabEditor.onContext = function(path, x, y) self:showPrefabObjectMenu(path, x, y) end
    return true
end

function EditorApp:placePrefab(reference, x, y, hierarchyDrop)
    if self:isPlaying() then return false, "Stop Play before placing a Prefab" end
    if not hierarchyDrop and not self.sceneView:containsPoint(x, y) then return false, "Drop inside the Scene View" end
    if self.viewportControls:containsPoint(x, y) then return false, "Drop outside the viewport controls" end
    local source, sourceError = self.project:getAssetReference(reference)
    if not source then return false, sourceError end
    local sourcePath, sourceError = require("project.LObjectTemplate").source(self.project, reference)
    if not sourcePath then return false, sourceError end
    local Definition = require("editor.ObjectDefinition")
    local definition, err = Definition.resolve(self.project, reference)
    if not definition then return false, err end
    local target, targetError = Definition.inspectorTarget(self.project, {}, definition, self.level, "LObject")
    if not target then return false, targetError end
    self.inspector:commitEdit()
    local wx, wy = self.sceneView:screenToWorld(x, y)
    local parent
    if type(hierarchyDrop) == "table" then parent = hierarchyDrop.parent
    elseif hierarchyDrop then parent = self.hierarchy:getLObjectAtPosition(x, y) end
    if hierarchyDrop then wx, wy = 0, 0 end
    local object = assert(self.level:addLObject(wx, wy, self.project:getAssetId(reference) or reference, source:match("([^/]+)%.[^.]+$")))
    if parent then
        object.parentAuthoringId = parent.authoringId
        self.hierarchy.collapsed[parent.authoringId] = nil
    end
    local expanded, expandError = require("project.PrefabHierarchy").expandAuthoring(self.project, self.level, object)
    if not expanded then self.level:removeLObject(object); return false, expandError end
    self.sceneView:setSelection({object}); self.activePanel = hierarchyDrop and "hierarchy" or "scene"; self.inspectorSource = "scene"
    self.assetBrowser.selectedReference = nil
    self:updateInspectorTarget()
    return true
end

function EditorApp:placePrefabs(entries, x, y, hierarchyDrop)
    local startId, previous = self.level.nextAuthoringId, self.sceneView:getSelection()
    local previousSource, previousPanel = self.inspectorSource, self.activePanel
    local collapsed = {}; for id, value in pairs(self.hierarchy.collapsed) do collapsed[id] = value end
    local target = hierarchyDrop and {parent = self.hierarchy:getLObjectAtPosition(x, y)} or nil
    local added = {}
    for _, entry in ipairs(entries) do
        local called, ok, err = pcall(self.placePrefab, self, entry.reference, x, y, target)
        if not called then err, ok = tostring(ok), false end
        if not ok then
            for _, object in ipairs(self.level.lobjects) do
                if object.authoringId >= startId then added[#added + 1] = object end
            end
            self.level:removeLObjects(added)
            self.hierarchy.collapsed = collapsed
            self.inspectorSource, self.activePanel = previousSource, previousPanel
            self.sceneView:setSelection(previous); self:updateInspectorTarget()
            return false, err
        end
    end
    for _, object in ipairs(self.level.lobjects) do if object.authoringId >= startId then added[#added + 1] = object end end
    self.sceneView:setSelection(added); self:updateInspectorTarget()
    return true
end

function EditorApp:updateInspectorTarget()
    if not self.inspector.classInspector then return self.sceneView.selectedLObject end
    local revision = self.project.draftRevision or 0
    if self.prefabSyncLevel ~= self.level or self.prefabSyncRevision ~= revision then
        local roots = {}
        for _, object in ipairs(self.level.lobjects) do
            if not object.prefabRootId or object.prefabRootId == object.authoringId then roots[#roots + 1] = object end
        end
        for _, object in ipairs(roots) do
            local ok, err = require("project.PrefabHierarchy").expandAuthoring(self.project, self.level, object)
            if not ok then self.runtimeError = err end
        end
        self.prefabSyncLevel, self.prefabSyncRevision = self.level, revision
    end
    local selected = self.inspectedAssetReference and self.project:getAssetReference(self.inspectedAssetReference)
    self.inspectorSource = self.inspectorSource or "scene"
    local assetSelected = self.inspectorSource == "assets" and selected
    local prefab = assetSelected and self.prefabDocument
        and selected and self.project:getAssetId(selected) == self.prefabDocument.assetId
    local currentLevelAsset = assetSelected and self.documentAssetId
        and self.project:getAssetId(selected) == self.documentAssetId
    local object = not assetSelected and self.sceneView.selectedLObject or nil
    self.inspector.assetSummary = nil
    if assetSelected and not prefab and not currentLevelAsset then
        local name = selected:match("([^/]+)$")
        local extension = name:match("%.([^%.]+)$")
        local _, info = self.project:checkedEntry(selected)
        local kind = type(info) == "table" and info.type == "directory" and "Folder" or "File"
        if kind ~= "Folder" and extension then
            name = name:sub(1, -#extension - 2)
            local kinds = {level = "Level", prefab = "Prefab", lua = "Lua Class"}
            kind = kinds[extension] or extension:upper() .. " File"
            if extension == "lua" then
                local meta = self.project.assetMetadata and self.project.assetMetadata[selected]
                local classes = {level = "Level Class", lobject = "LObject Class", component = "Component Class"}
                kind = meta and classes[meta.scriptKind] or kind
            end
        end
        self.inspector.assetSummary = {name = name, kind = kind, reference = selected}
    end
    local target
    if object then
        if self.instanceInspectorObject ~= object then
            self.inspector:commitEdit()
            self.instanceInspectorObject = object
            local Definition = require("editor.ObjectDefinition")
            local definition, err = require("project.PrefabHierarchy").authoringDefinition(self.project, self.level, object)
            local targetError
            self.instanceInspectorTarget = nil
            if definition then self.instanceInspectorTarget, targetError = Definition.inspectorTarget(self.project, object, definition, self.level, "LObject " .. object.authoringId) end
            self.runtimeError = err or targetError
        end
        target = self.instanceInspectorTarget
    elseif not self.inspector.assetSummary then
        self.instanceInspectorObject = nil
        target = prefab and self.prefabInspectorTarget or self.levelInspectorTarget
    end
    self.levelInspectorTarget.level = self.level
    self.inspector.classInspector:setTarget(target)
    self.inspector.classInspector:layout(love.graphics.getWidth() - self.inspector.width,
        self.inspector.width, love.graphics.getHeight() - self.statusHeight, object and self.inspector:getPropertyTop(), self.inspector.y)
    return object
end

function EditorApp:saveInspectedDocument()
    self.inspector:commitEdit()
    if self.prefabDocument and self.inspector.classInspector and self.inspector.classInspector.target == self.prefabInspectorTarget then
        local saved, err = self.prefabDocument:save(self.project)
        if not saved then self.inspector.classInspector.error = err end
        if saved and self.spriteAssets then self.spriteAssets:clear(); self.instanceInspectorObject = nil end
        return saved, err
    end
    local saved, err = self:saveCurrentDocument()
    if not saved then self.runtimeError = err end
    return saved, err
end

function EditorApp:saveAllDocuments()
    if self:isPlaying() then return false, "Stop Play before saving" end
    self.inspector:commitEdit(); self:recordHistory()
    local targets, choices = {}, {}
    for id, document in pairs(self.prefabDocuments or {}) do
        if document:isDirty() then
            targets[#targets + 1] = {document = document, reference = self.project:getAssetReference(id) or id}
        end
    end
    table.sort(targets, function(a, b) return a.reference < b.reference end)
    for _, target in ipairs(targets) do choices[#choices + 1] = {label = "Prefab  " .. target.reference, value = target} end
    local saveLevel = self.document:isDirty() or not self.document.path
    if saveLevel then
        local reference = self.documentAssetId and self.project and self.project:getAssetReference(self.documentAssetId)
        choices[#choices + 1] = {label = "Level  " .. (reference or self.document.path
            or "Untitled (choose a path after confirmation)"), value = {level = true}}
    end
    require("editor.ui.Dialog").new(self.uiRoot, {title = "Save All", choices = choices, listOnly = true, checkboxes = true,
        message = "Choose the documents to save.", choiceLabel = "Save targets",
        emptyLabel = "All documents are already saved.", confirmLabel = "Save All",
        onConfirm = function(_, _, checked)
            local selectedLevel = false
            for _, target in ipairs(checked) do
                if target.level then selectedLevel = true
                elseif target.document:isDirty() then
                    local saved, err = target.document:save(self.project)
                    if not saved then return false, err end
                end
            end
            if selectedLevel then return self:saveCurrentDocument() end
            return true
        end})
    return true
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
        self.document.savedSnapshot = assert(require("editor.LevelFile").encode(self.level))
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
    self.document.savedSnapshot = assert(require("editor.LevelFile").encode(self.level))
    self.documentAssetId = self.project:getAssetId(reference)
    self.documentReference = self.documentAssetId
    if self.assetBrowser then self.assetBrowser:refresh(true) end
    return true
end

function EditorApp:showSaveLevelDialog()
    local folder = self.assetBrowser and self.assetBrowser.folder or "Assets"
    if folder ~= "Assets" and folder:sub(1, 7) ~= "Assets/" then folder = "Assets" end
    require("editor.ui.Dialog").new(self.uiRoot, {title = "Save Level", input = true,
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
    local Widget = require("editor.ui.Widget")
    local Canvas = require("editor.ui.Canvas")
    local Root = require("editor.ui.Root")
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
        hint = function() return self:isPlaying() and "Game View. F5: stop Play." or "Scene View. Drag gizmo: move. Ctrl+D: duplicate. F: frame. Middle drag: pan. Wheel: zoom." end,
        bounds = function(_, x, y, width, height)
            self.sceneView:setViewport(x, y, width, height)
            self.gameView:setViewport(x, y, width, height)
        end,
        draw = function()
            if self:isPlaying() then self.gameView:draw(self.runtimeWorld)
            else self.sceneView:draw() end
            if self.runtimeError then
                require("editor.Ui").text(self.runtimeError, self.sceneView.viewportX + 16, 94,
                    self.sceneView.viewportWidth - 32, Theme.color("error"))
            end
        end,
        mousepressed = function(_, x, y, button)
            if self:isPlaying() then return true end
            if button == 1 or button == 2 then self.inspectorSource = "scene" end
            self.sceneView:mousepressed(x, y, button)
            return true, self.sceneView.isPanning or self.sceneView.isDraggingLObject or self.sceneView.marquee ~= nil or self.sceneView.pointerDrag ~= nil
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
        keypressed = function(_, key) return self:handleSceneKey(key) end,
        cancel = function() self.sceneView:cancelDrag(true); self.sceneView.isPanning = false end,
    })
    self.sceneWidget = sceneWidget
    self.viewportControls = require("editor.ui.ViewportControls").new(self.sceneView)
    local snapSlot = center:addChild(self.viewportControls, {z = 1})
    center.handlers.bounds = function(_, _, _, width, height)
        snapSlot.width = math.max(0, math.min(self.viewportControls:preferredWidth(), width - 12))
        snapSlot.x, snapSlot.y = math.max(6, width - snapSlot.width - 12), 6
        snapSlot.height = math.min(self.viewportControls:preferredHeight(snapSlot.width), math.max(0, height - 12))
    end
    local hierarchy = panel("hierarchy", {
        hint = function(_, x, y)
            local object = self.hierarchy:getLObjectAtPosition(x, y)
            return object and "Select LObject " .. object.authoringId .. ". Delete: remove. Ctrl+D: duplicate."
                or "Hierarchy: objects in the current level. Click an empty row to inspect the level."
        end,
        bounds = function(_, _, y, _, height) self.hierarchy.height, self.hierarchy.y = height, y end,
        draw = function() self.hierarchy:draw(self.sceneView.selectedLObject) end,
        mousepressed = function(_, x, y, button)
            if not self:isPlaying() then
                if button == 1 or button == 2 then self.inspectorSource = "scene" end
                return self.hierarchy:mousepressed(x, y, button)
            end
            return true
        end,
        mousemoved = function(_, x, y) return self.hierarchy:mousemoved(x, y) end,
        mousereleased = function(_, x, y, button) return self.hierarchy:mousereleased(x, y, button) end,
        wheelmoved = function(_, _, _, amount) self.hierarchy:wheelmoved(amount); return true end,
        cancel = function() self.hierarchy.drag = nil; self.hierarchy.scrollbar:dispatch("cancel") end,
        keypressed = function(_, key) return self:handleSceneKey(key) end
    })
    self.hierarchy.sceneView = self.sceneView
    self.sceneView.onContextMenu = function(x, y, object) self:showObjectMenu(x, y, object) end
    self.hierarchy.onContextMenu = self.sceneView.onContextMenu

    local inspector, inspectorWidget = panel("inspector", {
        bounds = function(_, x, y, width, height)
            self.inspector.height, self.inspector.y = height, y
            local inspector = self.inspector.classInspector
            if inspector and inspector.target then
                inspector:layout(x, width, y + height, inspector.target.instance and self.inspector:getPropertyTop(), y)
            end
        end,
        hint = function() return "Inspector: edit the selected object, level or Prefab." end,
        draw = function() self.inspector:draw(self:updateInspectorTarget()) end,
        mousepressed = function(_, x, y, button)
            if not self:isPlaying() then
                return self.inspector:mousepressed(x, y, button, love.graphics.getWidth(), self:updateInspectorTarget())
            end
            return true
        end,
        keypressed = function(_, key) return self.inspector:keypressed(key) end,
        mousemoved = function(_, x, y, dx) return self.inspector:mousemoved(x, y, dx) end,
        mousereleased = function() return self.inspector:mousereleased() end,
        cancel = function() return self.inspector:cancelPointer() end,
        textinput = function(_, text) return self.inspector:textinput(text) end,
        textedited = function(_, text) return self.inspector:textedited(text) end,
        wheelmoved = function(_, x, y, amount)
            if not self:isPlaying() and self.inspector.classInspector and self.inspector.classInspector.target then
                self.inspector.classInspector:wheelmoved(amount, x, y)
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
    self.menuBar = require("editor.ui.MenuBar").new(self)
    slots.menu = self.canvas:addChild(self.menuBar, {z = 102})
    if self.statusHeight > 0 then
        self.statusWidget = Widget.new({mousepressed = function() return true end, wheelmoved = function() return true end})
        self.statusWidget.focusable = false
        slots.status = self.canvas:addChild(self.statusWidget, {z = 101})
    end
    if self.assetBrowser then
        self.inspector.classInspector = require("editor.ClassInspector").new(self.project, self.uiRoot)
        self.inspector.classInspector.onCommitEdit = self.inspector.onCommitEdit
        self.inspector.classInspector.onSave = function() return self:saveInspectedDocument() end
        self.inspector.classInspector.onScopeChanged = function()
            self.inspector:commitEdit()
            self:updateInspectorTarget()
        end
        self.inspector.classInspector.onPick = function(name) return self:beginObjectPick(name) end
        self.inspector.classInspector.onTargetReloaded = function(target)
            self.prefabInspectorTarget = target; self:updateInspectorTarget()
        end
        self.inspector.classInspector.isPicking = function(name) return self.objectPick and self.objectPick.name == name end
        self.inspector.classInspector.onFrame = function(value)
            local inspector = self.inspector.classInspector
            if inspector.target and inspector.target.prefabScope then
                local object = inspector.target.level.lobjects[value]
                if not object then return false, "Referenced Prefab object is missing" end
                return inspector.objectTree:reveal(object.path)
            end
            for _, object in ipairs(self.level.lobjects) do
                if object.authoringId == value then self.sceneView:frameLObject(object); self.sceneView.ping = {object = object, remaining = 1.5}; return true end
            end
            return false, "Referenced instance was not found"
        end
        self.inspector.classInspector.onReveal = function(value)
            self.assetBrowser.collapsed = false
            self:updateSceneViewport()
            return self.assetBrowser:reveal(value)
        end
        self:updateInspectorTarget()
        self.assetBrowser.onSelect = function(reference) return self:selectAsset(reference) end
        self.assetBrowser.externalDropTarget = function(entry, x, y)
            if self.inspectorWidget:containsPoint(x, y) then return false, nil, "Use the eyedropper to assign resources" end
            if self.hierarchy:containsPoint(x, y) then
                if self:isPlaying() then return false, nil, "Stop Play before placing a Prefab" end
                if entry.type ~= "file" or not require("project.LObjectTemplate").source(self.project, entry.reference) then return false, nil, "Drop an LObject Lua Class or Prefab into the Hierarchy" end
                return "hierarchy", {x = 0, y = self.hierarchy.y or 0, w = self.hierarchy.width, h = self.hierarchy.height}
            end
            if not self.sceneView:containsPoint(x, y) then return end
            if self:isPlaying() then return false, nil, "Stop Play before placing a Prefab" end
            if self.viewportControls:containsPoint(x, y) then return false, nil, "Drop outside the viewport controls" end
            if entry.type ~= "file" or not require("project.LObjectTemplate").source(self.project, entry.reference) then return false, nil, "Drop an LObject Lua Class or Prefab into the Scene View" end
            local vx, vy, width, height = self.sceneView:getViewport()
            return "scene", {x = vx, y = vy, w = width, h = height}
        end
        self.assetBrowser.onExternalDrop = function(entry, x, y, destination)
            return self:placePrefab(entry.reference, x, y, destination == "hierarchy")
        end
        self.assetBrowser.onExternalDropMany = function(entries, x, y, destination)
            return self:placePrefabs(entries, x, y, destination == "hierarchy")
        end
        self.assetBrowser.onRefresh = function()
            self.inspector:commitEdit()
            self.prefabSyncRevision = nil
            for id, document in pairs(self.prefabDocuments) do
                if not document:isDirty() then
                    local fresh = require("editor.PrefabDocument").load(self.project, id)
                    if fresh and fresh.savedSnapshot ~= document.savedSnapshot then
                        document.data, document.savedSnapshot = fresh.data, fresh.savedSnapshot
                        self.histories[document] = require("editor.History").new(fresh.savedSnapshot)
                        if document == self.prefabDocument then self.prefabInspectorTarget = assert(self.prefabEditor:target()) end
                    end
                end
            end
            self:updateInspectorTarget()
            self.inspector.classInspector:reload()
            self.instanceInspectorObject = nil
            self.spriteAssets:clear()
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
            for _, prefab in pairs(self.prefabDocuments or {}) do
                local prefabPath = self.project:resolvePath(prefab.assetId)
                if prefabPath then prefabPath = prefabPath:gsub("\\", "/") end
                if prefabPath and require("ffi").os == "Windows" then prefabPath = prefabPath:lower() end
                if path and prefabPath and prefab:isDirty()
                    and (prefabPath == path or prefabPath:sub(1, #path + 1) == path .. "/") then
                    return false, "Save the edited prefab before removing it"
                end
            end
            return true
        end
        self.assetBrowser.onMove = function(source, destination)
            local refs = self.moveReferences
            if refs then
                self.level.scriptReference = refs.script
                for i, object in ipairs(self.level.lobjects) do object.definitionReference = refs.objects[i] end
                if refs.clean and self.documentAssetId then
                    self.document.savedSnapshot = assert(require("editor.LevelFile").encode(self.level))
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
        if target == self.viewportControls and self.sceneView.isDraggingLObject then
            self.sceneView:cancelDrag(true)
            self.uiRoot.captured, self.uiRoot.captureButton = nil, nil
        end
        if target ~= self.viewportControls then self.viewportControls:commit() end
        local ancestor = target
        while ancestor and not ancestor.panelName do ancestor = ancestor.parent end
        local name = ancestor and ancestor.panelName
        if target == self.menuBar then return end
        if name then self.activePanel = name end
        if not self:isPlaying() and name ~= "inspector" then self.inspector:commitEdit() end
        if name ~= "scene" then
            self.sceneView:cancelDrag(false)
            self.sceneView.isPanning = false
        end
    end
    self.uiLayout = require("editor.ui.EditorLayout").new(self, self.canvas, slots)
    self:updateSceneViewport()
end

function EditorApp:updateSceneViewport()
    self.viewportControls.visible = not self:isPlaying()
    self.uiLayout:arrange(love.graphics.getDimensions())
end

function EditorApp:update(dt)
    local objectTree = self.inspector.classInspector and self.inspector.classInspector.objectTree
    if objectTree and objectTree.ping then objectTree.ping.remaining = objectTree.ping.remaining - dt; if objectTree.ping.remaining <= 0 then objectTree.ping = nil end end
    if self.sceneView.ping then self.sceneView.ping.remaining = self.sceneView.ping.remaining - dt; if self.sceneView.ping.remaining <= 0 then self.sceneView.ping = nil end end
    self.uiRoot:update(dt)
    if self.runtimeWorld then
        local ok, updated, err = pcall(self.runtimeWorld.update, self.runtimeWorld, dt)
        if not ok then err, updated = tostring(updated), false end
        if updated == false then self.runtimeError = err; self.runtimeWorld = nil end
        if self.runtimeWorld then
            local candidate, transitionError = self.runtimeWorld:takeLevelTransition()
            if candidate then self.runtimeWorld, self.runtimeError = candidate, nil
            elseif transitionError then self.runtimeError = transitionError end
        end
        return updated, err
    end
end

function EditorApp:draw()
    self:updateSceneViewport()
    local Ui = require("editor.Ui")
    local x, y = love.mouse.getPosition()
    Ui.beginFrame(x, y)
    Theme.clear("background")
    self.uiRoot:draw()
    self:drawStatusBar(x, y)
end

function EditorApp:statusText(x, y)
    if self.objectPick then return "Pick " .. self.objectPick.kind .. " reference in Assets, Hierarchy or Scene. Esc / right click: cancel." end
    local Ui = require("editor.Ui")
    if self.assetBrowser and self.assetBrowser.drag and self.assetBrowser.drag.active then
        local drag = self.assetBrowser.drag
        return drag.error or (drag.destination == "scene" and "Place Prefab in Scene. Esc: cancel."
            or drag.destination == "inspector" and "Set Inspector resource. Esc: cancel."
            or "Move to " .. (drag.destination or "") .. ". Esc: cancel.")
    end
    local hint = Ui.hoverHint or self.uiRoot:getHint(x, y)
    local err = self.runtimeError or self.assetBrowser and self.assetBrowser.error
        or self.inspector.classInspector and self.inspector.classInspector.error
        or self.spriteAssets and self.spriteAssets.error
        or self.viewportControls.error
    if err then return "Error: " .. err .. (hint and " | " .. hint or "") end
    if hint then return hint end
    return self.assetBrowser and self.assetBrowser.selectedReference
        or "Double-click a folder or level to open it."
end

function EditorApp:drawStatusBar(x, y)
    if self.statusHeight == 0 then return end
    local width, height = love.graphics.getDimensions()
    love.graphics.push("all")
    love.graphics.setScissor(0, height - self.statusHeight, width, self.statusHeight)
    Theme.setColor("background")
    love.graphics.rectangle("fill", 0, height - self.statusHeight, width, self.statusHeight)
    self.statusHint = self:statusText(x, y)
    require("editor.Ui").text(self.statusHint, 12, height - self.statusHeight + 6, width - 24, Theme.color("text"))
    love.graphics.pop()
end

function EditorApp:cancelObjectPick()
    if not self.objectPick then return end
    if self.objectPick.scrollbar then self.objectPick.scrollbar:dispatch("cancel") end
    love.mouse.setCursor(self.objectPick.cursor)
    self.objectPick = nil
end

function EditorApp:beginObjectPick(name, parentPath)
    local inspector = self.inspector.classInspector
    if self:isPlaying() or not inspector or not inspector.target then return false, "Stop Play before picking a reference" end
    local declaration = name ~= "$parent" and inspector.class.properties[name]
    local kind = name == "$child" and "child" or declaration and declaration.type or name == "$parent" and "parent"
    if kind == "child" and (not self.prefabEditor or inspector.target ~= self.prefabInspectorTarget) then return false, "Open a Prefab before adding children" end
    if kind ~= "child" and kind ~= "parent" and kind ~= "object" and kind ~= "image" and not require("core.PropertySchema").isTemplate(kind) then return false, "This field cannot be picked" end
    if kind == "object" and inspector.target.level ~= self.level and not inspector.target.prefabScope then return false, "Pick an instance reference on a level or placed instance" end
    if self.objectPick then self:cancelObjectPick(); return true end
    self.inspector:commitEdit(); self.uiRoot:cancelCapture(); self.uiRoot:dismissPopup()
    self.objectPick = {target = inspector.target, component = inspector.selectedComponent, name = name, kind = kind, cursor = love.mouse.getCursor()}
    if kind == "child" then self.objectPick.parentPath = parentPath or self.prefabEditor.selected end
    self.pickCursor = self.pickCursor or love.mouse.getSystemCursor("crosshair")
    love.mouse.setCursor(self.pickCursor)
    return true
end
function EditorApp:selectAsset(reference)
    local ok, err = self:prepareInspectedAsset(reference)
    if ok then
        self.inspectedAssetReference = reference and (self.project:getAssetId(reference) or reference)
        self.inspectorSource = "assets"
        self:updateInspectorTarget()
    end
    return ok, err
end
function EditorApp:inspectAsset(reference) return self:selectAsset(reference) end
function EditorApp:pickReferenceAt(x, y)
    local reference, object
    self.assetBrowser:clampScroll(); self.hierarchy:layoutScrollbar()
    local bars = {self.assetBrowser.treeScrollbar, self.assetBrowser.fileScrollbar, self.hierarchy.scrollbar}
    local inspector = self.inspector.classInspector
    local tree = inspector.objectTree
    if inspector:treeContains(tree, x, y) then bars[#bars + 1] = tree.scrollbar end
    bars[#bars + 1] = inspector.scrollbar
    for _, bar in ipairs(bars) do
        if bar:dispatch("mousepressed", x, y, 1) then self.objectPick.scrollbar = bar; return end
    end
    if self.objectPick.kind == "object" and self.inspector.classInspector.target.prefabScope and inspector:treeContains(tree, x, y) then
        local node = tree:nodeAt(x, y)
        object = node and self.inspector.classInspector.target.scopeByPath[node.key]
    elseif self.assetBrowser:containsPoint(x, y) then
        local entry = self.assetBrowser:getEntryAtPosition(x, y)
        if entry and entry.type == "directory" and not entry.isLink then self.assetBrowser:openFolder(entry.reference); return end
        if entry and entry.type == "file" and not entry.isLink then reference = entry.reference end
        local tree = self.assetBrowser.treeSlot.widget
        if tree:containsPoint(x, y) then
            local index = math.floor((y - tree.y) / 26) + 1 + self.assetBrowser.treeScroll
            local node = self.assetBrowser.tree[index]
            if node then
                if x < tree.x + require("editor.Ui").METRICS.contentPaddingX + 18 + node.depth * 14 then
                    self.assetBrowser.expanded[node.reference] = not self.assetBrowser.expanded[node.reference]; self.assetBrowser:rebuildTree()
                else self.assetBrowser:openFolder(node.reference) end
                return
            end
        end
    elseif self.hierarchy:containsPoint(x, y) then object = self.hierarchy:getLObjectAtPosition(x, y)
    elseif self.sceneView:containsPoint(x, y) and not self.viewportControls:containsPoint(x, y) then
        object = self.sceneView:findLObjectAtWorldPosition(self.sceneView:screenToWorld(x, y))
    end
    if not reference and not object then return end
    local pick, inspector = self.objectPick, self.inspector.classInspector
    if inspector.target ~= pick.target or inspector.selectedComponent ~= pick.component then self:cancelObjectPick(); return end
    if pick.kind == "child" then
        local previous = assert(require("editor.Prefab").encodeData(self.prefabDocument.data))
        self:recordHistory()
        local called, ok, err, path = pcall(function()
            if object then return self.prefabEditor:addInstance(self.level, object, pick.parentPath) end
            return self.prefabEditor:add(reference, pick.parentPath)
        end)
        if not called or not ok then
            self.prefabDocument.data = assert(require("editor.Prefab").decode(previous))
            inspector.error = tostring(called and err or ok)
            return
        end
        self:cancelObjectPick()
        self.prefabInspectorTarget = assert(self.prefabEditor:target(path))
        self:updateInspectorTarget(); self:recordHistory()
        return
    end
    local value, err = inspector:pickCandidate(pick.name, reference, object)
    if value == nil then inspector.error = err; return end
    local ok = inspector:applyPicked(pick.name, value)
    if ok then self:cancelObjectPick(); self:updateInspectorTarget() end
end
function EditorApp:mousepressed(x, y, button, presses)
    self:updateSceneViewport()
    if self.objectPick then
        if button == 2 then self:cancelObjectPick(); return true end
        if button == 1 then
            if self.inspectorWidget:containsPoint(x, y) and not (self.objectPick.kind == "object"
                and self.inspector.classInspector.target.prefabScope and self.inspector.classInspector:treeContains(self.inspector.classInspector.objectTree, x, y))
                and not (self.inspector.classInspector.scrollbar.visible and require("editor.Ui").contains(x, y, self.inspector.classInspector.scrollbar.rect)) then self:cancelObjectPick()
            else self:pickReferenceAt(x, y); return true end
        else return true end
    end
    self.uiRoot:mousepressed(x, y, button, presses)
    self:updateSceneViewport()
end

function EditorApp:mousereleased(x, y, button)
    if self.objectPick and self.objectPick.scrollbar then
        self.objectPick.scrollbar:dispatch("mousereleased", x, y, button); self.objectPick.scrollbar = nil
        return true
    end
    self.uiRoot:mousereleased(x, y, button)
end

function EditorApp:mousemoved(x, y, dx, dy)
    self:updateSceneViewport()
    if self.objectPick then
        if self.objectPick.scrollbar then self.objectPick.scrollbar:dispatch("mousemoved", x, y) end
        love.mouse.setCursor(self.pickCursor); return
    end
    self.uiLayout:updateCursor(x, y)
    if self.inspector.classInspector and self.inspector.classInspector:resizeAt(x, y) then
        self.treeResizeCursor = self.treeResizeCursor or love.mouse.getSystemCursor("sizens")
        love.mouse.setCursor(self.treeResizeCursor)
    end
    self.uiRoot:mousemoved(x, y, dx, dy)
end

function EditorApp:focus(focused)
    if focused then return end
    self:cancelObjectPick()
    if self.assetBrowser then self.assetBrowser:cancelDrag() end
    self.inspector:cancelPointer()
    if self.viewportControls.numberDrag then self.viewportControls:dispatch("cancel") end
    self.uiRoot:cancelCapture()
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

function EditorApp:textedited(text, start, length)
    if self.uiRoot.popup then return self.uiRoot:textedited(text, start, length) end
    if self:isPlaying() then return end
    if self.inspector:isEditing() then self.uiRoot.focused = self.inspectorWidget end
    return self.uiRoot:textedited(text, start, length)
end

function EditorApp:handleSceneKey(key)
    if self:isPlaying() then return true end
    local controlDown = love.keyboard.isDown("lctrl", "rctrl")
    local x, y = love.mouse.getPosition()
    local usesMousePosition = key == "d" and controlDown
    if usesMousePosition and self.activePanel == "hierarchy" then self.sceneView:duplicateSelection(); return true end
    if usesMousePosition and not self.sceneView:containsPoint(x, y) then return true end
    if usesMousePosition and self.viewportControls:containsPoint(x, y) then return true end
    self.sceneView:keypressed(key, controlDown, x, y)
    if key == "escape" then self.uiRoot:cancelCapture(); self.hierarchy.drag = nil end
    if not self.sceneView.isDraggingLObject and not self.sceneView.isPanning and self.uiRoot.captured == self.sceneWidget then self.uiRoot.captured, self.uiRoot.captureButton = nil, nil end
    return true
end

function EditorApp:keypressed(key)
    if self.objectPick then
        if key == "escape" then self:cancelObjectPick() end
        return true
    end
    -- 팝업과 편집 포커스가 입력을 우선 소비한다. 저장·Play는 에디터 전역 명령이다.
    if self.uiRoot.popup then return self.uiRoot:keypressed(key) end
    local controlDown = love.keyboard.isDown("lctrl", "rctrl")
    local shiftDown = love.keyboard.isDown("lshift", "rshift")
    if key == "z" and controlDown and not self:isPlaying() then return self:undoRedo(shiftDown and 1 or -1) end
    if key == "e" and controlDown and shiftDown and not self:isPlaying() then return self:showExportDialog() end
    if key == "s" and controlDown then
        if shiftDown then return self:saveAllDocuments() end
        return self:saveInspectedDocument()
    end
    if key == "f5" then
        if self:isPlaying() then return self:stopPlay() end
        return self:startPlay()
    end
    if self:isPlaying() then return end
    if self.inspector:isEditing() then self.uiRoot.focused = self.inspectorWidget end
    if not controlDown and not self.inspector:isEditing() and not self.viewportControls.editing
        and (key == "w" or key == "e" or key == "r") then return self:handleSceneKey(key) end
    return self.uiRoot:keypressed(key)
end

function EditorApp:showObjectMenu(x, y, object)
    if object and not self.sceneView:isSelected(object) then self.sceneView:setSelection({object}) end
    local enabled = #self.sceneView:getSelection() > 0
    local function edit(callback)
        self.inspector:commitEdit(); self:recordHistory(); callback(); self:recordHistory(); self:updateInspectorTarget()
    end
    require("editor.ui.ContextMenu").new(self.uiRoot):show(x, y, {
        {label = "Duplicate", shortcut = "Ctrl+D", enabled = enabled, action = function() edit(function() self.sceneView:duplicateSelection() end) end},
        {label = "Create Prefab...", enabled = object ~= nil, action = function() self:showCreatePrefabDialog(object) end},
        {label = "Delete", shortcut = "Delete", enabled = enabled, action = function() edit(function() self.sceneView:deleteSelection() end) end},
        {label = "Frame Selection", shortcut = "F", enabled = enabled, action = function() self.sceneView:frameSelected() end},
        {label = "Detach from Parent", enabled = enabled, action = function() edit(function()
            local ok, err = self.level:reparent(self.sceneView:getSelection(), nil); self.hierarchy.error = not ok and err or nil
        end) end},
        {label = "Select All", shortcut = "Ctrl+A", action = function() self.sceneView:setSelection(self.level.lobjects) end}
    })
end

function EditorApp:showCreatePrefabDialog(object)
    if self:isPlaying() then return false, "Stop Play before creating a Prefab" end
    self.inspector:commitEdit(); self:recordHistory()
    local captured, err = require("project.PrefabHierarchy").capture(self.project, self.level, object)
    if not captured then self.hierarchy.error = err; return false, err end
    local folder = self.assetBrowser.folder
    if not folder:match("^Assets") then folder = "Assets" end
    local tree = require("editor.ui.FolderTree").new(self.project, "Assets", nil, folder)
    require("editor.ui.Dialog").new(self.uiRoot, {title = "Create Prefab", input = true,
        message = "Save this object and its descendants. The level instances stay unchanged.",
        value = "PF_" .. (object.name or "Object"):gsub("[^%w_]", "_"), content = tree,
        onConfirm = function(name)
            local ok, reference = self.assetBrowser.assetOperations:create(tree.selected or folder, "prefab", name, {prefabData = captured})
            if ok then self.assetBrowser:reveal(reference) end
            return ok, reference
        end})
    return true
end

function EditorApp:showPrefabObjectMenu(path, x, y)
    require("editor.ui.ContextMenu").new(self.uiRoot):show(x, y, {
        {label = "Add Child", children = {
            {label = "Pick Source...", action = function() self:beginObjectPick("$child", path) end}
        }}
    })
end
function EditorApp:recordHistory()
    if self.performingAssets or self.replayingAssets then return end
    if self:isPlaying() or self.inspector:isEditing() or self.sceneView.isDraggingLObject then return end
    local selected = self.sceneView.selectedLObject
    local history = self.histories[self.document]
    history.highWater = math.max(history.highWater or 1, self.level.nextAuthoringId)
    local changed = history:record(assert(require("editor.LevelFile").encode(self.level)), selected and selected.authoringId)
    if changed then self:stampHistory(history) end
    local prefab = self.prefabDocument
    if prefab then
        local prefabHistory = self.histories[prefab]
        if prefabHistory:record(assert(require("editor.Prefab").encodeData(prefab.data))) then self:stampHistory(prefabHistory) end
    end
end

function EditorApp:discardRedo()
    for i = #self.assetActions, self.assetActionIndex + 1, -1 do self.assetActions[i] = nil end
    for _, history in pairs(self.histories) do
        for i = #history.entries, history.index + 1, -1 do history.entries[i] = nil end
    end
end

function EditorApp:stampHistory(history)
    self:discardRedo()
    self.historyClock = self.historyClock + 1
    history.entries[history.index].stamp = self.historyClock
end

function EditorApp:pushAssetAction(command)
    self:discardRedo()
    self.historyClock = self.historyClock + 1
    command.stamp = self.historyClock
    self.assetActions[#self.assetActions + 1] = command
    if #self.assetActions > 100 then table.remove(self.assetActions, 1) end
    self.assetActionIndex = #self.assetActions
end

function EditorApp:undoRedo(direction)
    self:cancelObjectPick()
    if self:isPlaying() then return false end
    self.inspector:mousereleased()
    self.inspector:commitEdit()
    -- 캡처를 지우기 전에 스냅 드래그의 마우스 상태와 편집 값을 확정한다.
    self.viewportControls:release()
    self.viewportControls:commit()
    self.sceneView:cancelDrag(false)
    -- 나머지 캡처 소유자도 취소를 받아 내부 드래그 상태를 정리한다.
    self.uiRoot:cancelCapture()
    self:recordHistory()
    local prefab = self.prefabDocument and self.inspector.classInspector
        and self.inspector.classInspector.target == self.prefabInspectorTarget
    local document = prefab and self.prefabDocument or self.document
    local history = self.histories[document]
    local action = self.assetActions[self.assetActionIndex + (direction == 1 and 1 or 0)]
    local nextState = history and history.entries[history.index + direction]
    local stamp = nextState and (direction == -1 and history.entries[history.index].stamp or nextState.stamp)
    if action and (not stamp or (direction == -1 and action.stamp > stamp)
        or (direction == 1 and action.stamp < stamp)) then
        self.replayingAssets = true
        local called, ok, err = pcall(direction == -1 and action.undo or action.redo)
        self.replayingAssets = nil
        if not called or not ok then
            self.assetBrowser.error = tostring(called and err or ok)
            return false
        end
        self.assetActionIndex = self.assetActionIndex + direction
        self.assetBrowser.error = nil
        return true
    end
    local state = history and history:step(direction)
    if not state then return false end
    if prefab then
        document.data = assert(require("editor.Prefab").decode(state.text))
        self.project.draftRevision = (self.project.draftRevision or 0) + 1
        self.prefabInspectorTarget = assert(self.prefabEditor:target())
        self:updateInspectorTarget()
    else
        document.level = assert(require("editor.LevelFile").decode(state.text))
        document.level.nextAuthoringId = math.max(document.level.nextAuthoringId, history.highWater or 1)
        self:setDocument(document)
        for _, object in ipairs(self.level.lobjects) do
            if object.authoringId == state.selection then self.sceneView.selectedLObject = object end
        end
        self.activePanel, self.inspectorSource = "scene", "scene"
        self:updateInspectorTarget()
    end
    if self.spriteAssets then self.spriteAssets:clear() end
    return true
end

-- 하나의 드래그·필드 편집을 완료한 시점에만 문서 스냅샷을 기록한다.
for _, name in ipairs({"mousepressed", "mousereleased", "keypressed", "focus"}) do
    local handler = EditorApp[name]
    EditorApp[name] = function(self, ...)
        local result, extra = handler(self, ...)
        self:recordHistory()
        return result, extra
    end
end

function EditorApp:showExportDialog()
    if not self.project then return false, "Export requires a project" end
    self.inspector:commitEdit()
    require("editor.ui.Dialog").new(self.uiRoot, {title = "Export Game", input = true,
        message = "Export the current level as a standalone .love game.",
        value = require("editor.HostFileSystem").join(self.project.rootPath, "Build/Game.love"), confirmLabel = "Export",
        onConfirm = function(output)
            local called, ok, err = pcall(require("editor.Export").write, self.project, self.level, output)
            if not called then return false, tostring(ok) end
            return ok, err
        end})
    return true
end

return EditorApp
