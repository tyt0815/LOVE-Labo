local Rendering = {screen = {}}
-- 투영 제공자는 변환을 생략할 수 있으며, 소비자는 같은 검증·기본값을 사용한다.
function Rendering.normalizeProjection(value)
    if value == nil then return nil end
    local Transform = require("core.Transform")
    assert(type(value) == "table" and Transform.finite(value.width) and value.width > 0
        and Transform.finite(value.height) and value.height > 0, "Invalid projection dimensions")
    return {width = value.width, height = value.height,
        transform = Transform.affine(value.transform or {x = 0, y = 0})}
end
local function liveWorld(world)
    assert(type(world) == "table" and world.scope == "level" and world.world == world and not world.disposed, "Expected a live World")
end
function Rendering.createView(world, options)
    liveWorld(world)
    return require("core.RenderView").new(world, options or {})
end
function Rendering.createTarget(world, options)
    liveWorld(world)
    return require("core.RenderTarget").new(world, options or {})
end
function Rendering.views(world)
    local result = {}
    if not world then return result end
    for _, view in ipairs(world.renderViews or {}) do if view:isActive() then result[#result + 1] = view end end
    table.sort(result, function(a, b) return a.order < b.order or a.order == b.order and a.id < b.id end)
    return result
end
function Rendering.dispose(world)
    while world.renderViews and #world.renderViews > 0 do world.renderViews[#world.renderViews]:release() end
    while world.renderTargets and #world.renderTargets > 0 do world.renderTargets[#world.renderTargets]:release() end
end
-- 일반 draw 안에서 필요한 구간만 화면 왼쪽 위 기준 픽셀 좌표로 그린다.
function Rendering.withScreen(context, callback)
    if context and context.preview then return end
    assert(context and context.viewport and type(callback) == "function", "Expected draw context and callback")
    local viewport = context.viewport
    local ok, result = require("core.GraphicsScope").call(function()
        love.graphics.origin(); love.graphics.translate(viewport.x or 0, viewport.y or 0)
        return callback(context)
    end)
    assert(ok, result)
    return result
end
return Rendering
