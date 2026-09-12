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

-- World 좌표를 현재 Scene View camera 기준의 screen 좌표로 변환한다.
--
-- cameraX/Y는 screen-space offset이고,
-- zoom은 world 단위에 적용되는 scale이다.
function SceneView:worldToScreen(x, y)
    local screenX = x * self.zoom + self.cameraX
    local screenY = y * self.zoom + self.cameraY

    return screenX, screenY
end

-- Screen 좌표를 현재 Scene View의 world 좌표로 되돌린다.
-- worldToScreen의 역변환이다.
function SceneView:screenToWorld(x, y)
    local worldX = (x - self.cameraX) / self.zoom
    local worldY = (y - self.cameraY) / self.zoom

    return worldX, worldY
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

    -- 현재는 cursor 중심 보정 없이
    -- Scene View 전체의 scale만 변경한다.
    self.zoom = clamp(
        self.zoom + y * ZOOM_STEP,
        MIN_ZOOM,
        MAX_ZOOM
    )
end

-- World 원점 기준의 X/Y 축을 그린다.
--
-- LÖVE의 screen 좌표는 +Y가 아래쪽이므로
-- 현재 단계에서는 world 좌표도 동일한 방향을 사용한다.
function SceneView:drawWorldAxes(width, height)
    local originX, originY = self:worldToScreen(0, 0)

    love.graphics.setLineWidth(2)

    -- Y축: world x = 0
    if originX >= 0 and originX <= width then
        love.graphics.setColor(0.75, 0.32, 0.32, 1.0)
        love.graphics.line(originX, 0, originX, height)
    end

    -- X축: world y = 0
    if originY >= 0 and originY <= height then
        love.graphics.setColor(0.32, 0.70, 0.38, 1.0)
        love.graphics.line(0, originY, width, originY)
    end

    -- 원점 자체가 화면 안에 있을 때 작은 marker도 표시한다.
    if originX >= 0
        and originX <= width
        and originY >= 0
        and originY <= height then

        love.graphics.setColor(0.92, 0.92, 0.94, 1.0)
        love.graphics.circle("fill", originX, originY, 4)
    end
end

-- 현재 mouse의 screen 좌표를 world 좌표로 변환해서 표시한다.
function SceneView:drawMouseWorldPosition()
    local mouseX, mouseY = love.mouse.getPosition()
    local worldX, worldY = self:screenToWorld(mouseX, mouseY)

    love.graphics.setColor(0.92, 0.92, 0.94, 1.0)

    love.graphics.print(
        string.format("Mouse: (%.1f, %.1f)", worldX, worldY),
        16,
        36
    )
end

function SceneView:draw()
    local width, height = love.graphics.getDimensions()
    local vertical, horizontal = self:getGridLines(width, height)

    -- love.graphics는 전역 state를 가지므로 Scene View가 바꾼 상태를
    -- Editor의 다른 rendering에 누수시키지 않도록 push/pop으로 감싼다.
    love.graphics.push("all")

    love.graphics.clear(0.08, 0.09, 0.11, 1.0)

    -- 일반 grid.
    love.graphics.setColor(0.16, 0.17, 0.20, 1.0)
    love.graphics.setLineWidth(1)

    for _, x in ipairs(vertical) do
        love.graphics.line(x, 0, x, height)
    end

    for _, y in ipairs(horizontal) do
        love.graphics.line(0, y, width, y)
    end

    -- Grid 위에 world 원점과 축을 표시한다.
    self:drawWorldAxes(width, height)

    love.graphics.setColor(0.92, 0.92, 0.94, 1.0)

    love.graphics.print(
        string.format("Scene View  %.2fx", self.zoom),
        16,
        16
    )

    self:drawMouseWorldPosition()

    love.graphics.pop()
end

return SceneView