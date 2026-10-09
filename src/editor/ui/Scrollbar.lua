local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Scrollbar = {}
Scrollbar.__index = Scrollbar
Scrollbar.WIDTH = 12
function Scrollbar.new(getValue, setValue)
    return setmetatable({getValue = getValue, setValue = setValue}, Scrollbar)
end
function Scrollbar:layout(rect, content, viewport)
    self.rect, self.viewport = rect, math.max(0, viewport)
    self.maximum = math.max(0, content - viewport)
    self.visible = self.maximum > 0 and rect.h > 0
    self.thumbHeight = math.min(rect.h, math.max(22, rect.h * viewport / math.max(1, content)))
    if not self.visible then self.drag = nil end
end
function Scrollbar:thumb()
    local rect = self.rect
    local value = math.max(0, math.min(self.maximum, self.getValue()))
    return {x = rect.x + 2, y = rect.y + (rect.h - self.thumbHeight) * value / math.max(1, self.maximum), w = rect.w - 4, h = self.thumbHeight}
end
function Scrollbar:moveTo(y)
    local travel = self.rect.h - self.thumbHeight
    local value = travel > 0 and (y - self.rect.y - self.drag) / travel * self.maximum or 0
    self.setValue(math.max(0, math.min(self.maximum, value)))
end
function Scrollbar:dispatch(event, ...)
    if event == "cancel" or event == "dismiss" then self.drag = nil; return false end
    if event == "mousepressed" then
        local x, y, button = ...
        if button ~= 1 or not self.visible or not Ui.contains(x, y, self.rect) then return false end
        local thumb = self:thumb()
        self.drag = Ui.contains(x, y, thumb) and y - thumb.y or self.thumbHeight / 2
        self:moveTo(y)
        return true, true
    elseif event == "mousemoved" and self.drag then
        local _, y = ...; self:moveTo(y); return true
    elseif event == "mousereleased" and self.drag then
        local _, _, button = ...
        if button == 1 or button == nil then self.drag = nil end
        return true
    end
    return false
end
function Scrollbar:draw()
    if not self.visible then return end
    love.graphics.push("all")
    Theme.setColor("border")
    love.graphics.rectangle("fill", self.rect.x + self.rect.w / 2 - 0.5, self.rect.y, 1, self.rect.h)
    local thumb = self:thumb()
    local x, y = love.mouse.getPosition()
    Theme.setColor(self.drag and "focus" or Ui.contains(x, y, self.rect) and "text" or "textMuted")
    love.graphics.rectangle("fill", thumb.x, thumb.y, thumb.w, thumb.h, 3, 3)
    Ui.hint(self.rect, "Drag to scroll.")
    love.graphics.pop()
end
return Scrollbar
