local Render = require("core.render_component")
local Transform = require("core.transform")
local Renderer = {}
local function context(imageFor)
    return {image = function(_, reference) if reference and reference ~= false then return imageFor(reference) end end}
end
local function visit(object, fn)
    for _, name in ipairs(object:getComponentOrder()) do
        local component = object.components[name]
        if component:isA(Render) then fn(component) end
    end
end
function Renderer.draw(object, imageFor, toScreen, zoom)
    local drawn, ctx = false, context(imageFor)
    visit(object, function(component)
        local world = component:getWorldTransform()
        local x, y = toScreen(world.x, world.y)
        local a, b, c, d = Transform.basis(world)
        local affine, z = love.math.newTransform(), zoom or 1
        affine:setMatrix(a * z, c * z, 0, x, b * z, d * z, 0, y, 0, 0, 1, 0, 0, 0, 0, 1)
        love.graphics.push("all"); love.graphics.origin(); love.graphics.applyTransform(affine)
        -- 사용자 Draw가 실패해도 다음 프레임의 그래픽 상태를 오염시키지 않는다.
        local ok, result, err = pcall(component.Draw, component, ctx)
        love.graphics.pop(); affine:release()
        if not ok then error(result, 0) end
        if result == false and err then error(err, 0) end
        drawn = drawn or result ~= false
    end)
    return drawn
end
function Renderer.hit(object, imageFor, worldX, worldY)
    local hit, ctx = false, context(imageFor)
    visit(object, function(component)
        local x, y = Transform.inversePoint(component:getWorldTransform(), worldX, worldY)
        if x then
            local left, top, width, height = component:GetLocalBounds(ctx)
            if left and x >= left and x <= left + width and y >= top and y <= top + height then hit = true end
        end
    end)
    return hit
end
function Renderer.outline(object, imageFor, toScreen)
    local ctx = context(imageFor)
    visit(object, function(component)
        local x, y, width, height = component:GetLocalBounds(ctx)
        if x then
            local points, world = {}, component:getWorldTransform()
            for _, corner in ipairs({{x, y}, {x + width, y}, {x + width, y + height}, {x, y + height}}) do
                local wx, wy = Transform.point(world, corner[1], corner[2])
                local sx, sy = toScreen(wx, wy); points[#points + 1], points[#points + 2] = sx, sy
            end
            love.graphics.polygon("line", points)
        end
    end)
end
return Renderer
