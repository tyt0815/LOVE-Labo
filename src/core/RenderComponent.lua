local Render = require("core.BoundsComponent"):extend({componentType = "RenderComponent", properties = {
    sortingOrder = {type = "number", default = 0, group = "Rendering"}
}})
function Render:draw(context) return false end
return Render
