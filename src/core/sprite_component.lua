local Sprite = require("core.render_component"):extend({
    componentType = "SpriteComponent",
    properties = {image = {type = "image", default = false}}
})
function Sprite:Draw(context)
    local image = context:image(self.properties.image)
    if not image then return false end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, -image:getWidth() / 2, -image:getHeight() / 2)
    return true
end
function Sprite:GetLocalBounds(context)
    local image = context:image(self.properties.image)
    if image then return -image:getWidth() / 2, -image:getHeight() / 2, image:getWidth(), image:getHeight() end
end
return Sprite
