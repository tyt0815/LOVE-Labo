local Bounds = require("core.Bounds")
local Rect = require("core.Script"):extend({scriptType = "Rect", properties = {
    width = {type = "number", default = 100}, height = {type = "number", default = 100},
    fillParent = {type = "boolean", default = false}
}})
Rect.getBounds, Rect.hitTest = Bounds.getBounds, Bounds.hitTest
function Rect:getLocalBounds()
    assert(self.width >= 0 and self.height >= 0, "Invalid rectangle size")
    return -self.width / 2, -self.height / 2, self.width, self.height
end
return Rect
