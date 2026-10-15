local Bounds = require("Engine").Bounds
local Actor = {properties = {speed = {type = "number", default = 2, group = "Motion"}}}
Actor.getBounds, Actor.hitTest = Bounds.getBounds, Bounds.hitTest
function Actor:load() self.elapsed, self.priority = 0, 10 end
-- update는 선언하지 않는다. Level Script가 이 일반 메서드를 직접 호출한다.
function Actor:fixedUpdate(dt)
    self.elapsed = self.elapsed + dt
    self.owner.transform.x = math.sin(self.elapsed * self.speed) * 180
end
function Actor:draw(context)
    love.graphics.setColor(0.15, 0.8, 0.9, 1)
    love.graphics.circle("fill", 0, 0, 20)
end
function Actor:drawScreen(context)
    love.graphics.setColor(0.15, 0.8, 0.9, 1)
    love.graphics.print("Object drawScreen: fixed on screen while the circle moves", 20, context.viewport.height - 35)
end
function Actor:getLocalBounds() return -20, -20, 40, 40 end
function Actor:drawEditor(context) context:bounds(self) end
return Actor
