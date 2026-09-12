local SceneView = {}
SceneView.__index = SceneView

local DEFAULT_GRID_SIZE = 32
local PAN_MOUSE_BUTTON = 3

local DEFAULT_ZOOM = 1.0
local ZOOM_STEP = 0.25
local MIN_ZOOM = 0.25
local MAX_ZOOM = 4.0

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end

function SceneView.new(gridSize)
    local self = setmetatable({}, SceneView)

    self.gridSize = gridSize or DEFAULT_GRID_SIZE

    -- 현재 camera는 별도 subsystem 없이
    -- Scene View 내부의 screen-space offset으로만 관리한다.
    self.cameraX = 0
    self.cameraY = 0

    self.zoom = DEFAULT_ZOOM
    self.isPanning = false

    return self
end

-- 현재 camera offset에 맞춰 화면 안의 첫 번째 grid line 위치를 계산한다.
local function getFirstGridLine(cameraPosition, spacing)
    return cameraPosition % spacing
end

-- Scene View 크기, camera offset, zoom을 기준으로
-- 화면에 표시할 grid line 좌표를 계산한다.
function SceneView:getGridLines(width, height)
    local vertical = {}
    local horizontal = {}

    local spacing = self.gridSize * self.zoom

    local firstX = getFirstGridLine(self.cameraX, spacing)
    local firstY = getFirstGridLine(self.cameraY, spacing)

    for x = firstX, width, spacing do
        vertical[#vertical + 1] = x
    end

    for y = firstY, height, spacing do
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
    -- 현재 camera offset은 screen-space pixel 단위다.
    self.cameraX = self.cameraX + dx
    self.cameraY = self.cameraY + dy
end

function SceneView:wheelmoved(x, y)
    if y == 0 then
        return
    end

    -- 이번 단계에서는 cursor 중심 보정 없이
    -- Scene View 전체의 grid scale만 단순하게 변경한다.
    self.zoom = clamp(
        self.zoom + y * ZOOM_STEP,
        MIN_ZOOM,
        MAX_ZOOM
    )
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
    love.graphics.print(
        string.format("Scene View  %.2fx", self.zoom),
        16,
        16
    )

    love.graphics.pop()
end

return SceneView