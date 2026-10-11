local Transform = require("core.Transform")
local Bounds = {}
function Bounds.getBounds(script, context)
    if script.properties.fillParent then
        local object = script.owner.parent
        while object do
            for _, id in ipairs(object.scriptOrder) do
                local parent = object.scripts[id]
                if parent.getLocalBounds then return parent:getBounds(context) end
            end
            object = object.parent
        end
    end
    return script:getLocalBounds(context)
end
function Bounds.hitTest(script, context, worldX, worldY)
    local world = context and context.transform and context:transform(script) or script:getWorldTransform()
    local x, y = Transform.inversePoint(world, worldX, worldY)
    if not x then return false end
    local left, top, width, height = script:getBounds(context)
    if not left then return false end
    assert(Transform.finite(left) and Transform.finite(top) and Transform.finite(width) and Transform.finite(height)
        and width >= 0 and height >= 0, "Invalid script bounds")
    return width > 0 and height > 0 and x >= left and x <= left + width and y >= top and y <= top + height, x, y
end
return Bounds
