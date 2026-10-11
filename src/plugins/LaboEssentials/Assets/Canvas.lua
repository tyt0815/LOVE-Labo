local Bounds = require("core.Bounds")
local Canvas = require("core.Script"):extend({scriptType = "Canvas", canvas = true, properties = {
    width = {type = "number", default = 1280}, height = {type = "number", default = 720},
    matchViewport = {type = "boolean", default = true}
}})
Canvas.getBounds, Canvas.hitTest = Bounds.getBounds, Bounds.hitTest
function Canvas:getLocalBounds(context)
    local width, height = self.width, self.height
    if self.matchViewport and context and context.viewport then width, height = context.viewport.width, context.viewport.height end
    assert(width >= 0 and height >= 0, "Invalid canvas size")
    return -width / 2, -height / 2, width, height
end
function Canvas:drawEditor(context) context:bounds(self) end
return Canvas
