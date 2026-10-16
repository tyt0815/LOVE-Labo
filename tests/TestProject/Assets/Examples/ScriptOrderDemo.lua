local Demo = {properties = {
    trace = {type = "string", default = "", group = "Result"},
    caption = {type = "string", default = "Order demo"},
    red = {type = "number", default = 0.2, group = "Color"},
    green = {type = "number", default = 0.5, group = "Color"},
    blue = {type = "number", default = 0.8, group = "Color"}
}}
function Demo:update(dt)
    local world = self:getWorld()
    -- 프레임마다 실행 흔적을 새로 모아 순서를 확인한다.
    if world.orderDemoTime ~= world.elapsedTime then
        world.orderDemoTime, world.orderDemoTrace = world.elapsedTime, ""
    end
    world.orderDemoTrace = world.orderDemoTrace .. (world.orderDemoTrace == "" and "" or " -> ") .. self.caption
    self.trace = world.orderDemoTrace
    world.debug:screenLog("Update: " .. self.trace, {key = "order-demo"})
end
function Demo:draw()
    love.graphics.setColor(self.red, self.green, self.blue, 1)
    love.graphics.rectangle("fill", -170, -70, 340, 140)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(self.caption .. "\nUpdate order: " .. self.updateOrder .. "\nDraw order: " .. self.drawOrder, -160, -25, 320, "center")
end
function Demo:getLocalBounds() return -170, -70, 340, 140 end
return Demo
