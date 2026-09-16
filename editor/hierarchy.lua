local Hierarchy = {}
Hierarchy.__index = Hierarchy

local DEFAULT_WIDTH = 220
local HEADER_HEIGHT = 36
local ROW_HEIGHT = 24

function Hierarchy.new(level, width)
    local self = setmetatable({}, Hierarchy)

    self.level = level
    self.width = width or DEFAULT_WIDTH

    return self
end

function Hierarchy:containsPoint(x, y)
    return x >= 0 and x < self.width and y >= 0
end

function Hierarchy:getLObjectAtPosition(x, y)
    if not self.level or not self:containsPoint(x, y) then
        return nil
    end

    if y < HEADER_HEIGHT then
        return nil
    end

    local index = math.floor((y - HEADER_HEIGHT) / ROW_HEIGHT) + 1
    return self.level.lobjects[index]
end

function Hierarchy:draw(selectedLObject)
    local _, height = love.graphics.getDimensions()

    love.graphics.push("all")

    -- 현재는 별도 Docking/Layout system 없이 고정 폭 패널로 시작한다.
    love.graphics.setColor(0.11, 0.12, 0.14, 1.0)
    love.graphics.rectangle("fill", 0, 0, self.width, height)

    love.graphics.setColor(0.28, 0.29, 0.33, 1.0)
    love.graphics.line(self.width, 0, self.width, height)

    love.graphics.setColor(0.92, 0.92, 0.94, 1.0)
    love.graphics.print("Hierarchy", 12, 10)

    if self.level then
        for i, lobject in ipairs(self.level.lobjects) do
            local rowY = HEADER_HEIGHT + (i - 1) * ROW_HEIGHT

            if rowY >= height then
                break
            end

            if lobject == selectedLObject then
                love.graphics.setColor(0.22, 0.28, 0.36, 1.0)
                love.graphics.rectangle("fill", 0, rowY, self.width, ROW_HEIGHT)
            end

            love.graphics.setColor(0.86, 0.87, 0.90, 1.0)
            love.graphics.print("LObject " .. i, 12, rowY + 4)
        end
    end

    love.graphics.pop()
end

return Hierarchy
