local Theme = require("editor.theme")
local UI = require("editor.ui")
local Gizmo = require("editor.transform_gizmo")
local SceneView = {}
SceneView.__index = SceneView

local DEFAULT_GRID_SIZE = 100

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

    -- camera offset은 Scene View viewport 중앙 기준의 screen-space 이동량이다.
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
    self.snapSettings = require("editor.snap_settings").copy()
    self.gizmoMode = "translate"

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
    local viewportX, viewportY, width, height = self:getViewport()
    local screenX = viewportX + width * 0.5 + self.cameraX + x * self.zoom
    local screenY = viewportY + height * 0.5 + self.cameraY + y * self.zoom

    return screenX, screenY
end

function SceneView:screenToWorld(x, y)
    local originX, originY = self:worldToScreen(0, 0)
    local worldX = (x - originX) / self.zoom
    local worldY = (y - originY) / self.zoom

    return worldX, worldY
end

local function getFirstGridLine(cameraPosition, spacing)
    return cameraPosition % spacing
end

function SceneView:getGridLines(width, height)
    local vertical = {}
    local horizontal = {}

    local spacing = self.gridSize * self.zoom
    local startX, startY = self:getViewport()
    local originX, originY = self:worldToScreen(0, 0)

    local firstX = startX + getFirstGridLine(originX - startX, spacing)
    local firstY = startY + getFirstGridLine(originY - startY, spacing)

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
        if self.spriteAssets then
            local preview = self.spriteAssets:preview(lobject)
            if preview and require("core.sprite_renderer").hit(preview, function(reference) return self.spriteAssets:image(reference) end, worldX, worldY) then return lobject end
        end

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

        local axis = Gizmo.hit(self, x, y)
        if axis then
            self.drag = Gizmo.begin(self, axis, x, y)
            self.isDraggingLObject = true
            return
        end
        local worldX, worldY = self:screenToWorld(x, y)
        local hitLObject = self:findLObjectAtWorldPosition(worldX, worldY)

        if hitLObject then
            self.selectedLObject = hitLObject
            self.isDraggingLObject = false
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
        self:cancelDrag(false)
    end

    if button == PAN_MOUSE_BUTTON then
        self.isPanning = false
    end
end

function SceneView:cancelDrag(restore)
    if restore and self.drag then
        for field, value in pairs(self.drag.initial) do self.drag.object.transform[field] = value end
    end
    self.drag, self.isDraggingLObject = nil, false
end

function SceneView:setGizmoMode(mode)
    if mode ~= "translate" and mode ~= "rotate" and mode ~= "scale" then return false end
    if self.gizmoMode ~= mode then self:cancelDrag(true); self.gizmoMode = mode end
    return true
end

function SceneView:setSnap(mode, enabled, unit)
    if not self.snapSettings[mode] or type(enabled) ~= "boolean" or not require("editor.snap_settings").validUnit(unit) then return false, "Snap unit must be a positive finite number" end
    self.snapSettings[mode] = {enabled = enabled, unit = unit}
    if self.onSnapChanged then return self.onSnapChanged(self.snapSettings) end
    return true
end

function SceneView:snapValue(value, mode)
    local setting = self.snapSettings[mode or "translate"]
    if not setting.enabled then return value end
    local scaled = value / setting.unit
    return (scaled >= 0 and math.floor(scaled + 0.5) or math.ceil(scaled - 0.5)) * setting.unit
end

function SceneView:snapPosition(x, y)
    local transform = self.selectedLObject and self.selectedLObject.transform or {x = x, y = y}
    return transform.x + self:snapValue(x - transform.x), transform.y + self:snapValue(y - transform.y)
end

function SceneView:mousemoved(x, y, dx, dy)
    if self.isDraggingLObject and self.drag then
        Gizmo.update(self, self.drag, dx, dy)
        return
    end

    if self.isPanning then
        self.cameraX = self.cameraX + dx
        self.cameraY = self.cameraY + dy
    end
end

function SceneView:frameSelected()
    if not self.selectedLObject or not self.selectedLObject.transform then
        return false
    end

    local transform = self.selectedLObject.transform

    -- 선택된 LObject의 world 위치가 현재 Scene View 정중앙에 오도록
    -- viewport 위치와 독립적인 camera offset만 조정한다.
    self.cameraX = -transform.x * self.zoom
    self.cameraY = -transform.y * self.zoom

    return true
end

function SceneView:keypressed(key, controlDown, mouseX, mouseY)
    if key == "escape" then self:cancelDrag(true); return end
    if not controlDown then
        local modes = {w = "translate", e = "rotate", r = "scale"}
        if modes[key] then self:setGizmoMode(modes[key]); return end
    end
    if key == "f" and not controlDown then
        self:frameSelected()
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

        local worldX, worldY = self:snapPosition(self:screenToWorld(mouseX, mouseY))
        local duplicate = self.level:duplicateLObject(
            self.selectedLObject,
            worldX,
            worldY
        )

        if duplicate then
            self.selectedLObject = duplicate
            self:cancelDrag(false)
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
    self:cancelDrag(false)
end

function SceneView:zoomAtScreenPosition(screenX, screenY, wheelY)
    if self.isDraggingLObject then return end
    if wheelY == 0 then
        return
    end

    local worldX, worldY = self:screenToWorld(screenX, screenY)
    local newZoom = clamp(self.zoom + wheelY * ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)

    if newZoom == self.zoom then
        return
    end

    self.zoom = newZoom

    -- 확대 전후 커서 아래의 world 좌표가 같도록 중앙 기준 이동량을 보정한다.
    local viewportX, viewportY, width, height = self:getViewport()
    self.cameraX = screenX - viewportX - width * 0.5 - worldX * self.zoom
    self.cameraY = screenY - viewportY - height * 0.5 - worldY * self.zoom
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
        Theme.setColor("axisY")
        love.graphics.line(originX, viewportY, originX, bottom)
    end

    if originY >= viewportY and originY <= bottom then
        Theme.setColor("axisX")
        love.graphics.line(viewportX, originY, right, originY)
    end

    if originX >= viewportX and originX <= right
        and originY >= viewportY and originY <= bottom
    then
        Theme.setColor("origin")
        love.graphics.circle("fill", originX, originY, 4)
    end
end

function SceneView:drawLObjects()
    if not self.level then
        return
    end

    love.graphics.setLineWidth(2)

    for _, lobject in ipairs(self.level.lobjects) do
        if self.spriteAssets then
            local preview = self.spriteAssets:preview(lobject)
            if preview then self.spriteAssets:draw(preview, self, self.zoom) end
        end
    end
    if self.selectedLObject and self.spriteAssets then
        local preview = self.spriteAssets:preview(self.selectedLObject)
        if preview then
            Theme.setColor("objectSelected")
            love.graphics.setLineWidth(2)
            require("core.sprite_renderer").outline(preview, function(reference) return self.spriteAssets:image(reference) end,
                function(x, y) return self:worldToScreen(x, y) end)
        end
    end
    Gizmo.draw(self)
end

function SceneView:drawMouseWorldPosition()
    local mouseX, mouseY = love.mouse.getPosition()
    local viewportX, viewportY = self:getViewport()

    Theme.setColor("text")

    if self:containsPoint(mouseX, mouseY) then
        local worldX, worldY = self:screenToWorld(mouseX, mouseY)

        love.graphics.print(
            string.format("Mouse: (%.1f, %.1f)", worldX, worldY),
            viewportX + UI.metrics.contentPaddingX,
            viewportY + 36 + UI.metrics.contentPaddingY
        )
    else
        love.graphics.print("Mouse: --", viewportX + UI.metrics.contentPaddingX, viewportY + 36 + UI.metrics.contentPaddingY)
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

    require("editor.ui").panel(viewportX, viewportY, width, height, "viewportBackground")
    -- 좌표 변환의 기준 사각형은 유지하고 콘텐츠만 테두리 안쪽으로 제한한다.
    love.graphics.intersectScissor(viewportX + 12, viewportY + 12, math.max(0, width - 24), math.max(0, height - 24))

    Theme.setColor("grid")
    love.graphics.setLineWidth(1)

    for _, x in ipairs(vertical) do
        love.graphics.line(x, viewportY, x, bottom)
    end

    for _, y in ipairs(horizontal) do
        love.graphics.line(viewportX, y, right, y)
    end

    self:drawWorldAxes()
    self:drawLObjects()

    Theme.setColor("text")
    UI.panelHeading(
        string.format("Scene View  %.2fx", self.zoom),
        viewportX,
        viewportY,
        width
    )
    self:drawMouseWorldPosition()
    love.graphics.print(
        "W: Move  E: Rotate  R: Scale",
        viewportX + UI.metrics.contentPaddingX,
        viewportY + 56 + UI.metrics.contentPaddingY
    )
    love.graphics.print("Ctrl+D: Duplicate  F: Frame  Delete: Delete",
        viewportX + UI.metrics.contentPaddingX, viewportY + 76 + UI.metrics.contentPaddingY)

    love.graphics.pop()
end

return SceneView
