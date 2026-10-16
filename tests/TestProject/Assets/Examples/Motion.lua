local Motion = {properties = {
    speed = {type = "number", default = 35, group = "Movement"},
    title = {type = "string", default = "Moving object"},
    target = {type = "object", default = false}, sibling = {type = "script", default = false}
}}
function Motion.load(self)
    self.originY, self.elapsed = self.owner.transform.y, 0
    local x, y = self:getWorldPosition()
    self.owner.world.debug:log(self.title .. " load at " .. x .. ", " .. y)
end
function Motion.update(self, dt)
    self.elapsed = self.elapsed + dt
    if self.enabled then
        self.owner.transform.y = self.originY + math.sin(self.elapsed) * self.speed
        self.owner.transform.rotation = (self.owner.transform.rotation + dt * 20) % 360
    end
end
return Motion
