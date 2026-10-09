local Sprite = require("core.RenderComponent"):extend({
    componentType = "SpriteComponent",
    properties = {image = {type = "image", default = false}}
})
function Sprite:draw(context)
    local image = context:image(self.properties.image)
    if not image then return false end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, -image:getWidth() / 2, -image:getHeight() / 2)
    return true
end
function Sprite:getLocalBounds(context)
    local image = context:image(self.properties.image)
    if image then return -image:getWidth() / 2, -image:getHeight() / 2, image:getWidth(), image:getHeight() end
end
return Sprite
