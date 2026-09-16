local Level = require("editor.level")
local SceneView = require("editor.scene_view")
local Hierarchy = require("editor.hierarchy")

local EditorApp = {}
EditorApp.__index = EditorApp

-- Editor Application instance를 생성한다.
function EditorApp.new()
    local self = setmetatable({}, EditorApp)

    -- Level이 authoring data를 소유하고,
    -- Scene View와 Hierarchy는 같은 Level을 서로 다른 방식으로 편집/표시한다.
    self.level = Level.new()
    self.sceneView = SceneView.new(nil, self.level)
    self.hierarchy = Hierarchy.new(self.level)

    return self
end

-- LÖVE의 love.update(dt)에서 매 프레임 호출된다.
-- 현재는 아직 Editor 상태 갱신 로직이 없다.
function EditorApp:update(dt)
end

function EditorApp:draw()
    -- Scene View를 먼저 그린 뒤 Hierarchy를 overlay한다.
    -- 아직 별도 layout system은 만들지 않고 입력만 패널 경계에서 분리한다.
    self.sceneView:draw()
    self.hierarchy:draw(self.sceneView.selectedLObject)
end

function EditorApp:mousepressed(x, y, button)
    if self.hierarchy:containsPoint(x, y) then
        -- Hierarchy 영역의 모든 mouse press는 여기서 소비한다.
        -- 좌클릭만 selection을 변경하고, 중클릭 등이 뒤쪽 Scene View로 새지 않게 한다.
        if button == 1 then
            self.sceneView.selectedLObject = self.hierarchy:getLObjectAtPosition(x, y)
            self.sceneView.isDraggingLObject = false
        end

        return
    end

    self.sceneView:mousepressed(x, y, button)
end

function EditorApp:mousereleased(x, y, button)
    self.sceneView:mousereleased(x, y, button)
end

function EditorApp:mousemoved(x, y, dx, dy)
    self.sceneView:mousemoved(x, y, dx, dy)
end

function EditorApp:wheelmoved(x, y)
    local mouseX, mouseY = love.mouse.getPosition()

    -- Hierarchy 위에서 wheel을 움직였을 때 뒤쪽 Scene View가 zoom되지 않게 한다.
    if self.hierarchy:containsPoint(mouseX, mouseY) then
        return
    end

    self.sceneView:wheelmoved(x, y)
end

function EditorApp:keypressed(key)
    -- LÖVE의 keyboard state는 App 경계에서 읽고,
    -- Scene View에는 필요한 modifier 상태만 전달한다.
    local controlDown = love.keyboard.isDown("lctrl", "rctrl")
    local mouseX, mouseY = love.mouse.getPosition()

    -- A와 Ctrl+D는 현재 mouse world position을 사용하는 Scene View 명령이다.
    -- 마우스가 Hierarchy 위에 있으면 뒤쪽 Scene View에 생성/복제가 일어나지 않게 한다.
    local usesMouseWorldPosition =
        (key == "a" and not controlDown)
        or (key == "d" and controlDown)

    if usesMouseWorldPosition and self.hierarchy:containsPoint(mouseX, mouseY) then
        return
    end

    self.sceneView:keypressed(key, controlDown, mouseX, mouseY)
end

return EditorApp
