local Engine = require("Engine")
local Transform = Engine.Transform
local Camera = Engine.Script:extend({scriptType = "Camera", properties = {
    viewWidth = {type = "number", default = 1280, group = "Camera"},
    viewHeight = {type = "number", default = 720, group = "Camera"},
    zoom = {type = "number", default = 1, group = "Camera"}
}})
function Camera:getViewSize()
    assert(Transform.finite(self.viewWidth) and self.viewWidth > 0 and Transform.finite(self.viewHeight) and self.viewHeight > 0
        and Transform.finite(self.zoom) and self.zoom > 0, "Camera size and zoom must be positive")
    return self.viewWidth / self.zoom, self.viewHeight / self.zoom
end
function Camera:getViewTransform()
    local world = self.owner:getWorldTransform()
    local rotation, object = 0, self.owner
    while object do rotation = rotation + (object.transform and object.transform.rotation or 0); object = object.parent end
    return {x = world.x, y = world.y, rotation = Transform.normalizeRotation(rotation), scaleX = 1, scaleY = 1}
end
function Camera:getProjection()
    local width, height = self:getViewSize()
    return {transform = self:getViewTransform(), width = width, height = height}
end
function Camera:drawEditor(context)
    local width, height = self:getViewSize()
    local transform, points = self:getViewTransform(), {}
    for _, corner in ipairs({{-width / 2, -height / 2}, {width / 2, -height / 2}, {width / 2, height / 2}, {-width / 2, height / 2}}) do
        local x, y = Transform.point(transform, corner[1], corner[2])
        points[#points + 1] = x; points[#points + 1] = y
    end
    context:polygon(points, {color = {context.color[1] * 255, context.color[2] * 255, context.color[3] * 255}})
end
return Camera
