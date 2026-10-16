local Engine = require("Engine")
local Traveller = {properties = {hp = {type = "number", default = 100}, gold = {type = "number", default = 0},
    keys = {type = "number", default = 0}, visits = {type = "number", default = 0}, token = {type = "number", default = 0}}}
function Traveller:load(world)
    self.currentWorld = world
    self.token = love.math.random(100000, 999999)
    self.camera = self.owner.children[1]:getScriptByName("camera")
    self.view = Engine.Rendering.createView(world, {owner = self, projection = function() return self.camera:getProjection() end})
end
function Traveller:worldChanged(previous, current)
    self.currentWorld = current
    self.visits = self.visits + 1
end
function Traveller:unload() self.view:release() end
function Traveller:update(dt)
    local t = self.owner.transform
    if love.keyboard.isDown("a", "left") then t.x = t.x - 180 * dt end
    if love.keyboard.isDown("d", "right") then t.x = t.x + 180 * dt end
end
function Traveller:draw()
    love.graphics.setColor(1, 0.55, 0.2, 1); love.graphics.rectangle("fill", -22, -32, 44, 64, 5, 5)
end
return Traveller
