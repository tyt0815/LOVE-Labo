local Bounds = require("core.Bounds")
local Text = require("core.Script"):extend({scriptType = "Text", properties = {
    text = {type = "string", default = "Text"},
    fontSize = {type = "number", default = 20},
    width = {type = "number", default = 300, group = "Layout"},
    align = {type = "string", default = "left", group = "Layout"},
    red = {type = "number", default = 1, group = "Color"},
    green = {type = "number", default = 1, group = "Color"},
    blue = {type = "number", default = 1, group = "Color"},
    alpha = {type = "number", default = 1, group = "Color"},
    sortingOrder = {type = "number", default = 0}
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
function Text:draw()
    local align = self.align == "center" and "center" or self.align == "right" and "right" or "left"
    love.graphics.setFont(fontFor(self))
    love.graphics.setColor(self.red, self.green, self.blue, self.alpha)
    love.graphics.printf(self.text, 0, 0, math.max(1, self.width), align)
    return true
end
function Text:drawEditor(context) context:bounds(self) end
return Text
