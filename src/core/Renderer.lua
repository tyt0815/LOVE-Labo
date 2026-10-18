local Render = "draw"
local Transform = require("core.Transform")
local Renderer = {}
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
    if not ctx.viewport then ctx.preview = true end
    ctx.withScreen = ctx.withScreen or function(_, callback) return require("core.Rendering").withScreen(ctx, callback) end
    for _, entry in ipairs(require("core.ScriptOrder").entries(objects, Render)) do
        local script = entry.script
        if script.owner and script.owner.scripts[script.id] == script and script.enabled ~= false and (not ctx.includes or ctx.includes(script)) then
            local owner = script.owner
            local affine = love.math.newTransform()
            local ok, result, err = require("core.GraphicsScope").call(function()
                local world = ctx.transform and ctx:transform(script) or script:getWorldTransform()
                local x, y = toScreen(world.x, world.y)
                local ax, ay = Transform.point(world, 1, 0)
                local bx, by = Transform.point(world, 0, 1)
                ax, ay = toScreen(ax, ay); bx, by = toScreen(bx, by)
                affine:setMatrix(ax - x, bx - x, 0, x, ay - y, by - y, 0, y, 0, 0, 1, 0, 0, 0, 0, 1)
                love.graphics.origin(); love.graphics.applyTransform(affine)
                -- 사용자 draw가 실패해도 다음 프레임의 그래픽 상태를 오염시키지 않는다.
                local runtime = owner:getWorld()
                local profiler = runtime and runtime.profiler
                local started = profiler and profiler.recording and profiler.detailed and love.timer.getTime()
                local result, err = script:draw(ctx)
                if started then profiler:sample("draw", script, love.timer.getTime() - started) end
                return result, err
            end)
            affine:release()
            if not ok then error(result, 0) end
            if result == false and err then error(err, 0) end
            drawn = drawn or result ~= false
            if ctx.drawn then ctx.drawn[owner] = result ~= false or ctx.drawn[owner] end
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
    local ctx = viewport:context(function(_, reference) return reference and reference ~= false and imageFor(reference) or nil end)
    ctx.drawn = {}
    local objects = require("core.ScriptOrder").hosts(world)
    if viewport.view then
        -- 범용 필터는 스크립트마다 적용하고 좌표계나 플러그인 종류를 분류하지 않는다.
        ctx.includes = function(script) return viewport.view:includes(script) end
    end
    local ok, drawn = require("core.GraphicsScope").call(function()
        love.graphics.intersectScissor(viewport.x, viewport.y, viewport.width, viewport.height)
        return Renderer.drawObjects(objects, imageFor,
            function(x, y) return viewport:worldToScreen(x, y) end, viewport.scale, ctx)
    end)
    assert(ok, drawn)
    return ctx.drawn
end
return Renderer
