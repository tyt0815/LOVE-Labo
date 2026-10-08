local Theme = require("editor.theme")
local UI = require("editor.ui")
local Transform = require("core.transform")
local Gizmo = {}
local RADIUS, LENGTH = 60, 70

-- 핸들의 화면 크기는 고정한다. 스케일 축만 객체의 로컬 축을 따른다.
function Gizmo.handles(view)
    if not view.selectedLObject then return nil end
    local transform = view.selectedLObject.transform
    local x, y = view:worldToScreen(transform.x, transform.y)
    local angle = view.gizmoMode == "scale" and math.rad(transform.rotation or 0) or 0
    local cosine, sine = math.cos(angle), math.sin(angle)
    return {x = x, y = y, ux = cosine, uy = sine, vx = sine, vy = -cosine,
        free = {x = x - 8, y = y - 8, w = 16, h = 16}, radius = RADIUS}
end

local function onAxis(handles, x, y, ux, uy)
    local dx, dy = x - handles.x, y - handles.y
    local along, across = dx * ux + dy * uy, math.abs(-dx * uy + dy * ux)
    return along >= 12 and along <= LENGTH + 7 and across <= 7
end

function Gizmo.hit(view, x, y)
    local handles = Gizmo.handles(view)
    if not handles then return nil end
    local dx, dy = x - handles.x, y - handles.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if view.gizmoMode == "rotate" then
        if math.abs(distance - RADIUS) <= 7 then return "z" end
        return nil
    end
    if view.gizmoMode == "scale" then
        if UI.contains(x, y, handles.free) then return "free" end
    elseif distance <= 9 then return "free" end
    if onAxis(handles, x, y, handles.ux, handles.uy) then return "x" end
    if onAxis(handles, x, y, handles.vx, handles.vy) then return "y" end
end

function Gizmo.begin(view, axis, x, y)
    local initial = assert(Transform.copy(view.selectedLObject.transform))
    local handles = Gizmo.handles(view)
    return {axis = axis, mode = view.gizmoMode, object = view.selectedLObject, initial = initial,
        dx = 0, dy = 0, zoom = view.zoom, handles = handles,
        pointerX = x, pointerY = y, angle = math.atan2(y - handles.y, x - handles.x), rotationDelta = 0}
end

function Gizmo.update(view, drag, dx, dy)
    drag.dx, drag.dy = drag.dx + dx, drag.dy + dy
    local initial, transform = drag.initial, drag.object.transform
    if drag.mode == "rotate" then
        drag.pointerX, drag.pointerY = drag.pointerX + dx, drag.pointerY + dy
        local rx, ry = drag.pointerX - drag.handles.x, drag.pointerY - drag.handles.y
        if rx * rx + ry * ry < 1 then return end
        local angle = math.atan2(ry, rx)
        -- ±180도 경계에서도 드래그가 역방향으로 튀지 않게 차이를 감싼다.
        local delta = (angle - drag.angle + math.pi) % (2 * math.pi) - math.pi
        drag.rotationDelta, drag.angle = drag.rotationDelta + delta, angle
        transform.rotation = initial.rotation + math.deg(drag.rotationDelta)
    elseif drag.mode == "scale" then
        local amount
        if drag.axis == "x" then amount = drag.dx * drag.handles.ux + drag.dy * drag.handles.uy
        elseif drag.axis == "y" then amount = drag.dx * drag.handles.vx + drag.dy * drag.handles.vy
        else amount = drag.dx - drag.dy end
        local factor = math.exp(math.max(-20, math.min(20, amount / 100)))
        if drag.axis == "free" then
            factor = math.max(factor, 0.01 / initial.scaleX, 0.01 / initial.scaleY)
            transform.scaleX, transform.scaleY = initial.scaleX * factor, initial.scaleY * factor
        elseif drag.axis == "x" then transform.scaleX = math.max(0.01, initial.scaleX * factor)
        else transform.scaleY = math.max(0.01, initial.scaleY * factor) end
    else
        if drag.axis ~= "y" then transform.x = initial.x + view:snapValue(drag.dx / drag.zoom) end
        if drag.axis ~= "x" then transform.y = initial.y + view:snapValue(drag.dy / drag.zoom) end
    end
end

local function drawAxis(view, handles, axis, ux, uy, hovered)
    local active = view.drag and view.drag.axis
    Theme.setColor(axis == "x" and "axisX" or "axisY")
    love.graphics.setLineWidth((active == axis or hovered == axis or active == "free" and view.gizmoMode == "scale") and 4 or 3)
    local x, y = handles.x, handles.y
    love.graphics.line(x + ux * 12, y + uy * 12, x + ux * 60, y + uy * 60)
    local endX, endY = x + ux * LENGTH, y + uy * LENGTH
    if view.gizmoMode == "scale" then
        love.graphics.rectangle("fill", endX - 6, endY - 6, 12, 12)
    else
        love.graphics.polygon("fill", endX, endY, x + ux * 58 - uy * 6, y + uy * 58 + ux * 6,
            x + ux * 58 + uy * 6, y + uy * 58 - ux * 6)
    end
end

function Gizmo.draw(view)
    local handles = Gizmo.handles(view)
    if not handles then return end
    local x, y = handles.x, handles.y
    local mx, my = love.mouse.getPosition()
    local hovered = Gizmo.hit(view, mx, my)
    if view.gizmoMode == "rotate" then
        Theme.setColor("axisZ")
        love.graphics.setLineWidth((hovered == "z" or view.drag) and 4 or 3)
        love.graphics.circle("line", x, y, RADIUS)
        local angle = math.rad(view.selectedLObject.transform.rotation or 0)
        love.graphics.line(x, y, x + math.cos(angle) * RADIUS, y + math.sin(angle) * RADIUS)
        if view.drag then UI.text(string.format("Z: %.1f°", view.selectedLObject.transform.rotation), x + RADIUS + 10, y - 8) end
        UI.hint({x = x - RADIUS - 7, y = y - RADIUS - 7, w = 2 * RADIUS + 14, h = 2 * RADIUS + 14}, "Drag the ring: rotate around Z. Esc: cancel.")
        return
    end
    drawAxis(view, handles, "x", handles.ux, handles.uy, hovered)
    drawAxis(view, handles, "y", handles.vx, handles.vy, hovered)
    love.graphics.setColor(1, 1, 1, 1)
    if view.gizmoMode == "scale" then
        love.graphics.rectangle("fill", handles.free.x, handles.free.y, 16, 16)
        Theme.setColor("border")
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", handles.free.x, handles.free.y, 16, 16)
    else
        love.graphics.circle("fill", x, y, 7)
        Theme.setColor("border")
        love.graphics.setLineWidth(1)
        love.graphics.circle("line", x, y, 7)
    end
    UI.hint(handles.free, view.gizmoMode == "scale" and "Drag right/up: scale both axes up. Left/down: scale down." or "Drag the white circle: move freely. Esc: cancel.")
end
return Gizmo
