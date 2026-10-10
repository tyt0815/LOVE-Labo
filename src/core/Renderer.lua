local Render = require("core.RenderComponent")
local Transform = require("core.Transform")
local Renderer = {}
local function context(imageFor)
    return {image = function(_, reference) if reference and reference ~= false then return imageFor(reference) end end}
end
local function visit(object, fn)
    for _, entry in ipairs(require("core.ComponentOrder").entries({object}, Render)) do
        fn(entry.component)
    end
end
function Renderer.drawObjects(objects, imageFor, toScreen, zoom)
    local drawn, ctx = false, context(imageFor)
    for _, entry in ipairs(require("core.ComponentOrder").entries(objects, Render)) do
        local component = entry.component
        local world = component:getWorldTransform()
        local x, y = toScreen(world.x, world.y)
        local a, b, c, d = Transform.basis(world)
        local affine, z = love.math.newTransform(), zoom or 1
        affine:setMatrix(a * z, c * z, 0, x, b * z, d * z, 0, y, 0, 0, 1, 0, 0, 0, 0, 1)
        love.graphics.push("all"); love.graphics.origin(); love.graphics.applyTransform(affine)
        -- 사용자 draw가 실패해도 다음 프레임의 그래픽 상태를 오염시키지 않는다.
        local ok, result, err = pcall(component.draw, component, ctx)
        love.graphics.pop(); affine:release()
        if not ok then error(result, 0) end
        if result == false and err then error(err, 0) end
        drawn = drawn or result ~= false
    end
    return drawn
end
function Renderer.draw(object, imageFor, toScreen, zoom)
    return Renderer.drawObjects({object}, imageFor, toScreen, zoom)
end
function Renderer.hit(object, imageFor, worldX, worldY)
    local hit, ctx = false, context(imageFor)
    visit(object, function(component)
        if component:hitTest(ctx, worldX, worldY) then hit = true end
    end)
    return hit
end
function Renderer.outline(object, imageFor, toScreen, measureOnly)
    local ctx = context(imageFor)
    visit(object, function(component)
        local x, y, width, height = component:getBounds(ctx)
        if x then
            local points, world = {}, component:getWorldTransform()
            for _, corner in ipairs({{x, y}, {x + width, y}, {x + width, y + height}, {x, y + height}}) do
                local wx, wy = Transform.point(world, corner[1], corner[2])
                local sx, sy = toScreen(wx, wy); points[#points + 1], points[#points + 2] = sx, sy
            end
            if not measureOnly then love.graphics.polygon("line", points) end
        end
    end)
end
function Renderer.drawWorld(world, imageFor, viewport)
    local ctx, drawn = viewport:context(function(_, reference) return reference and reference ~= false and imageFor(reference) or nil end), {}
    local Space = require("core.CoordinateSpace")
    for _, entry in ipairs(require("core.ComponentOrder").entries(world.lobjects, Render)) do
        local component = entry.component
        local transform = Space.transform(component)
        local x, y = Transform.point(transform, 0, 0)
        local ax, ay = Transform.point(transform, 1, 0)
        local bx, by = Transform.point(transform, 0, 1)
        local screen = Space.canvas(component) ~= nil
        local function project(px, py)
            if screen then return viewport.x + viewport.width / 2 + px, viewport.y + viewport.height / 2 + py end
            return viewport:worldToScreen(px, py)
        end
        x, y = project(x, y); ax, ay = project(ax, ay); bx, by = project(bx, by)
        local affine = love.math.newTransform()
        affine:setMatrix(ax - x, bx - x, 0, x, ay - y, by - y, 0, y, 0, 0, 1, 0, 0, 0, 0, 1)
        love.graphics.push("all")
        if not screen then
            love.graphics.intersectScissor(viewport.x + (viewport.width - viewport.contentWidth) / 2,
                viewport.y + (viewport.height - viewport.contentHeight) / 2, viewport.contentWidth, viewport.contentHeight)
        end
        love.graphics.origin(); love.graphics.applyTransform(affine)
        local ok, result, err = pcall(component.draw, component, ctx)
        love.graphics.pop(); affine:release()
        if not ok then error(result, 0) end
        if result == false and err then error(err, 0) end
        drawn[component.owner] = drawn[component.owner] or result ~= false
    end
    return drawn
end
return Renderer
