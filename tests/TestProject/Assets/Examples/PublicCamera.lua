local Engine = require("Engine")
local Camera = {extends = "db48127e-7d1f-4d9e-a0b0-5e0a9b0faeaa", properties = {
    width = {type = "number", default = 1280}, height = {type = "number", default = 720},
    zoom = {type = "number", default = 1}
}}
function Camera:getProjection()
    return {transform = self.owner:getWorldTransform(), width = self.width / self.zoom, height = self.height / self.zoom}
end
function Camera:load(world)
    self.view = Engine.Rendering.createView(world, {owner = self, projection = function() return self:getProjection() end})
end
function Camera:unload() self.view:release() end
return Camera
