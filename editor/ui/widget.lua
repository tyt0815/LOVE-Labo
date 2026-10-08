local Widget = {}
Widget.__index = Widget

function Widget.new(handlers)
    return setmetatable({ x = 0, y = 0, width = 0, height = 0,
        visible = true, enabled = true, handlers = handlers or {} }, Widget)
end

function Widget:setBounds(x, y, width, height)
    self.x, self.y, self.width, self.height = x, y, math.max(0, width), math.max(0, height)
    if self.handlers.bounds then self.handlers.bounds(self, x, y, self.width, self.height) end
end

function Widget:containsPoint(x, y)
    return x >= self.x and x < self.x + self.width and y >= self.y and y < self.y + self.height
end

function Widget:hitTest(x, y)
    if not self.visible or not self.enabled or not self:containsPoint(x, y) then return nil end
    if self.handlers.hitTest and not self.handlers.hitTest(self, x, y) then return nil end
    return self
end

function Widget:draw()
    if self.visible and self.handlers.draw then self.handlers.draw(self) end
end

function Widget:dispatch(event, ...)
    if not self.visible or not self.enabled then return false end
    local handler = self.handlers[event]
    if handler then return handler(self, ...) end
    return false
end

return Widget
