local Engine = require("Engine")
local Bounds, Transform = Engine.Bounds, Engine.Transform
local OPTIONS = {"topLeft", "top", "topRight", "left", "center", "right", "bottomLeft", "bottom", "bottomRight"}
local Layout = Engine.Script:extend({scriptType = "RectLayout", properties = {
    width = {type = "number", default = 100}, height = {type = "number", default = 100},
    anchor = {type = "string", default = "center", group = "Layout", options = OPTIONS},
    pivot = {type = "string", default = "center", group = "Layout", options = OPTIONS}
}})
local POINTS = {topLeft = {0, 0}, top = {0.5, 0}, topRight = {1, 0},
    left = {0, 0.5}, center = {0.5, 0.5}, right = {1, 0.5},
    bottomLeft = {0, 1}, bottom = {0.5, 1}, bottomRight = {1, 1}}
function Layout:getLocalBounds()
    local pivot = assert(POINTS[self.pivot], "Invalid rectangle pivot")
    assert(self.width >= 0 and self.height >= 0, "Invalid rectangle size")
    return -pivot[1] * self.width, -pivot[2] * self.height, self.width, self.height
end
function Layout:anchorOffset(context)
    local anchor = assert(POINTS[self.anchor], "Invalid rectangle anchor")
    local x, y, w, h, source = Bounds.parent(self.owner, context)
    if not source then return 0, 0 end
    x, y = x + w * anchor[1], y + h * anchor[2]
    if source ~= self.owner.parent then
        x, y = Transform.point(source:getWorldTransform(context), x, y)
        x, y = Transform.inversePoint(self.owner.parent:getWorldTransform(context), x, y)
        assert(x, "Layout parent Transform cannot be inverted")
    end
    return x, y
end
function Layout:configure()
    Bounds.bind(self, function() return self:getLocalBounds() end, {primary = true})
    Transform.bindLocal(self.owner, {owner = self,
        resolve = function(authored, context)
            local value = assert(Transform.copy(authored)); local x, y = self:anchorOffset(context)
            value.x, value.y = value.x + x, value.y + y; return value
        end,
        unresolve = function(value, context)
            local x, y = self:anchorOffset(context)
            local result = {}; for name, item in pairs(value) do result[name] = item end
            result.x, result.y = value.x - x, value.y - y; return result
        end})
end
function Layout:drawEditor(context) context:bounds(self) end
return Layout
