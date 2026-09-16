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

    -- camera offset은 Scene View viewport 내부 screen-space 기준이다.
    -- Editor panel의 위치와 camera를 섞지 않기 위해 viewport 위치는 별도로 관리한다.
    self.cameraX = 0
    self.cameraY = 0

    self.zoom = DEFAULT_ZOOM
    self.isPanning = false

    -- nil width/height는 아직 별도 viewport를 지정하지 않은 상태다.
    -- 이 경우 기존처럼 전체 window를 Scene View로 사용한다.
    self.viewportX = 0
    self.viewportY = 0
    self.viewportWidth = nil
    self.viewportHeight = nil

    -- 선택 상태와 drag 상태는 Editor에서만 사용하는 transient state다.
    self.selectedLObject = nil
    self.isDraggingLObject = false

    return self
end

function SceneView:setViewport(x, y, width, height)
    self.viewportX = x
    self.viewportY = y
    self.viewportWidth = math.max(0, width)
    self.viewportHeight = math.max(0, height)
end

function SceneView:getViewport()
    if self.viewportWidth ~= nil and self.viewportHeight ~= nil then
        return self.viewportX, self.viewportY, self.viewportWidth, self.viewportHeight
    end

    local width, height = love.graphics.getDimensions()
    return 0, 0, width, height
end

function SceneView:containsPoint(x, y)
    -- 테스트나 독립 사용처럼 viewport가 아직 지정되지 않았다면
    -- 입력 영역 제한 없이 기존 동작을 유지한다.
    if self.viewportWidth == nil or self.viewportHeight == nil then
        return true
    end

    return x >= self.viewportX
        and x < self.viewportX + self.viewportWidth
        and y >= self.viewportY
        and y < self.viewportY + self.viewportHeight
end

function SceneView:worldToScreen(x, y)
    local screenX = self.viewportX + self.cameraX + x * self.zoom
    local screenY = self.viewportY + self.cameraY + y * self.zoom

    return screenX, screenY
end

function SceneView:screenToWorld(x, y)
    local worldX = (x - self.viewportX - self.cameraX) / self.zoom
    local worldY = (y - self.viewportY - self.cameraY) / self.zoom

    return worldX, worldY
end

local function getFirstGridLine(cameraPosition, spacing)
    return cameraPosition % spacing
end

function SceneView:getGridLines(width, height)
    local vertical = {}
    local horizontal = {}

    local spacing = self.gridSize * self.zoom
    local startX = self.viewportX
    local startY = self.viewportY

    local firstX = startX + getFirstGridLine(self.cameraX, spacing)
    local firstY = startY + getFirstGridLine(self.cameraY, spacing)

    local endX = startX + width
    local endY = startY + height

    for x = firstX, endX, spacing do
        vertical[#vertical + 1] = x
    end

    for y = firstY, endY, spacing do
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
    if not self:containsPoint(x, y) then
        return
    end

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
            -- 빈 공간 클릭은 새 LObject를 만들지 않고 현재 선택만 해제한다.
            self.selectedLObject = nil
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

function SceneView:keypressed(key, controlDown, mouseX, mouseY)
    if key == "a" and not controlDown then
        if not self.level
            or mouseX == nil
            or mouseY == nil
            or not self:containsPoint(mouseX, mouseY)
        then
            return
        end

        local worldX, worldY = self:screenToWorld(mouseX, mouseY)

        -- 현재는 별도 Asset/Palette가 없으므로 A 키를 임시 생성 입력으로 사용한다.
        self.selectedLObject = self.level:addLObject(worldX, worldY)
        self.isDraggingLObject = false
        return
    end

    if key == "d" and controlDown then
        if not self.level
            or not self.selectedLObject
            or mouseX == nil
            or mouseY == nil
            or not self:containsPoint(mouseX, mouseY)
        then
            return
        end

        local worldX, worldY = self:screenToWorld(mouseX, mouseY)
        local duplicate = self.level:duplicateLObject(
            self.selectedLObject,
            worldX,
            worldY
        )

        if duplicate then
            self.selectedLObject = duplicate
            self.isDraggingLObject = false
        end

        return
    end

    if key ~= "delete" then
        return
    end

    if not self.level or not self.selectedLObject then
        return
    end

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

    -- viewport 위치는 camera offset과 별도이므로 다시 빼준다.
    self.cameraX = screenX - self.viewportX - worldX * self.zoom
    self.cameraY = screenY - self.viewportY - worldY * self.zoom
end

function SceneView:wheelmoved(x, y)
    if y == 0 then
        return
    end

    local mouseX, mouseY = love.mouse.getPosition()

    if not self:containsPoint(mouseX, mouseY) then
        return
    end

    self:zoomAtScreenPosition(mouseX, mouseY, y)
end

function SceneView:drawWorldAxes()
    local viewportX, viewportY, width, height = self:getViewport()
    local originX, originY = self:worldToScreen(0, 0)

    local right = viewportX + width
    local bottom = viewportY + height

    love.graphics.setLineWidth(2)

    if originX >= viewportX and originX <= right then
        love.graphics.setColor(0.75, 0.32, 0.32, 1.0)
        love.graphics.line(originX, viewportY, originX, bottom)
    end

    if originY >= viewportY and originY <= bottom then
        love.graphics.setColor(0.32, 0.70, 0.38, 1.0)
        love.graphics.line(viewportX, originY, right, originY)
    end

    if originX >= viewportX and originX <= right
        and originY >= viewportY and originY <= bottom
    then
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
    local viewportX, viewportY = self:getViewport()

    love.graphics.setColor(0.92, 0.92, 0.94, 1.0)

    if self:containsPoint(mouseX, mouseY) then
        local worldX, worldY = self:screenToWorld(mouseX, mouseY)

        love.graphics.print(
            string.format("Mouse: (%.1f, %.1f)", worldX, worldY),
            viewportX + 16,
            viewportY + 36
        )
    else
        love.graphics.print("Mouse: --", viewportX + 16, viewportY + 36)
    end
end

function SceneView:draw()
    local viewportX, viewportY, width, height = self:getViewport()

    if width <= 0 or height <= 0 then
        return
    end

    local vertical, horizontal = self:getGridLines(width, height)
    local right = viewportX + width
    local bottom = viewportY + height

    love.graphics.push("all")

    -- Scene View는 이제 자신의 실제 viewport 밖으로 그리지 않는다.
    love.graphics.setScissor(viewportX, viewportY, width, height)

    love.graphics.setColor(0.08, 0.09, 0.11, 1.0)
    love.graphics.rectangle("fill", viewportX, viewportY, width, height)

    love.graphics.setColor(0.16, 0.17, 0.20, 1.0)
    love.graphics.setLineWidth(1)

    for _, x in ipairs(vertical) do
        love.graphics.line(x, viewportY, x, bottom)
    end

    for _, y in ipairs(horizontal) do
        love.graphics.line(viewportX, y, right, y)
    end

    self:drawWorldAxes()
    self:drawLObjects()

    love.graphics.setColor(0.92, 0.92, 0.94, 1.0)
    love.graphics.print(
        string.format("Scene View  %.2fx", self.zoom),
        viewportX + 16,
        viewportY + 16
    )
    self:drawMouseWorldPosition()
    love.graphics.print(
        "A: Add  Ctrl+D: Duplicate  Delete: Delete",
        viewportX + 16,
        viewportY + 56
    )

    love.graphics.pop()
end

return SceneView
