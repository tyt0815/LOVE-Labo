local SceneView = {}
SceneView.__index = SceneView

local DEFAULT_GRID_SIZE = 32

function SceneView.new(gridSize)
    local self = setmetatable({}, SceneView)

    self.gridSize = gridSize or DEFAULT_GRID_SIZE

    return self
end

-- Scene View 크기에 맞춰 그리드 선 좌표를 계산한다.
-- 계산 자체는 love.graphics와 분리해서 테스트할 수 있게 유지한다.
function SceneView:getGridLines(width, height)
    local vertical = {}
    local horizontal = {}

    for x = 0, width, self.gridSize do
        vertical[#vertical + 1] = x
    end

    for y = 0, height, self.gridSize do
        horizontal[#horizontal + 1] = y
    end

    return vertical, horizontal
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
