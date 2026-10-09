local Theme = require("editor.Theme")
local SelectionBox = {}
function SelectionBox.rect(x1, y1, x2, y2)
    return {x = math.min(x1, x2), y = math.min(y1, y2), w = math.abs(x2 - x1), h = math.abs(y2 - y1)}
end
function SelectionBox.intersects(a, b)
    return a.x <= b.x + b.w and a.x + a.w >= b.x and a.y <= b.y + b.h and a.y + a.h >= b.y
end
function SelectionBox.draw(rect)
    love.graphics.push("all")
    local r, g, b = unpack(Theme.color("focus"))
    love.graphics.setColor(r, g, b, 0.16); love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setColor(r, g, b, 0.9); love.graphics.setLineWidth(1); love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
    love.graphics.pop()
end
return SelectionBox
