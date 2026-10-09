local Render = require("core.SceneComponent"):extend({componentType = "RenderComponent"})
function Render:draw(context) return false end
function Render:getLocalBounds(context) end
return Render
