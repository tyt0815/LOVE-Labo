local Engine = require("Engine")
local Hud = {properties = {drawOrder = {type = "number", default = 100}}}
function Hud:configure() Engine.Bounds.bind(self, function(context) return Engine.Bounds.of(self.owner, context) end) end
function Hud:load(world)
    local actor = self.owner.parent
    while actor and not actor:getScriptByName("traveller") do actor = actor.parent end
    self.actor = assert(actor):getScriptByName("traveller")
    Engine.Input.registerRegion(world, {owner = self, hitTest = function(context, x, y) return self:hitTest(context, x, y) end,
        onDown = function() self.actor.gold = self.actor.gold + 1; return true end})
end
function Hud:draw(context)
    local x, y, w, h = self:getBounds(context)
    love.graphics.setColor(0.12, 0.32, 0.48, 1); love.graphics.rectangle("fill", x, y, w, h, 5, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("CLICK: +1 GOLD | HP " .. self.actor.hp .. " | Gold " .. self.actor.gold .. " | Keys " .. self.actor.keys,
        x + 8, y + 16, w - 16, "center")
end
return Hud
