local Level = require("editor.level")
local SceneView = require("editor.scene_view")

local EditorApp = {}
EditorApp.__index = EditorApp

-- Editor Application instance를 생성한다.
function EditorApp.new()
    local self = setmetatable({}, EditorApp)

    -- Level이 authoring data를 소유하고
    -- Scene View는 그 Level을 편집하고 표시한다.
    self.level = Level.new()
    self.sceneView = SceneView.new(nil, self.level)

    return self
end

-- LÖVE의 love.update(dt)에서 매 프레임 호출된다.
-- 현재는 아직 Editor 상태 갱신 로직이 없다.
function EditorApp:update(dt)
end

-- 현재 첫 Editor surface인 Scene View를 그린다.
function EditorApp:draw()
    self.sceneView:draw()
end

function EditorApp:mousepressed(x, y, button)
    self.sceneView:mousepressed(x, y, button)
end

function EditorApp:mousereleased(x, y, button)
    self.sceneView:mousereleased(x, y, button)
end

function EditorApp:mousemoved(x, y, dx, dy)
    self.sceneView:mousemoved(x, y, dx, dy)
end

function EditorApp:wheelmoved(x, y)
    self.sceneView:wheelmoved(x, y)
end

function EditorApp:keypressed(key)
    -- LÖVE의 keyboard state는 App 경계에서 읽고,
    -- Scene View에는 필요한 modifier 상태만 전달한다.
    local controlDown = love.keyboard.isDown("lctrl", "rctrl")
    local mouseX, mouseY = love.mouse.getPosition()

    self.sceneView:keypressed(key, controlDown, mouseX, mouseY)
end

return EditorApp
