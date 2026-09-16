local Inspector = {}
Inspector.__index = Inspector

local DEFAULT_WIDTH = 240

function Inspector.new(level, width)
    local self = setmetatable({}, Inspector)

    self.level = level
    self.width = width or DEFAULT_WIDTH

    return self
end

function Inspector:containsPoint(x, y, windowWidth)
    if windowWidth == nil then
        return false
    end

    local left = windowWidth - self.width
    return x >= left and x < windowWidth and y >= 0
end

function Inspector:getLObjectIndex(target)
    if not self.level or not target then
        return nil
    end

    for i, lobject in ipairs(self.level.lobjects) do
        if lobject == target then
            return i
        end
    end

    return nil
end

function Inspector:draw(selectedLObject)
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local left = windowWidth - self.width

    love.graphics.push("all")

    -- 현재는 별도 Docking/Layout system 없이 오른쪽 고정 폭 패널로 시작한다.
    love.graphics.setColor(0.11, 0.12, 0.14, 1.0)
    love.graphics.rectangle("fill", left, 0, self.width, windowHeight)

    love.graphics.setColor(0.28, 0.29, 0.33, 1.0)
    love.graphics.line(left, 0, left, windowHeight)

    love.graphics.setColor(0.92, 0.92, 0.94, 1.0)
    love.graphics.print("Inspector", left + 12, 10)

    if not selectedLObject then
        love.graphics.setColor(0.62, 0.63, 0.67, 1.0)
        love.graphics.print("No selection", left + 12, 44)
        love.graphics.pop()
        return
    end

    local index = self:getLObjectIndex(selectedLObject)

    love.graphics.setColor(0.86, 0.87, 0.90, 1.0)

    if index then
        love.graphics.print("LObject " .. index, left + 12, 44)
    else
        love.graphics.print("LObject", left + 12, 44)
    end

    love.graphics.setColor(0.72, 0.74, 0.78, 1.0)
    love.graphics.print("Transform", left + 12, 78)

    local transform = selectedLObject.transform

    if transform then
        love.graphics.setColor(0.86, 0.87, 0.90, 1.0)
        love.graphics.print(
            string.format("X: %.2f", transform.x),
            left + 20,
            106
        )
        love.graphics.print(
            string.format("Y: %.2f", transform.y),
            left + 20,
            130
        )
    end

    love.graphics.pop()
end

return Inspector
