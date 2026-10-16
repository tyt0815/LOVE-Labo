local Engine = require("Engine")
local Bounds = Engine.Bounds
local Sprite = Engine.Script:extend({scriptType = "Sprite", properties = {
    image = {type = "image", default = false},
    fillParent = {type = "boolean", default = false, group = "Bounds"}
}})
Sprite.getBounds, Sprite.hitTest = Bounds.getBounds, Bounds.hitTest
function Sprite:configure()
    Bounds.bind(self, function(context)
        local x, y, w, h = Bounds.of(self.owner, context)
        if x then return x, y, w, h end
        if self.fillParent then
            x, y, w, h = Bounds.parent(self.owner, context)
            if x then return x, y, w, h end
        end
        return self:getLocalBounds(context)
    end)
end
function Sprite:draw(context)
    local image = context:image(self.image)
    if not image then return false end
    local x, y, width, height = self:getBounds(context)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x, y, 0, width / image:getWidth(), height / image:getHeight())
    return true
end
function Sprite:getLocalBounds(context)
    local image = context:image(self.image)
    if image then return -image:getWidth() / 2, -image:getHeight() / 2, image:getWidth(), image:getHeight() end
end
function Sprite:drawEditor(context) context:bounds(self) end
return Sprite
