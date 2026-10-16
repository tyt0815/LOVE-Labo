local Engine = require("Engine")
local Canvas = {properties = {width = {type = "number", default = 1280}, height = {type = "number", default = 720}}}
function Canvas:scale()
    local camera = self.owner.parent and self.owner.parent:getScriptByName("camera")
    return camera and 1 / camera.zoom or 1
end
function Canvas:configure()
    Engine.Bounds.bind(self, function() return -self.width / 2, -self.height / 2, self.width, self.height end, {primary = true})
    Engine.Transform.bindLocal(self.owner, {owner = self,
        resolve = function(value)
            local t, scale = assert(Engine.Transform.copy(value)), self:scale()
            t.x, t.y, t.scaleX, t.scaleY = t.x * scale, t.y * scale, t.scaleX * scale, t.scaleY * scale
            return t
        end,
        unresolve = function(value)
            local t = assert(Engine.Transform.copy(self.owner.transform))
            t.x, t.y = value.x / self:scale(), value.y / self:scale(); return t
        end})
end
return Canvas
