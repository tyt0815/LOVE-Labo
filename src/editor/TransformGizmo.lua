local Theme = require("editor.Theme")
local Ui = require("editor.Ui")
local Transform = require("core.Transform")
local Gizmo = {}
local RADIUS, LENGTH = 60, 70

-- 핸들의 화면 크기는 고정한다. 스케일 축만 객체의 로컬 축을 따른다.
function Gizmo.handles(view)
    if not view.selectedLObject then return nil end
    local transform = view.selectedLObject.transform
    local x, y = view:worldToScreen(transform.x, transform.y)
    local angle = view.gizmoMode == "scale" and math.rad(transform.rotation or 0) or 0
    local cosine, sine = math.cos(angle), math.sin(angle)
    local ux, uy, vx, vy = cosine, sine, sine, -cosine
    if view.gizmoMode == "scale" then
        local a, b, c, d = Transform.basis(transform)
        local lx, ly = math.sqrt(a * a + b * b), math.sqrt(c * c + d * d)
        if lx > 1e-8 then ux, uy = a / lx, b / lx end
        if ly > 1e-8 then vx, vy = -c / ly, -d / ly end
    end
    return {x = x, y = y, ux = ux, uy = uy, vx = vx, vy = vy,
        free = {x = x - 8, y = y - 8, w = 16, h = 16}, radius = RADIUS}
end

local function onAxis(handles, x, y, ux, uy)
    local dx, dy = x - handles.x, y - handles.y
    local along, across = dx * ux + dy * uy, math.abs(-dx * uy + dy * ux)
    return along >= 0 and along <= LENGTH + 7 and across <= 7
end

function Gizmo.hit(view, x, y)
    local handles = Gizmo.handles(view)
    if not handles then return nil end
    local dx, dy = x - handles.x, y - handles.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if view.gizmoMode == "rotate" then
        if distance <= 9 then return nil end
        local active = view.drag and view.drag.mode == "rotate" and view.drag.axis
        -- 위쪽은 X 회전, 오른쪽은 Y 회전이다. 호 끝점은 선 핸들을 우선한다.
        if (not active or active == "x") and math.abs(dx) <= 7 and dy <= (active and RADIUS + 7 or -9) and dy >= -RADIUS - 7 then return "x" end
        if (not active or active == "y") and math.abs(dy) <= 7 and dx >= (active and -RADIUS - 7 or 9) and dx <= RADIUS + 7 then return "y" end
        if (not active or active == "z") and math.abs(distance - RADIUS) <= 7
            and (active == "z" or dx >= 0 and dy <= 0) then return "z" end
        return nil
    end
    if view.gizmoMode == "scale" then
        if Ui.contains(x, y, handles.free) then return "free" end
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
        if drag.axis == "x" or drag.axis == "y" then
            local field = drag.axis == "x" and "rotationX" or "rotationY"
            -- 화면 1px당 1도. 줌과 무관한 감도로 시작 각도에 변화량 스냅을 적용한다.
            local amount = drag.axis == "x" and -drag.dy or drag.dx
            transform[field] = Transform.normalizeRotation(initial[field] + view:snapValue(amount, "rotate"))
            return
        end
        drag.pointerX, drag.pointerY = drag.pointerX + dx, drag.pointerY + dy
        local rx, ry = drag.pointerX - drag.handles.x, drag.pointerY - drag.handles.y
        if rx * rx + ry * ry < 1 then return end
        local angle = math.atan2(ry, rx)
        -- ±180도 경계에서도 드래그가 역방향으로 튀지 않게 차이를 감싼다.
        local delta = (angle - drag.angle + math.pi) % (2 * math.pi) - math.pi
        drag.rotationDelta, drag.angle = drag.rotationDelta + delta, angle
        transform.rotation = Transform.normalizeRotation(initial.rotation + view:snapValue(math.deg(drag.rotationDelta), "rotate"))
    elseif drag.mode == "scale" then
        local amount
        if drag.axis == "x" then amount = drag.dx * drag.handles.ux + drag.dy * drag.handles.uy
        elseif drag.axis == "y" then amount = drag.dx * drag.handles.vx + drag.dy * drag.handles.vy
        else amount = drag.dx - drag.dy end
        local factor = math.exp(math.max(-20, math.min(20, amount / 100)))
        if drag.axis == "free" then
            factor = 1 + view:snapValue(initial.scaleX * (factor - 1), "scale") / initial.scaleX
            factor = math.max(factor, 0.01 / initial.scaleX, 0.01 / initial.scaleY)
            transform.scaleX, transform.scaleY = initial.scaleX * factor, initial.scaleY * factor
        elseif drag.axis == "x" then transform.scaleX = math.max(0.01, initial.scaleX + view:snapValue(initial.scaleX * (factor - 1), "scale"))
        else transform.scaleY = math.max(0.01, initial.scaleY + view:snapValue(initial.scaleY * (factor - 1), "scale")) end
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
    love.graphics.line(x, y, x + ux * 60, y + uy * 60)
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
        local active = view.drag and view.drag.mode == "rotate" and view.drag.axis
        if not active or active == "x" then
            Theme.setColor("axisX")
            love.graphics.setLineWidth((active == "x" or hovered == "x") and 4 or 3)
            love.graphics.line(x, active == "x" and y + RADIUS or y, x, y - RADIUS)
        end
        if not active or active == "y" then
            Theme.setColor("axisY")
            love.graphics.setLineWidth((active == "y" or hovered == "y") and 4 or 3)
            love.graphics.line(active == "y" and x - RADIUS or x, y, x + RADIUS, y)
        end
        if not active or active == "z" then
            Theme.setColor("axisZ")
            love.graphics.setLineWidth((active == "z" or hovered == "z") and 4 or 3)
            if active == "z" then
                love.graphics.circle("line", x, y, RADIUS)
                local angle = math.rad(view.selectedLObject.transform.rotation or 0)
                love.graphics.line(x, y, x + math.cos(angle) * RADIUS, y + math.sin(angle) * RADIUS)
            else
                local points = {}
                for i = 0, 24 do
                    local angle = -math.pi / 2 + i * math.pi / 48
                    points[#points + 1], points[#points + 2] = x + math.cos(angle) * RADIUS, y + math.sin(angle) * RADIUS
                end
                love.graphics.line(points)
            end
        end
        if active then
            local field = active == "z" and "rotation" or "rotation" .. active:upper()
            Ui.text(string.format("%s: %.1f°", active:upper(), view.selectedLObject.transform[field]), x + RADIUS + 10, y - 8)
        end
        Ui.hint({x = x - RADIUS - 7, y = y - RADIUS - 7, w = 2 * RADIUS + 14, h = 2 * RADIUS + 14},
            "Vertical: rotate X. Horizontal: rotate Y. Arc: rotate Z. Esc: cancel.")
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
    Ui.hint(handles.free, view.gizmoMode == "scale" and "Drag right/up: scale both axes up. Left/down: scale down." or "Drag the white circle: move freely. Esc: cancel.")
end
return Gizmo
