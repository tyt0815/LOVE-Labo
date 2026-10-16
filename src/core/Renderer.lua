local Render = "draw"
local Transform = require("core.Transform")
local Renderer = {}
local function invoke(script, callback, ctx, viewport, screen)
    if viewport.view and not viewport.view:includes(script, screen) then return end
    local owner = script.owner
    if not owner or owner.scripts[script.id] ~= script or script.enabled == false or script.hasUnloaded then return end
    love.graphics.push("all")
    love.graphics.intersectScissor(viewport.x, viewport.y, viewport.width, viewport.height)
    love.graphics.origin()
    if screen then love.graphics.translate(viewport.x, viewport.y)
    else
        local x, y = viewport:worldToScreen(0, 0)
        local ax, ay = viewport:worldToScreen(1, 0)
        local bx, by = viewport:worldToScreen(0, 1)
        local affine = love.math.newTransform()
        affine:setMatrix(ax - x, bx - x, 0, x, ay - y, by - y, 0, y, 0, 0, 1, 0, 0, 0, 0, 1)
        love.graphics.applyTransform(affine); affine:release()
    end
    local ok, result, err = pcall(script[callback], script, ctx)
    love.graphics.pop()
    if not ok then error(result, 0) end
    if result == false and err then error(err, 0) end
end
local function context(imageFor)
    return {image = function(_, reference) if reference and reference ~= false then return imageFor(reference) end end}
end
local function visit(object, fn)
    for _, entry in ipairs(require("core.ScriptOrder").entries({object}, Render)) do
        fn(entry.script)
    end
end
function Renderer.drawObjects(objects, imageFor, toScreen, zoom, drawContext)
    local drawn, ctx = false, drawContext or context(imageFor)
    for _, entry in ipairs(require("core.ScriptOrder").entries(objects, Render)) do
        local script = entry.script
        if script.owner and script.owner.scripts[script.id] == script and script.enabled ~= false then
            local world = ctx.transform and ctx:transform(script) or script:getWorldTransform()
            local x, y = toScreen(world.x, world.y)
            local a, b, c, d = Transform.basis(world)
            local affine, z = love.math.newTransform(), zoom or 1
            affine:setMatrix(a * z, c * z, 0, x, b * z, d * z, 0, y, 0, 0, 1, 0, 0, 0, 0, 1)
            love.graphics.push("all"); love.graphics.origin(); love.graphics.applyTransform(affine)
            -- 사용자 draw가 실패해도 다음 프레임의 그래픽 상태를 오염시키지 않는다.
            local ok, result, err = pcall(script.draw, script, ctx)
            love.graphics.pop(); affine:release()
            if not ok then error(result, 0) end
            if result == false and err then error(err, 0) end
            drawn = drawn or result ~= false
        end
    end
    return drawn
end
function Renderer.draw(object, imageFor, toScreen, zoom)
    return Renderer.drawObjects({object}, imageFor, toScreen, zoom)
end
function Renderer.hit(object, imageFor, worldX, worldY)
    local hit, ctx = false, context(imageFor)
    visit(object, function(script)
        if script.hitTest and script:hitTest(ctx, worldX, worldY) then hit = true end
    end)
    return hit
end
function Renderer.outline(object, imageFor, toScreen, measureOnly)
    local ctx = context(imageFor)
    visit(object, function(script)
        if not script.getBounds then return end
        local x, y, width, height = script:getBounds(ctx)
        if x then
            local points, world = {}, script:getWorldTransform()
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
    for _, entry in ipairs(require("core.ScriptOrder").entries(require("core.ScriptOrder").hosts(world), Render)) do
        local script = entry.script
        local owner = script.owner
        if owner and owner:getWorld() == world and owner.scripts[script.id] == script and script.enabled ~= false then
            if owner.scope then
                invoke(script, "draw", ctx, viewport, false)
            else
                local transform = Space.transform(script)
                local x, y = Transform.point(transform, 0, 0)
                local ax, ay = Transform.point(transform, 1, 0)
                local bx, by = Transform.point(transform, 0, 1)
                local screen = Space.canvas(script) ~= nil
                if not viewport.view or viewport.view:includes(script, screen) then
                    local function project(px, py)
                        if screen then return viewport.x + viewport.width / 2 + px, viewport.y + viewport.height / 2 + py end
                        return viewport:worldToScreen(px, py)
                    end
                    x, y = project(x, y); ax, ay = project(ax, ay); bx, by = project(bx, by)
                    local affine = love.math.newTransform()
                    affine:setMatrix(ax - x, bx - x, 0, x, ay - y, by - y, 0, y, 0, 0, 1, 0, 0, 0, 0, 1)
                    love.graphics.push("all")
                    love.graphics.intersectScissor(viewport.x, viewport.y, viewport.width, viewport.height)
                    love.graphics.origin(); love.graphics.applyTransform(affine)
                    local ok, result, err = pcall(script.draw, script, ctx)
                    love.graphics.pop(); affine:release()
                    if not ok then error(result, 0) end
                    if result == false and err then error(err, 0) end
                    drawn[owner] = drawn[owner] or result ~= false
                end
            end
        end
    end
    for _, entry in ipairs(require("core.ScriptOrder").entries(require("core.ScriptOrder").hosts(world, true), "drawScreen")) do
        if entry.script.owner and entry.script.owner:getWorld() == world then invoke(entry.script, "drawScreen", ctx, viewport, true) end
    end
    return drawn
end
return Renderer
