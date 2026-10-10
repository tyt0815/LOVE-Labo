local Transform = require("core.Transform")
local Viewport = {}
Viewport.__index = Viewport
function Viewport.new(world, x, y, width, height)
    assert(Transform.finite(width) and width > 0 and Transform.finite(height) and height > 0, "Invalid viewport size")
    assert(Transform.finite(x or 0) and Transform.finite(y or 0), "Invalid viewport origin")
    local self = setmetatable({x = x or 0, y = y or 0, width = width, height = height, scale = 1}, Viewport)
    self.camera = world and world:getActiveCamera()
    self.transform = {x = 0, y = 0}
    if self.camera then
        local w, h = self.camera:getViewSize()
        self.scale = math.min(width / w, height / h)
        self.transform = self.camera:getViewTransform()
        self.contentWidth, self.contentHeight = w * self.scale, h * self.scale
    else self.contentWidth, self.contentHeight = width, height end
    return self
end
function Viewport:worldToScreen(x, y)
    local localX, localY = Transform.inversePoint(self.transform, x, y)
    return self.x + self.width / 2 + localX * self.scale, self.y + self.height / 2 + localY * self.scale
end
function Viewport:screenToWorld(x, y)
    return Transform.point(self.transform, (x - self.x - self.width / 2) / self.scale, (y - self.y - self.height / 2) / self.scale)
end
function Viewport:containsWorldScreen(x, y)
    return math.abs(x - self.x - self.width / 2) <= self.contentWidth / 2
        and math.abs(y - self.y - self.height / 2) <= self.contentHeight / 2
end
function Viewport:context(image)
    return {image = image, viewport = self, transform = function(_, component) return require("core.CoordinateSpace").transform(component) end}
end
function Viewport:dispatchPointer(world, kind, x, y, button, dx, dy, image)
    local wx, wy = self:screenToWorld(x, y)
    local px, py = self:screenToWorld(x - (dx or 0), y - (dy or 0))
    local context = self:context(image)
    context.screenX, context.screenY = x - self.x - self.width / 2, y - self.y - self.height / 2
    context.screenDx, context.screenDy = dx or 0, dy or 0
    context.worldVisible = self:containsWorldScreen(x, y)
    return world:dispatchPointer(kind, wx, wy, button, wx - px, wy - py, context)
end
return Viewport
