local Theme = require("editor.Theme")
local Ui = require("editor.Ui")
local GameView = {}
GameView.__index = GameView

function GameView.new()
    local self = setmetatable({}, GameView)

    self.viewportX = 0
    self.viewportY = 0
    self.viewportWidth = nil
    self.viewportHeight = nil

    return self
end

function GameView:setViewport(x, y, width, height)
    self.viewportX = x
    self.viewportY = y
    self.viewportWidth = math.max(0, width)
    self.viewportHeight = math.max(0, height)
end

function GameView:getViewport()
    if self.viewportWidth ~= nil
        and self.viewportHeight ~= nil
    then
        return self.viewportX,
            self.viewportY,
            self.viewportWidth,
            self.viewportHeight
    end

    local width, height =
        love.graphics.getDimensions()

    return 0, 0, width, height
end

function GameView:runtimeViewport(world)
    local x, y, width, height = self:getViewport()
    if width <= 24 or height <= 48 then return nil end
    return require("core.Viewport").new(world, x + 12, y + 36, width - 24, height - 48)
end
function GameView:worldToScreen(x, y)
    local viewport = self:runtimeViewport(self.world)
    if not viewport then return self.viewportX, self.viewportY end
    return viewport:worldToScreen(x, y)
end
function GameView:dispatchPointer(world, kind, x, y, button, dx, dy)
    self.world = world
    local called, ok, result = pcall(function()
        local viewport = self:runtimeViewport(world)
        if not viewport then return true, {consumed = false, targets = {}} end
        return viewport:dispatchPointer(world, kind, x, y, button, dx, dy,
            function(_, reference) return self.spriteAssets and self.spriteAssets:image(reference) end)
    end)
    if not called then return false, tostring(ok) end
    return ok, result
end

function GameView:drawRuntimeLObjects(world)
    self.world = world
    local viewport = self:runtimeViewport(world)
    if not viewport then return end
    require("core.Renderer").drawWorld(world, function(reference) return self.spriteAssets and self.spriteAssets:image(reference) end, viewport)
end

function GameView:draw(world)
    self.world = world
    local viewportX,
        viewportY,
        width,
        height = self:getViewport()

    if width <= 0 or height <= 0 then
        return
    end

    love.graphics.push("all")

    -- Game View rendering이 Editor panel 영역으로 새지 않도록
    -- 자신의 viewport 안으로 graphics state를 제한한다.
    love.graphics.setScissor(
        viewportX,
        viewportY,
        width,
        height
    )

    require("editor.Ui").panel(viewportX, viewportY, width, height, "gameBackground")
    local viewport = self:runtimeViewport(world)
    if viewport then
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", viewportX + 12, viewportY + 36, width - 24, height - 48)
        Theme.setColor("gameBackground")
        love.graphics.rectangle("fill", viewport.x, viewport.y, viewport.width, viewport.height)
        love.graphics.push("all")
        love.graphics.intersectScissor(viewport.x, viewport.y, viewport.width, viewport.height)
    end
    if world and viewport then
        local ok, err = pcall(self.drawRuntimeLObjects, self, world)
        if not ok then love.graphics.pop(); love.graphics.pop(); error(err, 0) end
        if world.debug.drawShapes then
            world.debug:drawShapes(function(x, y) return self:worldToScreen(x, y) end)
            world.debug:drawScreens(viewport.x + 6, viewport.y + 6, math.max(0, viewport.width - 12), math.max(0, viewport.height - 12))
        end
    end
    if viewport then love.graphics.pop() end

    Theme.setColor("text")

    Ui.panelHeading(
        "Game View",
        viewportX,
        viewportY,
        width
    )

    love.graphics.pop()
end

return GameView
