local Sprite = require("core.sprite_component")
local Renderer = {}
function Renderer.draw(object, imageFor, toScreen, zoom)
    local drawn = false
    for _, name in ipairs(object:getComponentOrder()) do
        local component = object.components[name]
        if component:isA(Sprite) and component.properties.image ~= false then
            local image = imageFor(component.properties.image)
            if image then
                local transform = object.transform
                local Transform = require("core.transform")
                local cx, cy = component:getRelativePosition()
                local wx, wy = Transform.point(transform, cx - image:getWidth() / 2, cy - image:getHeight() / 2)
                local x, y = toScreen(wx, wy)
                love.graphics.setColor(1, 1, 1, 1)
                local a, b, c, d = Transform.basis(transform)
                local affine, z = love.math.newTransform(), zoom or 1
                affine:setMatrix(a * z, c * z, 0, x, b * z, d * z, 0, y, 0, 0, 1, 0, 0, 0, 0, 1)
                love.graphics.draw(image, affine)
                affine:release()
                drawn = true
            end
        end
    end
    return drawn
end
function Renderer.hit(object, imageFor, worldX, worldY)
    local x, y = require("core.transform").inversePoint(object.transform, worldX, worldY)
    if x == nil then return false end
    for _, name in ipairs(object:getComponentOrder()) do
        local component = object.components[name]
        if component:isA(Sprite) and component.properties.image ~= false then
            local image = imageFor(component.properties.image)
            local cx, cy = component:getRelativePosition()
            if image and math.abs(x - cx) <= image:getWidth() / 2 and math.abs(y - cy) <= image:getHeight() / 2 then return true end
        end
    end
    return false
end
function Renderer.outline(object, imageFor, toScreen)
    for _, name in ipairs(object:getComponentOrder()) do
        local component = object.components[name]
        if component:isA(Sprite) and component.properties.image ~= false then
            local image = imageFor(component.properties.image)
            if image then
                local halfWidth, halfHeight = image:getWidth() / 2, image:getHeight() / 2
                local points = {}
                local cx, cy = component:getRelativePosition()
                for _, corner in ipairs({{-halfWidth, -halfHeight}, {halfWidth, -halfHeight}, {halfWidth, halfHeight}, {-halfWidth, halfHeight}}) do
                    local wx, wy = require("core.transform").point(object.transform, cx + corner[1], cy + corner[2])
                    local x, y = toScreen(wx, wy)
                    points[#points + 1], points[#points + 2] = x, y
                end
                love.graphics.polygon("line", points)
            end
        end
    end
end
return Renderer
