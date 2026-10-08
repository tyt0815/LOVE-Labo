local Root = {}
Root.__index = Root

function Root.new(canvas)
    return setmetatable({ canvas = canvas, focused = nil, captured = nil,
        captureButton = nil, popup = nil }, Root)
end

function Root:setPopup(widget)
    if self.captured then self.captured:dispatch("cancel"); self.captured, self.captureButton = nil, nil end
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
    if self.captured then self.captured:dispatch("drawOverlay") end
    if self.popup then
        love.graphics.push("all")
        love.graphics.setScissor()
        self.popup:draw()
        love.graphics.pop()
    end
end

function Root:update(dt)
    if type(dt) ~= "number" or dt < 0 or dt ~= dt or dt == math.huge then return end
    self.canvas:update(dt)
    if self.popup then self.popup:update(dt) end
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
        if button == 2 and self.popup.reopenOnRightClick then
            -- 컨텍스트 메뉴는 새 우클릭 위치의 위젯이 바로 다음 메뉴를 열게 한다.
            self:dismissPopup()
        else
            local target = self.popup:hitTest(x, y)
            if target then return self:dispatchTo(target, "mousepressed", x, y, button, presses) end
            -- 일반 바깥 클릭은 닫기에만 사용하여 뒤쪽 객체를 실수로 조작하지 않는다.
            self:dismissPopup()
            return true
        end
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
    if self.popup and not self.captured then
        self:dispatchTo(self.popup:hitTest(x, y), "mousemoved", x, y, dx, dy)
        return true
    end
    local target = self.captured or (self.popup and self.popup:hitTest(x, y)) or self.canvas:hitTest(x, y)
    return self:dispatchTo(target, "mousemoved", x, y, dx, dy)
end

function Root:mousereleased(x, y, button)
    if self.popup and not self.captured then
        self:dispatchTo(self.popup:hitTest(x, y), "mousereleased", x, y, button)
        return true
    end
    local target = self.captured or self.canvas:hitTest(x, y)
    local handled = self:dispatchTo(target, "mousereleased", x, y, button)
    if button == self.captureButton then self.captured, self.captureButton = nil, nil end
    return handled
end

function Root:wheelmoved(x, y, amount)
    if self.popup then self:dispatchTo(self.popup, "wheelmoved", x, y, amount); return true end
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
    if self.popup then self:dispatchTo(self.popup, "textinput", text); return true end
    return self:dispatchTo(self.focused, "textinput", text)
end

return Root
