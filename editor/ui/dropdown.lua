local Theme = require("editor.theme")
local Widget = require("editor.ui.widget")
local UI = require("editor.ui")
local Dropdown = setmetatable({}, { __index = Widget })
Dropdown.__index = Dropdown

function Dropdown.new(root, options, value, onChange)
    local self = setmetatable(Widget.new(), Dropdown)
    self.root, self.options, self.value, self.onChange = root, options, value, onChange
    self.menu = Widget.new({
        draw = function(widget)
            Theme.setColor("surface")
            love.graphics.rectangle("fill", widget.x, widget.y, widget.width, widget.height)
            for i, option in ipairs(self.options) do
                UI.button(option.label, {x = widget.x + 3, y = widget.y + (i - 1) * 30 + 3,
                    w = widget.width - 6, h = 28}, i == self.highlight)
            end
        end,
        mousepressed = function(widget, x, y, button)
            if button ~= 1 then return true end
            local index = math.floor((y - widget.y) / 30) + 1
            local option = self.options[index]
            if option then self:setValue(option.value) end
            self.root:dismissPopup()
            return true
        end,
        keypressed = function(_, key)
            if key == "down" then self.highlight = self.highlight % #self.options + 1
            elseif key == "up" then self.highlight = (self.highlight - 2) % #self.options + 1
            elseif key == "return" or key == "kpenter" then
                self:setValue(self.options[self.highlight].value)
                self.root:dismissPopup()
            end
            return true
        end
    })
    return self
end

function Dropdown:setValue(value)
    for _, option in ipairs(self.options) do
        if option.value == value then
            self.value = value
            if self.onChange then self.onChange(value) end
            return true
        end
    end
    return false
end

function Dropdown:draw()
    local label = ""
    for _, option in ipairs(self.options) do if option.value == self.value then label = option.label end end
    UI.button(label .. "  v", {x = self.x, y = self.y, w = self.width, h = self.height})
end

function Dropdown:dispatch(event, ...)
    if event ~= "mousepressed" then return false end
    local _, _, button = ...
    if button ~= 1 then return true end
    local windowHeight = love.graphics.getHeight()
    for i, option in ipairs(self.options) do if option.value == self.value then self.highlight = i end end
    local height = #self.options * 30 + 6
    local top = self.y + self.height + 2
    if top + height > windowHeight then top = self.y - height - 2 end
    self.menu:setBounds(self.x, top, self.width, height)
    self.root:setPopup(self.menu)
    return true
end

return Dropdown
