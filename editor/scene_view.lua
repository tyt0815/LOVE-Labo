local SceneView = {}
SceneView.__index = SceneView

local DEFAULT_GRID_SIZE = 32

local LEFT_MOUSE_BUTTON = 1
local PAN_MOUSE_BUTTON = 3

local DEFAULT_ZOOM = 1.0
local ZOOM_STEP = 0.25
local MIN_ZOOM = 0.25
local MAX_ZOOM = 4.0

local LOBJECT_SIZE = 16

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end

function SceneView.new(gridSize, level)
    local self = setmetatable({}, SceneView)

    self.gridSize = gridSize or DEFAULT_GRID_SIZE
    self.level = level

    -- 현재 camera는 별도 subsystem 없이
    -- Scene View 내부의 screen-space offset으로 관리한다.
    self.cameraX = 0
    self.cameraY = 0

    self.zoom = DEFAULT_ZOOM
    self.isPanning = false

    -- 선택 상태와 drag 상태는 Editor에서만 사용하는 transient state다.
    self.selectedLObject = nil
    self.isDraggingLObject = false

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

function SceneView:findLObjectAtWorldPosition(worldX, worldY)
    if not self.level then
        return nil
    end

    local halfSize = LOBJECT_SIZE * 0.5

    for i = #self.level.lobjects, 1, -1 do
        local lobject = self.level.lobjects[i]
        local transform = lobject.transform

        local insideX =
            worldX >= transform.x - halfSize
            and worldX <= transform.x + halfSize

        local insideY =
            worldY >= transform.y - halfSize
            and worldY <= transform.y + halfSize

        if insideX and insideY then
            return lobject
        end
    end

    return nil
end

function SceneView:mousepressed(x, y, button)
    if button == LEFT_MOUSE_BUTTON then
        if not self.level then
            return
        end

        local worldX, worldY = self:screenToWorld(x, y)
        local hitLObject = self:findLObjectAtWorldPosition(worldX, worldY)

        if hitLObject then
            self.selectedLObject = hitLObject
            self.isDraggingLObject = true
        else
            self.selectedLObject = self.level:addLObject(worldX, worldY)
            self.isDraggingLObject = false
        end

        return
    end

    if button == PAN_MOUSE_BUTTON then
        self.isPanning = true
    end
end

function SceneView:mousereleased(x, y, button)
    if button == LEFT_MOUSE_BUTTON then
        self.isDraggingLObject = false
    end

    if button == PAN_MOUSE_BUTTON then
        self.isPanning = false
    end
end

function SceneView:mousemoved(x, y, dx, dy)
    if self.isDraggingLObject and self.selectedLObject then
        local worldDX = dx / self.zoom
        local worldDY = dy / self.zoom
        local transform = self.selectedLObject.transform

        transform.x = transform.x + worldDX
        transform.y = transform.y + worldDY
        return
    end

    if self.isPanning then
        self.cameraX = self.cameraX + dx
        self.cameraY = self.cameraY + dy
    end
end

function SceneView:keypressed(key)
    if key ~= "delete" then
        return
    end

    if not self.level or not self.selectedLObject then
        return
    end

    -- Level이 실제 authoring data의 소유자이므로
    -- Scene View는 직접 table.remove 하지 않고 Level에 제거를 요청한다.
    self.level:removeLObject(self.selectedLObject)
    self.selectedLObject = nil
    self.isDraggingLObject = false
end

function SceneView:zoomAtScreenPosition(screenX, screenY, wheelY)
    if wheelY == 0 then
        return
    end

    local worldX, worldY = self:screenToWorld(screenX, screenY)
    local newZoom = clamp(self.zoom + wheelY * ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)

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

    local mouseX, mouseY = love.mouse.getPosition()
    self:zoomAtScreenPosition(mouseX, mouseY, y)
end

function SceneView:drawWorldAxes(width, height)
    local originX, originY = self:worldToScreen(0, 0)

    love.graphics.setLineWidth(2)

    if originX >= 0 and originX <= width then
        love.graphics.setColor(0.75, 0.32, 0.32, 1.0)
        love.graphics.line(originX, 0, originX, height)
    end

    if originY >= 0 and originY <= height then
        love.graphics.setColor(0.32, 0.70, 0.38, 1.0)
        love.graphics.line(0, originY, width, originY)
    end

    if originX >= 0 and originX <= width and originY >= 0 and originY <= height then
        love.graphics.setColor(0.92, 0.92, 0.94, 1.0)
        love.graphics.circle("fill", originX, originY, 4)
    end
end

function SceneView:drawLObjects()
    if not self.level then
        return
    end

    love.graphics.setLineWidth(2)

    for _, lobject in ipairs(self.level.lobjects) do
        local transform = lobject.transform
        local screenX, screenY = self:worldToScreen(transform.x, transform.y)
        local size = LOBJECT_SIZE * self.zoom
        local halfSize = size * 0.5

        if lobject == self.selectedLObject then
            love.graphics.setColor(0.0, 1.0, 0.0, 1.0)
        else
            love.graphics.setColor(1.0, 0.0, 0.0, 1.0)
        end

        love.graphics.rectangle("line", screenX - halfSize, screenY - halfSize, size, size)
    end
end

function SceneView:drawMouseWorldPosition()
    local mouseX, mouseY = love.mouse.getPosition()
    local worldX, worldY = self:screenToWorld(mouseX, mouseY)

    love.graphics.setColor(0.92, 0.92, 0.94, 1.0)
    love.graphics.print(string.format("Mouse: (%.1f, %.1f)", worldX, worldY), 16, 36)
end

function SceneView:draw()
    local width, height = love.graphics.getDimensions()
    local vertical, horizontal = self:getGridLines(width, height)

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

    self:drawWorldAxes(width, height)
    self:drawLObjects()

    love.graphics.setColor(0.92, 0.92, 0.94, 1.0)
    love.graphics.print(string.format("Scene View  %.2fx", self.zoom), 16, 16)
    self:drawMouseWorldPosition()

    love.graphics.pop()
end

return SceneView
