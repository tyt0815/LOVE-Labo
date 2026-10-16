local Engine = require("Engine")
local OPTIONS = {"topLeft", "top", "topRight", "left", "center", "right", "bottomLeft", "bottom", "bottomRight"}
local POINTS = {topLeft = {0, 0}, top = {0.5, 0}, topRight = {1, 0}, left = {0, 0.5}, center = {0.5, 0.5},
    right = {1, 0.5}, bottomLeft = {0, 1}, bottom = {0.5, 1}, bottomRight = {1, 1}}
local Layout = {properties = {
    width = {type = "number", default = 176}, height = {type = "number", default = 44},
    anchor = {type = "string", default = "center", options = OPTIONS}, pivot = {type = "string", default = "center", options = OPTIONS}
}}
function Layout:offset(context)
    local x, y, w, h, source = Engine.Bounds.parent(self.owner, context)
    if not source then return 0, 0 end
    local anchor = POINTS[self.anchor]
    x, y = x + w * anchor[1], y + h * anchor[2]
    if source ~= self.owner.parent then
        x, y = Engine.Transform.point(source:getWorldTransform(context), x, y)
        x, y = Engine.Transform.inversePoint(self.owner.parent:getWorldTransform(context), x, y)
        assert(x, "Layout parent Transform cannot be inverted")
    end
    return x, y
end
function Layout:configure()
    Engine.Bounds.bind(self, function()
        local pivot = POINTS[self.pivot]; return -pivot[1] * self.width, -pivot[2] * self.height, self.width, self.height
    end, {primary = true})
    Engine.Transform.bindLocal(self.owner, {owner = self,
        resolve = function(value, context)
            local t = assert(Engine.Transform.copy(value)); local x, y = self:offset(context)
            t.x, t.y = t.x + x, t.y + y; return t
        end,
        unresolve = function(value, context)
            local t = assert(Engine.Transform.copy(self.owner.transform)); local x, y = self:offset(context)
            t.x, t.y = value.x - x, value.y - y; return t
        end})
end
function Layout:drawEditor(context) context:bounds(self) end
return Layout
