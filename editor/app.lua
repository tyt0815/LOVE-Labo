local Level = require("editor.level")
local SceneView = require("editor.scene_view")
local Hierarchy = require("editor.hierarchy")
local Inspector = require("editor.inspector")

local EditorApp = {}
EditorApp.__index = EditorApp

-- Editor Application instance를 생성한다.
function EditorApp.new()
    local self = setmetatable({}, EditorApp)

    -- Level이 authoring data를 소유하고,
    -- 각 Editor surface는 같은 Level을 서로 다른 방식으로 표시/편집한다.
    self.level = Level.new()
    self.sceneView = SceneView.new(nil, self.level)
    self.hierarchy = Hierarchy.new(self.level)
    self.inspector = Inspector.new(self.level)

    return self
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
            self.sceneView.selectedLObject = self.hierarchy:getLObjectAtPosition(x, y)
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
    if self.inspector:keypressed(key) then
        return
    end

    self:updateSceneViewport()

    local controlDown = love.keyboard.isDown("lctrl", "rctrl")
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

    self.sceneView:keypressed(key, controlDown, mouseX, mouseY)
end

return EditorApp
