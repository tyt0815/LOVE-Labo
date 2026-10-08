local Sprite = require("core.sprite_component")
local Renderer = {}
function Renderer.draw(object, imageFor, toScreen, zoom)
    local drawn = false
    for _, name in ipairs(object.componentOrder or {}) do
        local component = object.components[name]
        if component:isA(Sprite) and component.properties.image ~= false then
            local image = imageFor(component.properties.image)
            if image then
                local wx, wy = component:getWorldPosition()
                local x, y = toScreen(wx, wy)
                love.graphics.setColor(1, 1, 1, 1)
                local transform = object.transform
                love.graphics.draw(image, x, y, math.rad(transform.rotation or 0),
                    (zoom or 1) * (transform.scaleX or 1), (zoom or 1) * (transform.scaleY or 1), image:getWidth() / 2, image:getHeight() / 2)
                drawn = true
            end
        end
    end
    return drawn
end
function Renderer.hit(object, imageFor, worldX, worldY)
    local x, y = require("core.transform").inversePoint(object.transform, worldX, worldY)
    for _, name in ipairs(object.componentOrder or {}) do
        local component = object.components[name]
        if component:isA(Sprite) and component.properties.image ~= false then
            local image = imageFor(component.properties.image)
            if image and math.abs(x - component.properties.x) <= image:getWidth() / 2 and math.abs(y - component.properties.y) <= image:getHeight() / 2 then return true end
        end
    end
    return false
end
return Renderer
