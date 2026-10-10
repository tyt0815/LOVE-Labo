local Theme = require("editor.Theme")
local Ui = require("editor.Ui")
local GameView = {}
GameView.__index = GameView

local RUNTIME_LOBJECT_SIZE = 16

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

function GameView:worldToScreen(x, y)
    local viewportX, viewportY, width, height = self:getViewport()
    if width <= 0 or height <= 0 then return viewportX, viewportY end
    return require("core.Viewport").new(self.world, viewportX, viewportY, width, height):worldToScreen(x, y)
end
function GameView:dispatchPointer(world, kind, x, y, button, dx, dy)
    self.world = world
    local left, top, width, height = self:getViewport()
    if width <= 0 or height <= 0 then return true, {consumed = false, targets = {}} end
    local called, ok, result = pcall(function()
        return require("core.Viewport").new(world, left, top, width, height):dispatchPointer(world, kind, x, y, button, dx, dy,
            function(_, reference) return self.spriteAssets and self.spriteAssets:image(reference) end)
    end)
    if not called then return false, tostring(ok) end
    return ok, result
end

function GameView:drawRuntimeLObjects(world)
    local halfSize =
        RUNTIME_LOBJECT_SIZE * 0.5

    self.world = world
    local left, top, width, height = self:getViewport()
    local viewport = require("core.Viewport").new(world, left, top, width, height)
    local drawn = require("core.Renderer").drawWorld(world, function(reference) return self.spriteAssets and self.spriteAssets:image(reference) end, viewport)
    for _, lobject in ipairs(world.lobjects) do
        if not drawn[lobject] and #lobject:getComponentOrder() == 1 and lobject.rootComponent.isDefaultRoot then
            local transform = lobject:getWorldTransform()
            local screenX, screenY = self:worldToScreen(transform.x, transform.y)
            -- 표시할 Sprite가 없는 객체도 위치를 확인할 수 있게 한다.
            Theme.setColor("text")
            love.graphics.rectangle("fill", screenX - halfSize, screenY - halfSize,
                RUNTIME_LOBJECT_SIZE, RUNTIME_LOBJECT_SIZE)
        end
    end
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
    love.graphics.intersectScissor(viewportX + 12, viewportY + 12, math.max(0, width - 24), math.max(0, height - 24))

    if world then
        local ok, err = pcall(self.drawRuntimeLObjects, self, world)
        if not ok then love.graphics.pop(); error(err, 0) end
    end

    Theme.setColor("text")

    Ui.panelHeading(
        "Game View  [F5: Stop]",
        viewportX,
        viewportY,
        width
    )

    love.graphics.pop()
end

return GameView
