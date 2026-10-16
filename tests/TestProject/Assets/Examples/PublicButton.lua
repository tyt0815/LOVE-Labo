local Engine = require("Engine")
local Button = {properties = {
    caption = {type = "string", default = "Button"}, clicks = {type = "number", default = 0},
    drawOrder = {type = "number", default = 200}
}}
function Button:configure() Engine.Bounds.bind(self, function(context) return Engine.Bounds.of(self.owner, context) end) end
function Button:load(world)
    Engine.Input.registerRegion(world, {owner = self,
        hitTest = function(context, x, y) return self:hitTest(context, x, y) end,
        onDown = function() self.clicks = self.clicks + 1; return true end})
end
function Button:draw(context)
    local x, y, w, h = self:getBounds(context); if not x then return false end
    love.graphics.setColor(self.clicks > 0 and 0.2 or 0.16, self.clicks > 0 and 0.6 or 0.38, 0.62, 1)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    love.graphics.setColor(1, 1, 1, 1); love.graphics.printf(self.caption .. " : " .. self.clicks, x, y + 14, w, "center")
end
return Button
