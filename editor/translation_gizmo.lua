local Theme = require("editor.theme")
local UI = require("editor.ui")
local Gizmo = {}

-- 화면 픽셀 크기를 고정하여 줌에 관계없이 핸들을 잡을 수 있게 한다.
function Gizmo.handles(view)
    if not view.selectedLObject then return nil end
    local transform = view.selectedLObject.transform
    local x, y = view:worldToScreen(transform.x, transform.y)
    return {x = x, y = y,
        free = {x = x + 6, y = y - 22, w = 16, h = 16},
        horizontal = {x = x, y = y - 7, w = 72, h = 14},
        vertical = {x = x - 7, y = y - 72, w = 14, h = 72}}
end

function Gizmo.hit(view, x, y)
    local handles = Gizmo.handles(view)
    if not handles then return nil end
    if UI.contains(x, y, handles.free) then return "free" end
    if UI.contains(x, y, handles.horizontal) then return "x" end
    if UI.contains(x, y, handles.vertical) then return "y" end
end

function Gizmo.draw(view)
    local handles = Gizmo.handles(view)
    if not handles then return end
    local x, y = handles.x, handles.y
    local active = view.drag and view.drag.axis
    local mx, my = love.mouse.getPosition()
    local hovered = Gizmo.hit(view, mx, my)
    love.graphics.setLineWidth(3)
    Theme.setColor((active == "x" or hovered == "x") and "objectSelected" or "axisX")
    love.graphics.line(x, y, x + 60, y)
    love.graphics.polygon("fill", x + 70, y, x + 58, y - 6, x + 58, y + 6)
    Theme.setColor((active == "y" or hovered == "y") and "objectSelected" or "axisY")
    love.graphics.line(x, y, x, y - 60)
    love.graphics.polygon("fill", x, y - 70, x - 6, y - 58, x + 6, y - 58)
    Theme.setColor((active == "free" or hovered == "free") and "objectSelected" or "origin")
    local square = handles.free
    love.graphics.rectangle("fill", square.x, square.y, square.w, square.h)
    Theme.setColor("border")
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", square.x, square.y, square.w, square.h)
    UI.hint(handles.horizontal, "Drag: move along X.")
    UI.hint(handles.vertical, "Drag: move along Y.")
    UI.hint(handles.free, "Drag: move freely. Esc: cancel.")
end
return Gizmo
