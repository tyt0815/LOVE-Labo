local LevelDocument = require("editor.level_document")
local SceneView = require("editor.scene_view")
local Hierarchy = require("editor.hierarchy")
local Inspector = require("editor.inspector")

local EditorApp = {}
EditorApp.__index = EditorApp

-- Editor Application instance를 생성한다.
function EditorApp.new(document)
    local self = setmetatable({}, EditorApp)

    self.sceneView = SceneView.new()
    self.hierarchy = Hierarchy.new()
    self.inspector = Inspector.new()

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

    -- EditorApp이 현재 LevelDocument를 소유하고,
    -- 각 surface는 그 document의 동일한 Level authoring data를 참조한다.
    self.document = document
    self.level = document.level

    self.sceneView.level = self.level
    self.hierarchy.level = self.level
    self.inspector.level = self.level

    -- document 교체 시 이전 document의 transient Editor state가
    -- 새 Level을 가리키지 않도록 초기화한다.
    self.sceneView.selectedLObject = nil
    self.sceneView.isDraggingLObject = false
    self.sceneView.isPanning = false
    self.inspector:cancelEdit()

    return true
end

function EditorApp:saveCurrentDocument(path)
    -- Inspector text edit은 transient state이므로 저장 전에 authoring data에 확정한다.
    -- Ctrl+S가 edit 중 눌려도 화면에 보이는 값을 저장하게 한다.
    self.inspector:commitEdit()

    return self.document:save(path)
end

-- 현재 window 크기와 좌/우 panel 폭으로 Scene View의 실제 영역을 계산한다.
-- 아직 범용 layout system은 만들지 않고 현재 세 surface에 필요한 계산만 둔다.
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

-- LÖVE의 love.update(dt)에서 매 프레임 호출된다.
-- 현재는 아직 Editor 상태 갱신 로직이 없다.
function EditorApp:update(dt)
end

function EditorApp:draw()
    self:updateSceneViewport()

    -- 전체 window 배경을 한 번 지우고 각 surface가 자기 영역만 그린다.
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

    -- 다른 surface를 클릭하면 Inspector의 현재 숫자 편집을 먼저 확정한다.
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
    -- drag/pan이 Scene View 밖에서 끝나도 상태가 남지 않도록 release는 항상 전달한다.
    self.sceneView:mousereleased(x, y, button)
end

function EditorApp:mousemoved(x, y, dx, dy)
    -- 이미 시작된 drag/pan은 pointer가 viewport 밖으로 나가도 계속 처리한다.
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
    -- Save는 surface-local input보다 우선하는 Editor 전역 명령이다.
    -- 특히 Inspector edit 중 Ctrl+S도 정상적으로 현재 값을 commit하고 저장해야 한다.
    local controlDown =
        love.keyboard.isDown("lctrl", "rctrl")

    local shiftDown =
        love.keyboard.isDown("lshift", "rshift")

    if key == "s" and controlDown and not shiftDown then
        return self:saveCurrentDocument()
    end

    -- Ctrl+Shift+S는 이후 Save As에 사용할 수 있도록 현재 Save로 처리하지 않는다.
    if self.inspector:keypressed(key) then
        return
    end

    self:updateSceneViewport()

    local mouseX, mouseY = love.mouse.getPosition()

    -- 현재 mouse world position을 사용하는 명령은 Scene View 위에서만 허용한다.
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
