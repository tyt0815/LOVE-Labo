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
    local inset = Ui.METRICS.panelGap / 2
    if width <= inset * 2 or height <= inset * 2 then return nil end
    return require("core.RenderPipeline").primaryViewport(world, x + inset, y + inset, width - inset * 2, height - inset * 2)
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
        local vx, vy, width, height = self:getViewport()
        local inset = Ui.METRICS.panelGap / 2
        return require("core.RenderPipeline").pointer(world, kind, x, y, button, dx, dy,
            function(_, reference) return self.spriteAssets and self.spriteAssets:image(reference) end,
            {x = vx + inset, y = vy + inset, width = width - inset * 2, height = height - inset * 2})
    end)
    if not called then return false, tostring(ok) end
    return ok, result
end

function GameView:drawRuntimeLObjects(world)
    self.world = world
    local viewport = self:runtimeViewport(world)
    if not viewport then return end
    local x, y, width, height = self:getViewport()
    local inset = Ui.METRICS.panelGap / 2
    require("core.RenderPipeline").draw(world, function(reference) return self.spriteAssets and self.spriteAssets:image(reference) end,
        x + inset, y + inset, width - inset * 2, height - inset * 2)
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

    local ok, err = require("core.GraphicsScope").call(function()
        -- 투영 제공자·디버그 출력 오류도 패널의 그래픽 상태를 복구한 뒤 전달한다.
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
            local inset = Ui.METRICS.panelGap / 2
            love.graphics.rectangle("fill", viewportX + inset, viewportY + inset, width - inset * 2, height - inset * 2)
            Theme.setColor("gameBackground")
            love.graphics.rectangle("fill", viewport.x, viewport.y, viewport.width, viewport.height)
            love.graphics.intersectScissor(viewport.x, viewport.y, viewport.width, viewport.height)
        end
        if world and viewport then
            self:drawRuntimeLObjects(world)
            if world.debug.drawShapes then
                world.debug:drawShapes(function(x, y) return self:worldToScreen(x, y) end)
                world.debug:drawScreens(viewport.x + 6, viewport.y + 6, math.max(0, viewport.width - 12), math.max(0, viewport.height - 12))
            end
        end
    end)

    if not ok then error(err, 0) end
end

return GameView
