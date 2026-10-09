local Scene = require("core.lobject_component"):extend({
    componentType = "SceneComponent",
    properties = {x = {type = "number", default = 0, group = "Transform"}, y = {type = "number", default = 0, group = "Transform"}}
})
function Scene:getRelativePosition()
    local x, y, current = 0, 0, self
    while current do
        if current:isA(Scene) then x, y = x + current.properties.x, y + current.properties.y end
        current = current.parent
    end
    return x, y
end
function Scene:getWorldPosition()
    local transform = self.owner and self.owner.transform or {x = 0, y = 0}
    local x, y = self:getRelativePosition()
    return require("core.transform").point(transform, x, y)
end
return Scene
