local Transform = require("core.Transform")
local Rect = require("core.BoundsComponent"):extend({componentType = "RectComponent", properties = {
    width = {type = "number", default = 100, group = "Bounds"},
    height = {type = "number", default = 100, group = "Bounds"}
}})
function Rect:getLocalBounds(context)
    local width, height = self.properties.width, self.properties.height
    assert(Transform.finite(width) and width >= 0 and Transform.finite(height) and height >= 0, "Invalid rectangle size")
    return -width / 2, -height / 2, width, height
end
return Rect
