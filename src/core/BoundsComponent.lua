local Transform = require("core.Transform")
local Bounds = require("core.SceneComponent"):extend({componentType = "BoundsComponent", properties = {
    fillParent = {type = "boolean", default = false, group = "Bounds"}
}})
function Bounds:getLocalBounds(context) end
function Bounds:getBounds(context)
    if self.properties.fillParent then
        local parent = require("core.CoordinateSpace").parent(self)
        while parent and not parent:isA(Bounds) do parent = require("core.CoordinateSpace").parent(parent) end
        if parent then return parent:getBounds(context) end
    end
    return self:getLocalBounds(context)
end
function Bounds:hitTest(context, worldX, worldY)
    local world = context and context.transform and context:transform(self) or self:getWorldTransform()
    local x, y = Transform.inversePoint(world, worldX, worldY)
    if not x then return false end
    local left, top, width, height = self:getBounds(context)
    if not left then return false end
    assert(Transform.finite(left) and Transform.finite(top) and Transform.finite(width) and Transform.finite(height)
        and width >= 0 and height >= 0, "Invalid component bounds")
    return width > 0 and height > 0 and x >= left and x <= left + width and y >= top and y <= top + height, x, y
end
return Bounds
