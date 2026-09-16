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

-- LÖVE의 love.update(dt)에서 매 프레임 호출된다.
-- 현재는 아직 Editor 상태 갱신 로직이 없다.
function EditorApp:update(dt)
end

function EditorApp:draw()
    -- 아직 별도 layout system은 만들지 않고
    -- Scene View 위에 좌/우 Editor panel을 overlay한다.
    self.sceneView:draw()
    self.hierarchy:draw(self.sceneView.selectedLObject)
    self.inspector:draw(self.sceneView.selectedLObject)
end

function EditorApp:mousepressed(x, y, button)
    local windowWidth = love.graphics.getWidth()

    if self.hierarchy:containsPoint(x, y) then
        -- Hierarchy 영역의 모든 mouse press는 여기서 소비한다.
        -- 좌클릭만 selection을 변경하고, 중클릭 등이 뒤쪽 Scene View로 새지 않게 한다.
        if button == 1 then
            self.sceneView.selectedLObject = self.hierarchy:getLObjectAtPosition(x, y)
            self.sceneView.isDraggingLObject = false
        end

        return
    end

    if self.inspector:containsPoint(x, y, windowWidth) then
        -- 현재 Inspector는 읽기 전용이다.
        -- 패널 위 mouse press가 뒤쪽 Scene View에 전달되지 않게만 한다.
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
    local windowWidth = love.graphics.getWidth()

    -- Editor panel 위 wheel이 뒤쪽 Scene View zoom으로 전달되지 않게 한다.
    if self.hierarchy:containsPoint(mouseX, mouseY)
        or self.inspector:containsPoint(mouseX, mouseY, windowWidth)
    then
        return
    end

    self.sceneView:wheelmoved(x, y)
end

function EditorApp:keypressed(key)
    -- LÖVE의 keyboard state는 App 경계에서 읽고,
    -- Scene View에는 필요한 modifier 상태만 전달한다.
    local controlDown = love.keyboard.isDown("lctrl", "rctrl")
    local mouseX, mouseY = love.mouse.getPosition()
    local windowWidth = love.graphics.getWidth()

    -- A와 Ctrl+D는 현재 mouse world position을 사용하는 Scene View 명령이다.
    -- 마우스가 Editor panel 위에 있으면 뒤쪽 Scene View에 생성/복제가 일어나지 않게 한다.
    local usesMouseWorldPosition =
        (key == "a" and not controlDown)
        or (key == "d" and controlDown)

    if usesMouseWorldPosition then
        local mouseOverEditorPanel =
            self.hierarchy:containsPoint(mouseX, mouseY)
            or self.inspector:containsPoint(mouseX, mouseY, windowWidth)

        if mouseOverEditorPanel then
            return
        end
    end

    self.sceneView:keypressed(key, controlDown, mouseX, mouseY)
end

return EditorApp
