local Theme = require("editor.theme")
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
        and (not self.height or y < self.height)
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
    height = self.height or height

    love.graphics.push("all")
    love.graphics.setScissor(0, 0, self.width, height)

    local UI = require("editor.ui")
    UI.panel(0, 0, self.width, height)
    UI.panelTitle("Hierarchy", 18, 12, self.width - 36)
    Theme.setColor("border")
    love.graphics.line(12, 35, self.width - 12, 35)
    love.graphics.intersectScissor(6, 6, self.width - 12, math.max(0, height - 12))

    if self.level then
        for i, lobject in ipairs(self.level.lobjects) do
            local rowY = HEADER_HEIGHT + (i - 1) * ROW_HEIGHT

            if rowY >= height then
                break
            end

            if lobject == selectedLObject then
                Theme.setColor("selection")
                love.graphics.rectangle("fill", 0, rowY, self.width, ROW_HEIGHT)
            end

            local displayId = lobject.authoringId or i

            Theme.setColor("text")
            love.graphics.print("LObject " .. displayId, 12, rowY + 4)
        end
    end

    love.graphics.pop()
end

return Hierarchy
