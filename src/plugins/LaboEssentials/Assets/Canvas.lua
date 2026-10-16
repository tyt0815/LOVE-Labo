local Engine = require("Engine")
local Bounds, Transform = Engine.Bounds, Engine.Transform
local Canvas = Engine.Script:extend({scriptType = "Canvas", properties = {
    width = {type = "number", default = 1280}, height = {type = "number", default = 720},
    matchCamera = {type = "boolean", default = true}, cameraSource = {type = "script", default = false}
}})
function Canvas:getViewSource()
    if self.cameraSource ~= false then
        if not self.cameraSource.owner or self.cameraSource.hasUnloaded or self.cameraSource.enabled == false then return nil end
        return self.cameraSource
    end
    local object = self.owner.parent
    while object do
        for _, id in ipairs(object.scriptOrder) do
            local script = object.scripts[id]
            if type(script.getProjection) == "function" then return script end
        end
        object = object.parent
    end
end
function Canvas:metrics()
    assert(self.width > 0 and self.height > 0, "Canvas reference size must be positive")
    local camera = self.matchCamera and self:getViewSource()
    local projection
    if camera then projection = Engine.Rendering.normalizeProjection(camera:getProjection()) end
    if not projection then return self.width, self.height, 1 end
    local scale = math.min(projection.width / self.width, projection.height / self.height)
    return projection.width / scale, projection.height / scale, scale, projection
end
function Canvas:getLocalBounds()
    local w, h = self:metrics(); return -w / 2, -h / 2, w, h
end
function Canvas:configure()
    Bounds.bind(self, function() return self:getLocalBounds() end, {primary = true})
    Transform.bindLocal(self.owner, {owner = self,
        resolve = function(authored, context)
            local _, _, scale, projection = self:metrics()
            if not projection then return authored end
            local localValue = assert(Transform.copy(authored))
            localValue.x, localValue.y = authored.x * scale, authored.y * scale
            localValue.scaleX, localValue.scaleY = authored.scaleX * scale, authored.scaleY * scale
            local desired = Transform.compose(projection.transform, localValue)
            return self.owner.parent and assert(Transform.relative(self.owner.parent:getWorldTransform(context), desired)) or desired
        end,
        unresolve = function(value, context)
            local _, _, scale, projection = self:metrics()
            if not projection then return value end
            local world = self.owner.parent and Transform.compose(self.owner.parent:getWorldTransform(context), value) or value
            local localValue = assert(Transform.relative(projection.transform, world))
            local result = assert(Transform.copy(self.owner.transform))
            result.x, result.y = localValue.x / scale, localValue.y / scale
            return result
        end})
end
function Canvas:drawEditor(context) context:bounds(self) end
return Canvas
