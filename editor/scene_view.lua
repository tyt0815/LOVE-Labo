local SceneView = {}
SceneView.__index = SceneView

local DEFAULT_GRID_SIZE = 32

local LEFT_MOUSE_BUTTON = 1
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
    -- Scene View 내부의 screen-space offset으로 관리한다.
    self.cameraX = 0
    self.cameraY = 0

    self.zoom = DEFAULT_ZOOM
    self.isPanning = false

    -- 아직 실제 Actor selection은 없으므로,
    -- 좌클릭한 world 위치 하나만 임시 선택 상태로 보관한다.
    self.selectedWorldX = nil
    self.selectedWorldY = nil

    return self
end

function SceneView:worldToScreen(x, y)
    local screenX = x * self.zoom + self.cameraX
    local screenY = y * self.zoom + self.cameraY

    return screenX, screenY
end

function SceneView:screenToWorld(x, y)
    local worldX = (x - self.cameraX) / self.zoom
    local worldY = (y - self.cameraY) / self.zoom

    return worldX, worldY
end

local function getFirstGridLine(cameraPosition, spacing)
    return cameraPosition % spacing
end

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
    if button == LEFT_MOUSE_BUTTON then
        self.selectedWorldX, self.selectedWorldY =
            self:screenToWorld(x, y)

        return
    end

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

    self.cameraX = self.cameraX + dx
    self.cameraY = self.cameraY + dy
end

-- 특정 screen 위치를 중심으로 zoom한다.
--
-- zoom 변경 전 cursor 아래에 있던 world 좌표를 먼저 구한 뒤,
-- zoom 변경 후에도 그 world 좌표가 같은 screen 위치에 오도록
-- camera offset을 다시 계산한다.
function SceneView:zoomAtScreenPosition(screenX, screenY, wheelY)
    if wheelY == 0 then
        return
    end

    local worldX, worldY =
        self:screenToWorld(screenX, screenY)

    local newZoom = clamp(
        self.zoom + wheelY * ZOOM_STEP,
        MIN_ZOOM,
        MAX_ZOOM
    )

    if newZoom == self.zoom then
        return
    end

    self.zoom = newZoom

    self.cameraX = screenX - worldX * self.zoom
    self.cameraY = screenY - worldY * self.zoom
end

function SceneView:wheelmoved(x, y)
    if y == 0 then
        return
    end

    -- love.wheelmoved의 x/y는 wheel 이동량이지
    -- mouse cursor 좌표가 아니다.
    -- 따라서 현재 cursor 위치는 love.mouse에서 별도로 가져온다.
    local mouseX, mouseY = love.mouse.getPosition()

    self:zoomAtScreenPosition(mouseX, mouseY, y)
end

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

    if originX >= 0
        and originX <= width
        and originY >= 0
        and originY <= height then

        love.graphics.setColor(0.92, 0.92, 0.94, 1.0)
        love.graphics.circle("fill", originX, originY, 4)
    end
end

function SceneView:drawSelectedWorldPosition()
    if self.selectedWorldX == nil or self.selectedWorldY == nil then
        return
    end

    local screenX, screenY =
        self:worldToScreen(self.selectedWorldX, self.selectedWorldY)

    love.graphics.setColor(0.95, 0.78, 0.25, 1.0)
    love.graphics.setLineWidth(2)

    local markerSize = 8

    love.graphics.line(
        screenX - markerSize,
        screenY,
        screenX + markerSize,
        screenY
    )

    love.graphics.line(
        screenX,
        screenY - markerSize,
        screenX,
        screenY + markerSize
    )

    love.graphics.circle("line", screenX, screenY, 5)
end

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

    self:drawWorldAxes(width, height)
    self:drawSelectedWorldPosition()

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