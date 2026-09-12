local SceneView = {}
SceneView.__index = SceneView

local DEFAULT_GRID_SIZE = 32
local PAN_MOUSE_BUTTON = 3

function SceneView.new(gridSize)
    local self = setmetatable({}, SceneView)

    self.gridSize = gridSize or DEFAULT_GRID_SIZE

    -- 현재는 Scene View의 간단한 2D camera 위치만 관리한다.
    -- 양수 방향으로 이동하면 grid도 같은 방향으로 화면에서 이동한다.
    self.cameraX = 0
    self.cameraY = 0

    self.isPanning = false

    return self
end

-- 주어진 camera offset에 맞춰 첫 번째 grid line 위치를 계산한다.
-- Lua의 % 연산을 사용하면 camera가 음수로 이동해도
-- 화면 안쪽의 첫 grid 위치를 안정적으로 얻을 수 있다.
local function getFirstGridLine(cameraPosition, gridSize)
    return cameraPosition % gridSize
end

-- Scene View 크기와 camera 위치에 맞춰 그리드 선 좌표를 계산한다.
-- 계산 자체는 love.graphics와 분리해서 테스트할 수 있게 유지한다.
function SceneView:getGridLines(width, height)
    local vertical = {}
    local horizontal = {}

    local firstX = getFirstGridLine(self.cameraX, self.gridSize)
    local firstY = getFirstGridLine(self.cameraY, self.gridSize)

    for x = firstX, width, self.gridSize do
        vertical[#vertical + 1] = x
    end

    for y = firstY, height, self.gridSize do
        horizontal[#horizontal + 1] = y
    end

    return vertical, horizontal
end

function SceneView:mousepressed(x, y, button)
    if button == PAN_MOUSE_BUTTON then
        self.isPanning = true
    end
end

function SceneView:mousereleased(x, y, button)
    if button == PAN_MOUSE_BUTTON then
        self.isPanning = false
    end
end

function SceneView:mousemoved(x, y, dx, dy)
    if not self.isPanning then
        return
    end

    -- LÖVE가 전달하는 상대 이동량을 그대로 누적한다.
    -- 따라서 drag 중 cursor 이동과 Scene View 이동 방향이 같다.
    self.cameraX = self.cameraX + dx
    self.cameraY = self.cameraY + dy
end

function SceneView:draw()
    local width, height = love.graphics.getDimensions()
    local vertical, horizontal = self:getGridLines(width, height)

    -- love.graphics는 전역 state를 가지므로 Scene View가 바꾼 상태를
    -- Editor의 다른 rendering에 누수시키지 않도록 push/pop으로 감싼다.
    love.graphics.push("all")

    love.graphics.clear(0.08, 0.09, 0.11, 1.0)
    love.graphics.setColor(0.16, 0.17, 0.20, 1.0)
    love.graphics.setLineWidth(1)

    for _, x in ipairs(vertical) do
        love.graphics.line(x, 0, x, height)
    end

    for _, y in ipairs(horizontal) do
        love.graphics.line(0, y, width, y)
    end

    love.graphics.setColor(0.92, 0.92, 0.94, 1.0)
    love.graphics.print("Scene View", 16, 16)

    love.graphics.pop()
end

return SceneView