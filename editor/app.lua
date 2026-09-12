local SceneView = require("editor.scene_view")

local EditorApp = {}
EditorApp.__index = EditorApp

-- Editor Application instance를 생성한다.
function EditorApp.new()
    local self = setmetatable({}, EditorApp)

    self.sceneView = SceneView.new()

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

return EditorApp