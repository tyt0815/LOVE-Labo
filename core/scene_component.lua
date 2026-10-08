local Scene = require("core.lobject_component"):extend({
    componentType = "SceneComponent",
    properties = {x = {type = "number", default = 0}, y = {type = "number", default = 0}}
})
function Scene:getWorldPosition()
    local transform = self.owner and self.owner.transform or {x = 0, y = 0}
    return transform.x + self.properties.x, transform.y + self.properties.y
end
return Scene
