local EditorApp = {}
EditorApp.__index = EditorApp

-- Editor Application instance를 생성한다.
-- 지금은 상태가 전혀 없으므로 빈 table을 instance로 사용한다.
function EditorApp.new()
    return setmetatable({}, EditorApp)
end

-- LÖVE의 love.update(dt)에서 매 프레임 호출된다.
-- Task 1에서는 아직 Editor 상태 갱신 로직이 없다.
function EditorApp:update(dt)
end

-- LÖVE의 love.draw()에서 매 프레임 호출된다.
-- Task 1에서는 Editor가 정상적으로 부팅되었는지만 화면에 표시한다.
function EditorApp:draw()
    love.graphics.print("LÖVE Labo", 20, 20)
end

return EditorApp