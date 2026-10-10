local Transform = require("core.Transform")
local Camera = require("core.SceneComponent"):extend({componentType = "CameraComponent", properties = {
    enabled = {type = "boolean", default = true, group = "Camera"},
    viewWidth = {type = "number", default = 1280, group = "Camera"},
    viewHeight = {type = "number", default = 720, group = "Camera"},
    zoom = {type = "number", default = 1, group = "Camera"}
}})
function Camera:getViewSize()
    local p = self.properties
    assert(Transform.finite(p.viewWidth) and p.viewWidth > 0 and Transform.finite(p.viewHeight) and p.viewHeight > 0
        and Transform.finite(p.zoom) and p.zoom > 0, "Camera size and zoom must be positive")
    return p.viewWidth / p.zoom, p.viewHeight / p.zoom
end
function Camera:getViewTransform()
    local world = self:getWorldTransform()
    local rotation, component = 0, self
    while component do
        if component.transform then rotation = rotation + (component.transform.rotation or 0) end
        component = require("core.CoordinateSpace").parent(component)
    end
    -- 카메라의 화면 크기는 zoom이 담당하며 객체 스케일과 X/Y 기울기는 투영에 적용하지 않는다.
    return {x = world.x, y = world.y, rotation = Transform.normalizeRotation(rotation), scaleX = 1, scaleY = 1}
end
return Camera
