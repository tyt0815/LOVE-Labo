local Theme = require("editor.Theme")
local Ui = require("editor.Ui")
local Gizmo = require("editor.TransformGizmo")
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
    self.selectedLObjects = {}
    self.isDraggingLObject = false
    self.snapSettings = require("editor.SnapSettings").copy()
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
    if self.spriteAssets then self.spriteAssets.level = self.level end

    local halfSize = LOBJECT_SIZE * 0.5

    if self.spriteAssets then
        local previews, sources = {}, {}
        for _, object in ipairs(self.level.lobjects) do
            local preview = self.spriteAssets:preview(object)
            if preview then previews[#previews + 1] = preview; sources[preview] = object end
        end
        local entries = require("core.ComponentOrder").entries(previews, require("core.RenderComponent"))
        local context = {image = function(_, reference) return self.spriteAssets:image(reference) end}
        for index = #entries, 1, -1 do
            local component = entries[index].component
            if component:hitTest(context, worldX, worldY) then return sources[component.owner] end
        end
    end

    for i = #self.level.lobjects, 1, -1 do
        local lobject = self.level.lobjects[i]
        local transform = self.level:getWorldTransform(lobject)
        if self.spriteAssets then
            local preview = self.spriteAssets:preview(lobject)
            if preview and require("core.Renderer").hit(preview, function(reference) return self.spriteAssets:image(reference) end, worldX, worldY) then return lobject end
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

        local axis = not love.keyboard.isDown("lctrl", "rctrl", "lshift", "rshift") and Gizmo.hit(self, x, y)
        if axis then
            self.drag = Gizmo.begin(self, axis, x, y)
            self:beginGroupDrag()
            self.isDraggingLObject = true
            return
        end
        local worldX, worldY = self:screenToWorld(x, y)
        local hitLObject = self:findLObjectAtWorldPosition(worldX, worldY)

        if hitLObject then
            self:selectLObject(hitLObject, love.keyboard.isDown("lctrl", "rctrl"))
            self.isDraggingLObject = false
            if self:isSelected(hitLObject) then self.pointerDrag = {x = x, y = y} end
        else
            -- 빈 공간 클릭은 새 LObject를 만들지 않고 현재 선택만 해제한다.
            local additive = love.keyboard.isDown("lctrl", "rctrl")
            local previous = additive and self:getSelection() or {}
            self:setSelection(previous)
            self.marquee = {x = x, y = y, endX = x, endY = y, previous = previous}
            self.isDraggingLObject = false
        end

        return
    end

    if button == 2 and self.onContextMenu then
        local wx, wy = self:screenToWorld(x, y)
        self.onContextMenu(x, y, self:findLObjectAtWorldPosition(wx, wy))
        return
    end

    if button == PAN_MOUSE_BUTTON then
        self.isPanning = true
    end
end

function SceneView:mousereleased(x, y, button)
    if button == LEFT_MOUSE_BUTTON then
        self.marquee = nil
        self:cancelDrag(false)
    end

    if button == PAN_MOUSE_BUTTON then
        self.isPanning = false
    end
end

function SceneView:cancelDrag(restore)
    if restore and self.drag then
        for object, saved in pairs(self.drag.selection or {[self.drag.object] = {transform = self.drag.initial}}) do
            for field, value in pairs(saved.transform) do object.transform[field] = value end
        end
    end
    self.marquee, self.pointerDrag = nil, nil
    self.drag, self.isDraggingLObject = nil, false
end

function SceneView:setGizmoMode(mode)
    if mode ~= "translate" and mode ~= "rotate" and mode ~= "scale" then return false end
    if self.gizmoMode ~= mode then self:cancelDrag(true); self.gizmoMode = mode end
    return true
end

function SceneView:setSnap(mode, enabled, unit)
    if not self.snapSettings[mode] or type(enabled) ~= "boolean" or not require("editor.SnapSettings").validUnit(unit) then return false, "Snap unit must be a positive finite number" end
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
    if self.pointerDrag and not self.drag and (x - self.pointerDrag.x)^2 + (y - self.pointerDrag.y)^2 >= 36 then
        self.drag = Gizmo.begin(self, "free", self.pointerDrag.x, self.pointerDrag.y)
        self.drag.mode = "translate"; self:beginGroupDrag(); self.isDraggingLObject = true
        dx, dy = x - self.pointerDrag.x, y - self.pointerDrag.y
        self.pointerDrag = nil
    end
    if self.isDraggingLObject and self.drag then
        Gizmo.update(self, self.drag, dx, dy)
        self:applyGroupDrag()
        return
    end

    if self.marquee then
        self.marquee.endX, self.marquee.endY = x, y
        local Box = require("editor.ui.SelectionBox")
        local rect = Box.rect(self.marquee.x, self.marquee.y, x, y)
        local objects = {}; for _, object in ipairs(self.marquee.previous) do objects[#objects + 1] = object end
        for _, object in ipairs(self.level.lobjects) do
            if Box.intersects(rect, self:objectScreenBounds(object)) then
                local exists = false; for _, selected in ipairs(objects) do if selected == object then exists = true end end
                if not exists then objects[#objects + 1] = object end
            end
        end
        self:setSelection(objects)
        return
    end
    if self.isPanning then
        self.cameraX = self.cameraX + dx
        self.cameraY = self.cameraY + dy
    end
end

function SceneView:frameSelected()
    local objects = self:getSelection()
    if #objects < 2 then return self:frameLObject(self.selectedLObject) end
    local minX, minY, maxX, maxY
    for _, object in ipairs(objects) do
        local world = self.level:getWorldTransform(object)
        minX, minY = math.min(minX or world.x, world.x), math.min(minY or world.y, world.y)
        maxX, maxY = math.max(maxX or world.x, world.x), math.max(maxY or world.y, world.y)
    end
    self.cameraX, self.cameraY = -(minX + maxX) * 0.5 * self.zoom, -(minY + maxY) * 0.5 * self.zoom
    return true
end

function SceneView:frameLObject(object)
    if not object or not object.transform then
        return false
    end

    local transform = self.level and self.level:getWorldTransform(object) or object.transform

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

    if key == "a" and controlDown and self.level then self:setSelection(self.level.lobjects); return end
    if key == "d" and controlDown then
        if not self.level or not self.selectedLObject then return end
        -- 단일 루트는 기존 커서 위치 복제를 유지한다. 계층/다중 복제는 상대 배치를 보존한다.
        local selected = self:getSelection()
        local duplicates = self.level:duplicateLObjects(selected)
        if #selected == 1 and #duplicates == 1 and mouseX and mouseY and self:containsPoint(mouseX, mouseY) then
            self.level:setWorldPosition(duplicates[1], self:snapPosition(self:screenToWorld(mouseX, mouseY)))
        end
        self:setSelection(duplicates); self:cancelDrag(false); return
    end
    if key == "delete" then self:deleteSelection() end
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

    if self.spriteAssets then
        local previews = {}
        for _, lobject in ipairs(self.level.lobjects) do
            local preview = self.spriteAssets:preview(lobject)
            if preview then previews[#previews + 1] = preview end
        end
        require("core.Renderer").drawObjects(previews, function(reference) return self.spriteAssets:image(reference) end,
            function(x, y) return self:worldToScreen(x, y) end, self.zoom)
    end
    if self.spriteAssets then
        self:drawCameraBounds()
        for _, selected in ipairs(self:getSelection()) do
            local preview = self.spriteAssets:preview(selected)
            if preview then
                Theme.setColor("objectSelected")
                love.graphics.setLineWidth(2)
                require("core.Renderer").outline(preview, function(reference) return self.spriteAssets:image(reference) end,
                    function(x, y) return self:worldToScreen(x, y) end)
            end
        end
    end
    if self.ping and self.level:findLObject(self.ping.object.authoringId) == self.ping.object then
        local rect = self:objectScreenBounds(self.ping.object)
        Theme.setColor("focus"); love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", rect.x - 4, rect.y - 4, rect.w + 8, rect.h + 8)
    end
    Gizmo.draw(self)
end
function SceneView:getCameraBounds(camera)
    local width, height = camera:getViewSize()
    local transform, points = camera:getViewTransform(), {}
    for _, corner in ipairs({{-width / 2, -height / 2}, {width / 2, -height / 2}, {width / 2, height / 2}, {-width / 2, height / 2}}) do
        local x, y = require("core.Transform").point(transform, corner[1], corner[2])
        points[#points + 1], points[#points + 2] = self:worldToScreen(x, y)
    end
    return points
end
function SceneView:drawCameraBounds()
    local Camera = require("core.CameraComponent")
    for _, object in ipairs(self.level.lobjects) do
        local preview = self.spriteAssets:preview(object)
        if preview then
            for _, name in ipairs(preview:getComponentOrder()) do
                local component = preview.components[name]
                if component:isA(Camera) then
                    local ok, points = pcall(self.getCameraBounds, self, component)
                    if ok then
                        Theme.setColor(self:isSelected(object) and "objectSelected" or "textMuted")
                        love.graphics.setLineWidth(self:isSelected(object) and 2 or 1)
                        love.graphics.polygon("line", points)
                    else self.spriteAssets.error = tostring(points) end
                end
            end
        end
    end
end

function SceneView:drawMouseWorldPosition()
    local mouseX, mouseY = love.mouse.getPosition()
    if not self:containsPoint(mouseX, mouseY) then return end
    local viewportX, viewportY = self:getViewport()
    local worldX, worldY = self:screenToWorld(mouseX, mouseY)
    local title = string.format("Scene View  %.2fx", self.zoom)
    Theme.setColor("textMuted")
    love.graphics.print(string.format("(%.1f, %.1f)", worldX, worldY), viewportX + Ui.METRICS.titlePaddingX + require("editor.Fonts").get(Ui.METRICS.titleFontSize):getWidth(title) + 16,
        viewportY + Ui.METRICS.titlePaddingY)
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

    require("editor.Ui").panel(viewportX, viewportY, width, height, "viewportBackground")
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
    if self.spriteAssets then self.spriteAssets.level = self.level end
    self:drawLObjects()
    if self.marquee then require("editor.ui.SelectionBox").draw(require("editor.ui.SelectionBox").rect(self.marquee.x, self.marquee.y, self.marquee.endX, self.marquee.endY)) end

    Theme.setColor("text")
    Ui.panelHeading(
        string.format("Scene View  %.2fx", self.zoom),
        viewportX,
        viewportY,
        width
    )
    self:drawMouseWorldPosition()
    love.graphics.pop()
end

function SceneView:getSelection()
    if not self.selectedLObject then return {} end
    local found = false
    for _, object in ipairs(self.selectedLObjects) do if object == self.selectedLObject then found = true end end
    if not found then self.selectedLObjects = {self.selectedLObject} end
    return self.selectedLObjects
end
function SceneView:setSelection(objects)
    self.selectedLObjects = {}; for _, object in ipairs(objects) do self.selectedLObjects[#self.selectedLObjects + 1] = object end
    self.selectedLObject = self.selectedLObjects[#self.selectedLObjects]
end
function SceneView:isSelected(object)
    for _, selected in ipairs(self:getSelection()) do if selected == object then return true end end
    return false
end
function SceneView:selectLObject(object, toggle)
    if not toggle then
        if not self:isSelected(object) then self:setSelection(object and {object} or {}) end
        return
    end
    local objects = {}; local found = false
    for _, selected in ipairs(self:getSelection()) do if selected == object then found = true else objects[#objects + 1] = selected end end
    if object and not found then objects[#objects + 1] = object end
    self:setSelection(objects)
end
function SceneView:objectScreenBounds(object)
    local world = self.level:getWorldTransform(object)
    local x, y = self:worldToScreen(world.x, world.y)
    local bounds = {x = x - 8, y = y - 8, w = 16, h = 16}
    if self.spriteAssets then
        local preview = self.spriteAssets:preview(object)
        if preview then
            local minX, minY, maxX, maxY
            require("core.Renderer").outline(preview, function(reference) return self.spriteAssets:image(reference) end, function(px, py)
                local sx, sy = self:worldToScreen(px, py)
                minX, minY = math.min(minX or sx, sx), math.min(minY or sy, sy)
                maxX, maxY = math.max(maxX or sx, sx), math.max(maxY or sy, sy)
                return sx, sy
            end, true)
            if minX then bounds = {x = minX, y = minY, w = maxX - minX, h = maxY - minY} end
        end
    end
    return bounds
end
function SceneView:deleteSelection()
    if not self.level then return end
    self.level:removeLObjects(self:getSelection()); self:setSelection({}); self:cancelDrag(false)
end
function SceneView:duplicateSelection()
    self:setSelection(self.level:duplicateLObjects(self:getSelection()))
end
function SceneView:beginGroupDrag()
    local drag = self.drag; drag.selection = {}
    for _, object in ipairs(self.level:selectionRoots(self:getSelection())) do
        local world = self.level:getWorldTransform(object)
        drag.selection[object] = {transform = assert(require("core.Transform").copy(object.transform)), x = world.x, y = world.y}
    end
    drag.primaryLocal = assert(require("core.Transform").copy(drag.object.transform))
    local world = self.level:getWorldTransform(drag.object)
    drag.initial.x, drag.initial.y = world.x, world.y
end
function SceneView:applyGroupDrag()
    local drag, Transform = self.drag, require("core.Transform")
    local result = assert(Transform.copy(drag.object.transform))
    local dx, dy = result.x - drag.initial.x, result.y - drag.initial.y
    if drag.axis == "x" then dy = 0 elseif drag.axis == "y" then dx = 0 end
    local primary = drag.primaryLocal
    -- 선택된 조상의 이동에 자손이 다시 움직이지 않도록 최상위 선택만 변경한다.
    for field, value in pairs(primary) do drag.object.transform[field] = value end
    local positions = {}
    if drag.mode == "translate" then
        for object, saved in pairs(drag.selection) do
            local x, y = saved.x + dx, saved.y + dy
            local parent = self.level:getParent(object)
            if parent then x, y = Transform.inversePoint(self.level:getWorldTransform(parent), x, y) end
            if not x then return end
            positions[object] = {x, y}
        end
    end
    for object, saved in pairs(drag.selection) do
        local t = object.transform
        if drag.mode == "translate" then t.x, t.y = unpack(positions[object])
        elseif drag.mode == "rotate" then
            for _, field in ipairs({"rotation", "rotationX", "rotationY"}) do t[field] = Transform.normalizeRotation(saved.transform[field] + result[field] - primary[field]) end
        else
            t.scaleX, t.scaleY = saved.transform.scaleX * result.scaleX / primary.scaleX, saved.transform.scaleY * result.scaleY / primary.scaleY
        end
    end
end

return SceneView
