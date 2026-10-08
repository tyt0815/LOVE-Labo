local Root = {}
Root.__index = Root

function Root.new(canvas)
    return setmetatable({ canvas = canvas, focused = nil, captured = nil,
        captureButton = nil, popup = nil }, Root)
end

function Root:setPopup(widget)
    if self.popup and self.popup ~= widget then self.popup:dispatch("dismiss") end
    self.popup = widget
end

function Root:dismissPopup()
    local popup = self.popup
    self.popup = nil
    if popup then popup:dispatch("dismiss") end
end

function Root:draw()
    self.canvas:draw()
    if self.popup then
        love.graphics.push("all")
        love.graphics.setScissor()
        self.popup:draw()
        love.graphics.pop()
    end
end

function Root:dispatchTo(target, event, ...)
    while target do
        local handled, capture = target:dispatch(event, ...)
        if handled then return true, capture, target end
        target = target.parent
    end
    return false
end

function Root:mousepressed(x, y, button, presses)
    if self.popup then
        local target = self.popup:hitTest(x, y)
        if target then return self:dispatchTo(target, "mousepressed", x, y, button, presses) end
        -- 메뉴 바깥 클릭은 닫기에만 사용하여 뒤쪽 객체를 실수로 조작하지 않는다.
        self:dismissPopup()
        return true
    end
    local target = self.canvas:hitTest(x, y)
    if self.beforeMousepressed then self.beforeMousepressed(target, x, y, button) end
    local handled, capture, consumer = self:dispatchTo(target, "mousepressed", x, y, button, presses)
    if handled then
        if consumer.focusable ~= false then self.focused = consumer end
        if capture then self.captured, self.captureButton = consumer, button end
    end
    return handled
end

function Root:mousemoved(x, y, dx, dy)
    local target = self.captured or (self.popup and self.popup:hitTest(x, y)) or self.canvas:hitTest(x, y)
    return self:dispatchTo(target, "mousemoved", x, y, dx, dy)
end

function Root:mousereleased(x, y, button)
    local target = self.captured or self.canvas:hitTest(x, y)
    local handled = self:dispatchTo(target, "mousereleased", x, y, button)
    if button == self.captureButton then self.captured, self.captureButton = nil, nil end
    return handled
end

function Root:wheelmoved(x, y, amount)
    if self.popup then return true end
    return self:dispatchTo(self.canvas:hitTest(x, y), "wheelmoved", x, y, amount)
end

function Root:keypressed(key)
    if self.popup then
        if key == "escape" then self:dismissPopup()
        else self:dispatchTo(self.popup, "keypressed", key) end
        return true
    end
    return self:dispatchTo(self.focused, "keypressed", key)
end

function Root:textinput(text)
    if self.popup then return true end
    return self:dispatchTo(self.focused, "textinput", text)
end

return Root
