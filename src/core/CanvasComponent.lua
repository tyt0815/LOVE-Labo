local Canvas = require("core.RectComponent"):extend({componentType = "CanvasComponent", properties = {
    matchViewport = {type = "boolean", default = true, group = "Canvas"},
    width = {type = "number", default = 1280, group = "Bounds"},
    height = {type = "number", default = 720, group = "Bounds"}
}})
function Canvas:getLocalBounds(context)
    if self.properties.matchViewport and context and context.viewport then
        local view = context.viewport
        return -view.width / 2, -view.height / 2, view.width, view.height
    end
    return Canvas.super.getLocalBounds(self, context)
end
return Canvas
