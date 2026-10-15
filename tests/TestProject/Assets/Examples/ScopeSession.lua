local Session = {properties = {
    visits = {type = "number", default = 0, group = "Session"},
    frames = {type = "number", default = 0, group = "Session"}
}}
function Session:load() self.token = love.math.random(1000, 9999) end
function Session:update(dt) self.frames = self.frames + 1 end
function Session:drawScreen(context)
    local world = self:getWorld()
    if not world or not world:getScriptByName("scopeLevel") then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Project token " .. self.token .. " | visits " .. self.visits .. " | frames " .. self.frames, 20, 20)
end
return Session
