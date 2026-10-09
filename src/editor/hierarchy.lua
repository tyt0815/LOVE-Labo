local Theme = require("editor.theme")
local UI = require("editor.ui")
local Hierarchy = {}
Hierarchy.__index = Hierarchy

local DEFAULT_WIDTH = 300
local HEADER_HEIGHT = 36 + UI.metrics.contentPaddingY
local ROW_HEIGHT = 24

function Hierarchy.new(level, width)
    local self = setmetatable({}, Hierarchy)

    self.level = level
    self.width = width or DEFAULT_WIDTH

    return self
end

function Hierarchy:containsPoint(x, y)
    local top = self.y or 0
    return x >= 0 and x < self.width and y >= top
        and (not self.height or y < top + self.height)
end

function Hierarchy:getLObjectAtPosition(x, y)
    if not self.level or not self:containsPoint(x, y) then
        return nil
    end

    y = y - (self.y or 0)
    if y < HEADER_HEIGHT then
        return nil
    end

    local index = math.floor((y - HEADER_HEIGHT) / ROW_HEIGHT) + 1
    return self.level.lobjects[index]
end

function Hierarchy:draw(selectedLObject)
    local _, height = love.graphics.getDimensions()
    height = self.height or height
    local top = self.y or 0

    love.graphics.push("all")
    love.graphics.setScissor(0, top, self.width, height)

    local UI = require("editor.ui")
    UI.panel(0, top, self.width, height)
    UI.panelHeading("Hierarchy", 0, top, self.width)
    love.graphics.intersectScissor(6, top + 6, self.width - 12, math.max(0, height - 12))

    if self.level then
        for i, lobject in ipairs(self.level.lobjects) do
            local rowY = top + HEADER_HEIGHT + (i - 1) * ROW_HEIGHT

            if rowY >= top + height then
                break
            end

            if lobject == selectedLObject then
                UI.selection(0, rowY, self.width, ROW_HEIGHT)
            end

            local displayId = lobject.authoringId or i

            Theme.setColor("text")
            love.graphics.print("LObject " .. displayId, UI.metrics.contentPaddingX, rowY + 4)
        end
    end

    love.graphics.pop()
end

return Hierarchy
