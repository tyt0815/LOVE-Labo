local Transform = require("core.Transform")
local Viewport = {}
Viewport.__index = Viewport
function Viewport.new(world, x, y, width, height, view)
    assert(Transform.finite(width) and width > 0 and Transform.finite(height) and height > 0, "Invalid viewport size")
    assert(Transform.finite(x or 0) and Transform.finite(y or 0), "Invalid viewport origin")
    local self = setmetatable({x = x or 0, y = y or 0, width = width, height = height, scale = 1}, Viewport)
    if not view and world then
        local views = require("core.Rendering").views(world)
        for index = #views, 1, -1 do
            if views[index].target == require("core.Rendering").screen then view = views[index]; break end
        end
    end
    self.view, self.projection = view, view and view:getProjection()
    self.transform = {x = 0, y = 0}
    if self.projection then
        local w, h = self.projection.width, self.projection.height
        self.scale = math.min(width / w, height / h)
        self.transform = self.projection.transform
        self.contentWidth, self.contentHeight = w * self.scale, h * self.scale
        -- 화면 공간 UI도 레터박스를 제외한 실제 게임 화면을 기준으로 배치한다.
        self.x, self.y = self.x + (width - self.contentWidth) / 2, self.y + (height - self.contentHeight) / 2
        self.width, self.height = self.contentWidth, self.contentHeight
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
    local context = {image = image, viewport = self, projection = self.projection, view = self.view, target = self.view and self.view.target,
        transform = function(_, script) return script:getWorldTransform() end}
    context.transform = function(_, script) return script:getWorldTransform(context) end
    context.withScreen = function(_, callback) return require("core.Rendering").withScreen(context, callback) end
    return context
end
function Viewport:dispatchPointer(world, kind, x, y, button, dx, dy, image)
    local wx, wy = self:screenToWorld(x, y)
    local px, py = self:screenToWorld(x - (dx or 0), y - (dy or 0))
    local context = self:context(image)
    context.screenX, context.screenY = x - self.x, y - self.y
    context.screenDx, context.screenDy = dx or 0, dy or 0
    context.worldVisible = self:containsWorldScreen(x, y)
    return world:dispatchPointer(kind, wx, wy, button, wx - px, wy - py, context)
end
return Viewport
