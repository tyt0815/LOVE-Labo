local Widget = require("editor.ui.widget")
local UI = require("editor.ui")
local Breadcrumb = setmetatable({}, { __index = Widget })
Breadcrumb.__index = Breadcrumb

function Breadcrumb.new(onSelect)
    local self = setmetatable(Widget.new(), Breadcrumb)
    self.path, self.onSelect = "Assets", onSelect
    return self
end

function Breadcrumb:items()
    local result, reference, left = {}, "", self.x + 8
    local font = love.graphics.getFont()
    for name in self.path:gmatch("[^/]+") do
        reference = reference == "" and name or reference .. "/" .. name
        local width = math.min(font:getWidth(name) + 24, math.max(80, self.width * 0.5))
        result[#result + 1] = { label = name, reference = reference, x = left,
            y = self.y + 2, w = width, h = self.height - 4 }
        left = left + width + 16
    end
    return result
end

function Breadcrumb:draw()
    love.graphics.push("all")
    love.graphics.intersectScissor(self.x, self.y, self.width, self.height)
    love.graphics.setColor(0.13, 0.15, 0.19, 1)
    love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
    for i, item in ipairs(self:items()) do
        if i > 1 then UI.text("/", item.x - 12, self.y + 7) end
        UI.button(item.label, item, item.reference == self.path)
    end
    love.graphics.pop()
end

function Breadcrumb:dispatch(event, x, y, button)
    if event ~= "mousepressed" then return false end
    if button == 1 then
        for _, item in ipairs(self:items()) do
            if UI.contains(x, y, item) then self.onSelect(item.reference); break end
        end
    end
    return true
end

return Breadcrumb
