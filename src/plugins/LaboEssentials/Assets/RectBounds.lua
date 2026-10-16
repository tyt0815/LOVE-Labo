local Engine = require("Engine")
local Bounds = Engine.Bounds
local RectBounds = Engine.Script:extend({scriptType = "RectBounds", properties = {
    width = {type = "number", default = 100}, height = {type = "number", default = 100},
    fillParent = {type = "boolean", default = false}
}})
RectBounds.getBounds, RectBounds.hitTest = Bounds.getBounds, Bounds.hitTest
function RectBounds:configure()
    Bounds.bind(self, function(context)
        if self.fillParent then
            local x, y, w, h = Bounds.parent(self.owner, context)
            if x then return x, y, w, h end
        end
        return self:getLocalBounds()
    end, {primary = true})
end
function RectBounds:getLocalBounds()
    assert(self.width >= 0 and self.height >= 0, "Invalid rectangle size")
    return -self.width / 2, -self.height / 2, self.width, self.height
end
function RectBounds:drawEditor(context) context:bounds(self) end
return RectBounds
