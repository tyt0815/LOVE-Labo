local LevelDocument = require("editor.level_document")
local SceneView = require("editor.scene_view")
local Hierarchy = require("editor.hierarchy")
local Inspector = require("editor.inspector")

local EditorApp = {}
EditorApp.__index = EditorApp

function EditorApp.new(document, project)
    local self = setmetatable({}, EditorApp)

    self.sceneView = SceneView.new()
    self.hierarchy = Hierarchy.new()
    self.inspector = Inspector.new()

    -- Project는 Editor host가 소유한다.
    -- LevelDocument는 실제 파일 path/dirty/save만 알고
    -- project-relative reference의 해석은 EditorApp + Project가 담당한다.
    self.project = project
    self.documentReference = nil

    if not document then
        local newDocument, err = LevelDocument.new()

        if not newDocument then
            error(err)
        end

        document = newDocument
    end

    self:setDocument(document)

    return self
end

function EditorApp:setDocument(document)
    if not document or not document.level then
        return false
    end

    self.document = document
    self.level = document.level

    -- absolute path로 직접 교체된 document는 어느 Project reference에서
    -- 왔는지 알 수 없으므로 project-relative identity를 초기화한다.
    self.documentReference = nil

    self.sceneView.level = self.level
    self.hierarchy.level = self.level
    self.inspector.level = self.level

    self.sceneView.selectedLObject = nil
    self.sceneView.isDraggingLObject = false
    self.sceneView.isPanning = false
    self.inspector:cancelEdit()

    return true
end

function EditorApp:saveCurrentDocument(path)
    self.inspector:commitEdit()

    local saved, err = self.document:save(path)

    if saved and path ~= nil then
        -- 저수준 absolute path save는 Project reference와의 대응을
        -- 보장할 수 없으므로 기존 reference를 버린다.
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

    -- serialized/editor-facing identity는 absolute path가 아니라
    -- canonical project-relative reference로 유지한다.
    self.documentReference = reference

    return true
end

function EditorApp:openDocument(path, allowDiscard)
    -- 아직 commit되지 않은 Inspector 값도 unsaved 검사에 포함한다.
    self.inspector:commitEdit()

    local dirty = self.document:isDirty()

    if dirty and not allowDiscard then
        return false, "current level has unsaved changes"
    end

    -- target이 완전히 load/validate된 뒤에만 현재 document를 교체한다.
    local document, loadError = LevelDocument.load(path)

    if not document then
        return false, loadError
    end

    self:setDocument(document)

    return true
end

function EditorApp:openProjectDocument(reference, allowDiscard)
    if not self.project then
        return false, "editor has no project"
    end

    local path, resolveError =
        self.project:resolvePath(reference)

    if not path then
        return false, resolveError
    end

    local opened, openError =
        self:openDocument(path, allowDiscard)

    if not opened then
        return false, openError
    end

    self.documentReference = reference

    return true
end

function EditorApp:updateSceneViewport()
    local windowWidth, windowHeight = love.graphics.getDimensions()

    local viewportX = self.hierarchy.width
    local viewportWidth =
        windowWidth - self.hierarchy.width - self.inspector.width

    self.sceneView:setViewport(
        viewportX,
        0,
        math.max(0, viewportWidth),
        windowHeight
    )
end

function EditorApp:update(dt)
end

function EditorApp:draw()
    self:updateSceneViewport()

    love.graphics.clear(0.08, 0.09, 0.11, 1.0)

    self.sceneView:draw()
    self.hierarchy:draw(self.sceneView.selectedLObject)
    self.inspector:draw(self.sceneView.selectedLObject)
end

function EditorApp:mousepressed(x, y, button)
    self:updateSceneViewport()

    local windowWidth = love.graphics.getWidth()

    if self.inspector:containsPoint(x, y, windowWidth) then
        self.sceneView.isDraggingLObject = false
        self.inspector:mousepressed(
            x,
            y,
            button,
            windowWidth,
            self.sceneView.selectedLObject
        )
        return
    end

    self.inspector:commitEdit()

    if self.hierarchy:containsPoint(x, y) then
        if button == 1 then
            self.sceneView.selectedLObject =
                self.hierarchy:getLObjectAtPosition(x, y)

            self.sceneView.isDraggingLObject = false
        end

        return
    end

    if self.sceneView:containsPoint(x, y) then
        self.sceneView:mousepressed(x, y, button)
    end
end

function EditorApp:mousereleased(x, y, button)
    self.sceneView:mousereleased(x, y, button)
end

function EditorApp:mousemoved(x, y, dx, dy)
    self.sceneView:mousemoved(x, y, dx, dy)
end

function EditorApp:wheelmoved(x, y)
    self:updateSceneViewport()

    local mouseX, mouseY = love.mouse.getPosition()

    if not self.sceneView:containsPoint(mouseX, mouseY) then
        return
    end

    self.sceneView:wheelmoved(x, y)
end

function EditorApp:textinput(text)
    self.inspector:textinput(text)
end

function EditorApp:keypressed(key)
    local controlDown =
        love.keyboard.isDown("lctrl", "rctrl")

    local shiftDown =
        love.keyboard.isDown("lshift", "rshift")

    if key == "s" and controlDown and not shiftDown then
        return self:saveCurrentDocument()
    end

    if self.inspector:keypressed(key) then
        return
    end

    self:updateSceneViewport()

    local mouseX, mouseY = love.mouse.getPosition()

    local usesMouseWorldPosition =
        (key == "a" and not controlDown)
        or (key == "d" and controlDown)

    if usesMouseWorldPosition
        and not self.sceneView:containsPoint(mouseX, mouseY)
    then
        return
    end

    self.sceneView:keypressed(
        key,
        controlDown,
        mouseX,
        mouseY
    )
end

return EditorApp
