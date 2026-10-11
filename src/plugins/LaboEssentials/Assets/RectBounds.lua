local Bounds = require("core.Bounds")
local RectBounds = require("core.Script"):extend({scriptType = "RectBounds", properties = {
    width = {type = "number", default = 100}, height = {type = "number", default = 100},
    fillParent = {type = "boolean", default = false}
}})
RectBounds.getBounds, RectBounds.hitTest = Bounds.getBounds, Bounds.hitTest
function RectBounds:getLocalBounds()
    assert(self.width >= 0 and self.height >= 0, "Invalid rectangle size")
    return -self.width / 2, -self.height / 2, self.width, self.height
end
function RectBounds:drawEditor(context) context:bounds(self) end
return RectBounds
