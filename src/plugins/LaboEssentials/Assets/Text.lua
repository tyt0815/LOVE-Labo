local Engine = require("Engine")
local Bounds = Engine.Bounds
local Text = Engine.Script:extend({scriptType = "Text", properties = {
    text = {type = "string", default = "Text"},
    fontSize = {type = "number", default = 20},
    width = {type = "number", default = 300, group = "Layout"},
    align = {type = "string", default = "left", group = "Layout"},
    red = {type = "number", default = 1, group = "Color"},
    green = {type = "number", default = 1, group = "Color"},
    blue = {type = "number", default = 1, group = "Color"},
    alpha = {type = "number", default = 1, group = "Color"}
}})
local fonts = {}
local function fontFor(script)
    local size = math.max(1, math.min(512, math.floor(script.fontSize)))
    if not fonts[size] then fonts[size] = love.graphics.newFont(size) end
    return fonts[size]
end
Text.getBounds, Text.hitTest = Bounds.getBounds, Bounds.hitTest
function Text:getLocalBounds()
    local font = fontFor(self)
    local width = math.max(1, self.width)
    local _, lines = font:getWrap(self.text, width)
    return 0, 0, width, math.max(1, #lines) * font:getHeight() * font:getLineHeight()
end
function Text:configure()
    Bounds.bind(self, function(context)
        local x, y, w, h = Bounds.of(self.owner, context)
        if x then return x, y, w, h end
        return self:getLocalBounds()
    end)
end
function Text:draw(context)
    local align = self.align == "center" and "center" or self.align == "right" and "right" or "left"
    love.graphics.setFont(fontFor(self))
    love.graphics.setColor(self.red, self.green, self.blue, self.alpha)
    local x, y, width = self:getBounds(context)
    love.graphics.printf(self.text, x, y, math.max(1, width), align)
    return true
end
function Text:drawEditor(context) context:bounds(self) end
return Text
