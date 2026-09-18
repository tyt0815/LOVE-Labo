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
    self.documentReference = nil

    -- Play 중에만 존재하는 Runtime World다.
    -- authoring Level과 별도 mutable state를 소유하며 Stop 시 폐기한다.
    self.runtimeWorld = nil

    if not document then
        local newDocument, err =
            LevelDocument.new()

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
        return false, worldError
    end

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

function EditorApp:updateSceneViewport()
    local windowWidth,
        windowHeight =
        love.graphics.getDimensions()

    local viewportX =
        self.hierarchy.width

    local viewportWidth =
        windowWidth
        - self.hierarchy.width
        - self.inspector.width

    local width =
        math.max(0, viewportWidth)

    -- Scene View와 Game View는 같은 중앙 editor 영역을 번갈아 사용한다.
    self.sceneView:setViewport(
        viewportX,
        0,
        width,
        windowHeight
    )

    self.gameView:setViewport(
        viewportX,
        0,
        width,
        windowHeight
    )
end

function EditorApp:update(dt)
end

function EditorApp:draw()
    self:updateSceneViewport()

    love.graphics.clear(
        0.08,
        0.09,
        0.11,
        1.0
    )

    if self:isPlaying() then
        self.gameView:draw(
            self.runtimeWorld
        )
    else
        self.sceneView:draw()
    end

    self.hierarchy:draw(
        self.sceneView.selectedLObject
    )

    self.inspector:draw(
        self.sceneView.selectedLObject
    )
end

function EditorApp:mousepressed(
    x,
    y,
    button
)
    self:updateSceneViewport()

    -- 아직 Runtime input forwarding이 없으므로 Play 중에는
    -- Editor authoring mouse input을 전부 막는다.
    if self:isPlaying() then
        return
    end

    local windowWidth =
        love.graphics.getWidth()

    if self.inspector:containsPoint(
        x,
        y,
        windowWidth
    ) then
        self.sceneView.isDraggingLObject =
            false

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
                self.hierarchy:getLObjectAtPosition(
                    x,
                    y
                )

            self.sceneView.isDraggingLObject =
                false
        end

        return
    end

    if self.sceneView:containsPoint(x, y) then
        self.sceneView:mousepressed(
            x,
            y,
            button
        )
    end
end

function EditorApp:mousereleased(
    x,
    y,
    button
)
    if self:isPlaying() then
        return
    end

    self.sceneView:mousereleased(
        x,
        y,
        button
    )
end

function EditorApp:mousemoved(
    x,
    y,
    dx,
    dy
)
    if self:isPlaying() then
        return
    end

    self.sceneView:mousemoved(
        x,
        y,
        dx,
        dy
    )
end

function EditorApp:wheelmoved(x, y)
    if self:isPlaying() then
        return
    end

    self:updateSceneViewport()

    local mouseX, mouseY =
        love.mouse.getPosition()

    if not self.sceneView:containsPoint(
        mouseX,
        mouseY
    ) then
        return
    end

    self.sceneView:wheelmoved(x, y)
end

function EditorApp:textinput(text)
    if self:isPlaying() then
        return
    end

    self.inspector:textinput(text)
end

function EditorApp:keypressed(key)
    local controlDown =
        love.keyboard.isDown(
            "lctrl",
            "rctrl"
        )

    local shiftDown =
        love.keyboard.isDown(
            "lshift",
            "rshift"
        )

    -- Save는 Play 여부와 무관한 Editor 전역 명령으로 유지한다.
    if key == "s"
        and controlDown
        and not shiftDown
    then
        return self:saveCurrentDocument()
    end

    -- 현재는 별도 toolbar가 없으므로 F5를 최소 Play/Stop 입력으로 사용한다.
    if key == "f5" then
        if self:isPlaying() then
            return self:stopPlay()
        end

        return self:startPlay()
    end

    -- Runtime input forwarding을 만들기 전까지
    -- Play 중 다른 key가 authoring shortcut으로 들어가지 않게 막는다.
    if self:isPlaying() then
        return
    end

    if self.inspector:keypressed(key) then
        return
    end

    self:updateSceneViewport()

    local mouseX, mouseY =
        love.mouse.getPosition()

    local usesMouseWorldPosition =
        (key == "a" and not controlDown)
        or (key == "d" and controlDown)

    if usesMouseWorldPosition
        and not self.sceneView:containsPoint(
            mouseX,
            mouseY
        )
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
