-- labo-script: lobject
local Engine = require("Engine")
local Camera = {}
function Camera.build(self)
    self:setRootComponent("camera", Engine.CameraComponent)
end
return Camera
