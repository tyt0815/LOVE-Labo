local Base = require("core.LObjectComponent")
local Transform = require("core.Transform")
local TRANSFORM_PROPERTIES = {}
for name in pairs(Transform.FIELDS) do TRANSFORM_PROPERTIES[name] = {type = "number", default = name:match("^scale") and 1 or 0, group = "Transform"} end
local Scene = Base:extend({componentType = "SceneComponent", properties = TRANSFORM_PROPERTIES})
function Scene:new(overrides)
    local component = Base.new(self, overrides)
    component.transform = assert(Transform.copy(component.properties))
    -- 기존 properties.x 접근과 Transform API는 같은 값을 읽고 쓴다.
    for name in pairs(Transform.FIELDS) do component.properties[name] = nil end
    setmetatable(component.properties, {
        __index = function(_, name) if Transform.FIELDS[name] then return component.transform[name] end end,
        __newindex = function(values, name, value)
            if Transform.FIELDS[name] then
                local nextTransform = {}; for field in pairs(Transform.FIELDS) do nextTransform[field] = component.transform[field] end
                nextTransform[name] = value; component:setTransform(nextTransform)
            else rawset(values, name, value) end
        end
    })
    return component
end
function Scene:setTransform(value)
    local transform = assert(Transform.copy(value))
    for name in pairs(Transform.FIELDS) do self.transform[name] = transform[name] end
end
function Scene:setProperties(values)
    self:setTransform(values)
    for name in pairs(getmetatable(self).properties) do if not Transform.FIELDS[name] then self.properties[name] = values[name] end end
end
function Scene:getWorldTransform()
    local parent = self.parent
    while parent and not parent:isA(Scene) do parent = parent.parent end
    return parent and Transform.compose(parent:getWorldTransform(), self.transform) or self.transform
end
function Scene:getWorldPosition() local world = self:getWorldTransform(); return world.x, world.y end
function Scene:getRelativePosition()
    local x, y = self:getWorldPosition()
    if self.owner then return Transform.inversePoint(self.owner.transform, x, y) end
    return x, y
end
return Scene
