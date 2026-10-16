local Rendering = {screen = {}}
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
return Rendering
