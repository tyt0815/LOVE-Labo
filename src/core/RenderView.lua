local Transform = require("core.Transform")
local View = {}
View.__index = View
function View.validCamera(world, camera)
    if camera == nil or camera == false then return true end
    return not not (type(camera) == "table" and camera.camera == true and type(camera.getViewSize) == "function"
        and type(camera.getViewTransform) == "function" and camera.owner and camera.owner:getWorld() == world
        and camera.owner.scripts[camera.id] == camera and not camera.hasUnloaded)
end
function View.new(world, options)
    local self = setmetatable({world = world, owner = options.owner, enabled = options.enabled ~= false, includeWorld = options.includeWorld ~= false,
        includeScreen = options.includeScreen ~= false, input = options.input ~= false, filter = options.filter,
        clearColor = options.clearColor == nil and {0, 0, 0, 1} or options.clearColor,
        pointerCaptures = {}}, View)
    assert(self.filter == nil or type(self.filter) == "function", "View filter must be a function")
    assert(not self.owner or type(self.owner) == "table" and type(self.owner.getWorld) == "function" and self.owner:getWorld() == world, "View owner must be a script in this World")
    if self.clearColor ~= false then
        assert(type(self.clearColor) == "table" and #self.clearColor == 4, "Expected RGBA clear color or false")
        for _, channel in ipairs(self.clearColor) do assert(Transform.finite(channel) and channel >= 0 and channel <= 1, "Invalid clear color") end
        self.clearColor = {unpack(self.clearColor)}
    end
    self:setCamera(options.camera)
    self:setTarget(options.target)
    self:setViewport(options.viewport)
    self:setOrder(options.order or 0)
    world.renderViews = world.renderViews or {}
    world.nextViewId = (world.nextViewId or 0) + 1
    self.id = world.nextViewId
    world.renderViews[#world.renderViews + 1] = self
    return self
end
function View:setCamera(camera)
    assert(not self.released and View.validCamera(self.world, camera), "Camera must belong to the View's World")
    self.camera = camera or nil
end
function View:setTarget(target)
    local screen = require("core.Rendering").screen
    target = target or screen
    assert(not self.released and (target == screen or getmetatable(target) == require("core.RenderTarget")
        and target.world == self.world and not target.released), "Render target must belong to the View's World")
    self.target = target
end
function View:setViewport(rect)
    assert(not self.released, "View is released")
    if rect == nil then self.viewport = nil; return end
    assert(type(rect) == "table" and Transform.finite(rect.x) and Transform.finite(rect.y)
        and Transform.finite(rect.width) and Transform.finite(rect.height) and rect.x >= 0 and rect.y >= 0
        and rect.width > 0 and rect.height > 0, "Invalid View viewport")
    self.viewport = {x = rect.x, y = rect.y, width = rect.width, height = rect.height}
end
function View:setOrder(order)
    assert(not self.released and Transform.finite(order), "Invalid View order")
    self.order = order
end
function View:setEnabled(enabled)
    assert(not self.released and type(enabled) == "boolean", "Expected View enabled boolean")
    self.enabled = enabled
    if not enabled then self.pointerCaptures = {} end
end
function View:isActive()
    -- 호환 출력은 저장 당시 참조가 아니라 과거 World의 자동 대체 규칙을 따른다.
    if self == self.world.legacyView and self.world.legacyCameraSelection and not self.world.disposed then
        self.camera = self.world:getActiveCamera()
    end
    local active = not self.released and not self.world.disposed and self.enabled
        and (not self.owner or not self.owner.hasUnloaded and self.owner.enabled ~= false and self.owner:getWorld() == self.world)
        and View.validCamera(self.world, self.camera)
        and not self.target.released
    -- 비활성 중 놓친 release가 재활성화 뒤의 입력을 가로채지 않게 한다.
    if not active then self.pointerCaptures = {} end
    return active
end
function View:includes(script, screen)
    return (screen and self.includeScreen or not screen and self.includeWorld)
        and (not self.filter or self.filter(script) == true)
end
function View:release()
    if self.released then return end
    self.released, self.pointerCaptures = true, {}
    for index, view in ipairs(self.world.renderViews) do
        if view == self then table.remove(self.world.renderViews, index); break end
    end
end
return View
