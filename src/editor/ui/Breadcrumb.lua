local Theme = require("editor.Theme")
local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Fonts = require("editor.Fonts")
local SEPARATOR = " > "
local Breadcrumb = setmetatable({}, { __index = Widget })
Breadcrumb.__index = Breadcrumb

function Breadcrumb.new(onSelect)
    local self = setmetatable(Widget.new(), Breadcrumb)
    self.path, self.onSelect = "Assets", onSelect
    self.hover = {}
    return self
end

function Breadcrumb:update(dt)
    local x, y = love.mouse.getPosition()
    local inside = self.visible and self.enabled and self:containsPoint(x, y)
    local hover = {}
    for _, item in ipairs(self:items()) do
        local target = not item.current and inside and Ui.contains(x, y, item) and 1 or 0
        local amount = self.hover[item.reference] or 0
        -- 프레임 수가 아닌 경과 시간으로 보간해 배경이 부드럽게 나타나고 사라지게 한다.
        local rate = 1 - math.exp(-(target == 1 and 18 or 14) * dt)
        hover[item.reference] = amount + (target - amount) * rate
    end
    self.hover = hover
end

function Breadcrumb:items()
    local result, reference, left = {}, "", self.x + Ui.METRICS.contentPaddingX
    local font = love.graphics.getFont()
    for name in self.path:gmatch("[^/]+") do
        reference = reference == "" and name or reference .. "/" .. name
        local current = reference == self.path
        local width = (current and Fonts.boldFor(font) or font):getWidth(name)
        result[#result + 1] = { label = name, reference = reference, current = current, x = left,
            y = self.y + 2, w = width, h = self.height - 4 }
        left = left + width + font:getWidth(SEPARATOR)
    end
    return result
end

function Breadcrumb:draw()
    love.graphics.push("all")
    love.graphics.intersectScissor(self.x, self.y, self.width, self.height)
    for i, item in ipairs(self:items()) do
        if i > 1 then Ui.text(SEPARATOR, item.x - love.graphics.getFont():getWidth(SEPARATOR), self.y + 7) end
        local amount = not item.current and self.hover[item.reference] or 0
        if amount > 0.005 then
            Theme.setColor(love.mouse.isDown(1) and amount > 0.5 and "selection" or "hover", amount * 0.85)
            love.graphics.rectangle("fill", item.x, item.y, item.w, item.h, 4, 4)
        end
        local font = love.graphics.getFont()
        Ui.text(item.label, item.x, item.y + (item.h - font:getHeight()) / 2,
            item.w, item.current and Theme.color("text") or Theme.mix("textMuted", "text", amount), item.current)
        Ui.hint(item, item.current and "Current folder: " .. item.reference or "Open folder " .. item.reference .. ".")
    end
    love.graphics.pop()
end

function Breadcrumb:dispatch(event, x, y, button)
    if event ~= "mousepressed" then return false end
    if button == 1 then
        for _, item in ipairs(self:items()) do
            if Ui.contains(x, y, item) then
                if not item.current then self.onSelect(item.reference) end
                break
            end
        end
    end
    return true
end

return Breadcrumb
