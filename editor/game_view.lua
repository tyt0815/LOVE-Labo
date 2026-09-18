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
    -- 아직 Runtime Camera가 없으므로 world origin을
    -- Game View viewport의 좌상단에 1:1로 대응시킨다.
    -- Scene View의 editor camera/zoom은 Runtime에 공유하지 않는다.
    return self.viewportX + x,
        self.viewportY + y
end

function GameView:drawRuntimeLObjects(world)
    local halfSize =
        RUNTIME_LOBJECT_SIZE * 0.5

    for _, lobject in ipairs(world.lobjects) do
        local transform = lobject.transform

        local screenX, screenY =
            self:worldToScreen(
                transform.x,
                transform.y
            )

        -- 실제 game rendering Component가 생기기 전까지
        -- Runtime LObject의 존재/위치를 확인하기 위한 debug 표현이다.
        love.graphics.setColor(
            0.92,
            0.92,
            0.94,
            1.0
        )

        love.graphics.rectangle(
            "fill",
            screenX - halfSize,
            screenY - halfSize,
            RUNTIME_LOBJECT_SIZE,
            RUNTIME_LOBJECT_SIZE
        )
    end
end

function GameView:draw(world)
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

    love.graphics.setColor(
        0.035,
        0.04,
        0.05,
        1.0
    )

    love.graphics.rectangle(
        "fill",
        viewportX,
        viewportY,
        width,
        height
    )

    if world then
        self:drawRuntimeLObjects(world)
    end

    love.graphics.setColor(
        0.92,
        0.92,
        0.94,
        1.0
    )

    love.graphics.print(
        "Game View  [F5: Stop]",
        viewportX + 16,
        viewportY + 16
    )

    love.graphics.pop()
end

return GameView
