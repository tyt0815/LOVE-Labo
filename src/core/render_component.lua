local Render = require("core.scene_component"):extend({componentType = "RenderComponent"})
function Render:Draw(context) return false end
function Render:GetLocalBounds(context) end
return Render
