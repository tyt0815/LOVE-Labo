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
    self.assetBrowser = project and require("editor.asset_browser").new(project) or nil
    self.assetBrowserHeight = 220
    self.isResizingAssets = false
    self.activePanel = "scene"
    self.documentReference = nil

    -- Play 중에만 존재하는 Runtime World다.
    -- authoring Level과 별도 mutable state를 소유하며 Stop 시 폐기한다.
    self.runtimeWorld = nil

    if not document then
        if project and project.defaultLevelReference then
            local path, pathError = project:resolveAssetFile(project.defaultLevelReference)
            if not path then error(pathError) end
            local loaded, loadError = LevelDocument.load(path)
            if not loaded then error(loadError) end
            document = loaded
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

    if self.level.scriptReference then
        if not self.project then
            self.runtimeError = "Level script requires a project"
            return false, self.runtimeError
        end
        local ok, script, scriptError = pcall(require("editor.project_script").load, self.project, self.level.scriptReference)
        if not ok then self.runtimeError = tostring(script); return false, self.runtimeError end
        if not script then self.runtimeError = scriptError; return false, scriptError end
        local attached, loaded, loadError = pcall(world.setLevelScript, world, script)
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

function EditorApp:saveCurrentDocument(path)
    self.inspector:commitEdit()

    local saved, err =
        self.document:save(path)

    if saved and path ~= nil then
        self.documentReference = nil
    end

    return saved, err
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
        bounds = function(_, x, y, width, height)
            self.sceneView:setViewport(x, y, width, height)
            self.gameView:setViewport(x, y, width, height)
        end,
        draw = function()
            if self:isPlaying() then self.gameView:draw(self.runtimeWorld)
            else self.sceneView:draw() end
            if self.runtimeError then
                require("editor.ui").text(self.runtimeError, self.sceneView.viewportX + 16, 94,
                    self.sceneView.viewportWidth - 32, { 1, 0.5, 0.45, 1 })
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
        draw = function() self.inspector:draw(self.sceneView.selectedLObject) end,
        mousepressed = function(_, x, y, button)
            if not self:isPlaying() then
                self.inspector:mousepressed(x, y, button, love.graphics.getWidth(), self.sceneView.selectedLObject)
            end
            return true
        end,
        keypressed = function(_, key) return self.inspector:keypressed(key) end,
        textinput = function(_, text) return self.inspector:textinput(text) end
    })
    self.inspectorWidget = inspectorWidget
    local slots = {
        center = self.canvas:addChild(center),
        hierarchy = self.canvas:addChild(hierarchy),
        inspector = self.canvas:addChild(inspector)
    }
    if self.assetBrowser then
        self.assetBrowser:setUIRoot(self.uiRoot)
        self.assetBrowser.onOpenFile = function(reference)
            if reference:match("^Assets/.+%.level$") then return self:openProjectDocument(reference) end
            return true
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
    love.graphics.clear(0.08, 0.09, 0.11, 1)
    self.uiRoot:draw()
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
    if key == "s" and controlDown and not shiftDown then return self:saveCurrentDocument() end
    if key == "f5" then
        if self:isPlaying() then return self:stopPlay() end
        return self:startPlay()
    end
    if self:isPlaying() then return end
    if self.inspector:isEditing() then self.uiRoot.focused = self.inspectorWidget end
    return self.uiRoot:keypressed(key)
end

return EditorApp
