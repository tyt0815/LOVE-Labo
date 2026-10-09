local Theme = require("editor.Theme")
local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Dropdown = setmetatable({}, { __index = Widget })
Dropdown.__index = Dropdown

function Dropdown.new(root, options, value, onChange)
    local self = setmetatable(Widget.new(), Dropdown)
    self.root, self.options, self.value, self.onChange = root, options, value, onChange
    self.menu = Widget.new({
        draw = function(widget)
            if self.beginMenuDraw then self.beginMenuDraw() end
            Theme.setColor("surface")
            love.graphics.rectangle("fill", widget.x, widget.y, widget.width, widget.height)
            for row = 1, self.visibleRows do
                local index = row + self.scroll
                local option = self.options[index]
                if option then
                    local rect = {x = widget.x + 3, y = widget.y + (row - 1) * (self.rowHeight or 30) + 3,
                        w = widget.width - 6, h = (self.rowHeight or 30) - 2}
                    if self.drawOption then self.drawOption(option, rect, index == self.highlight)
                    else Ui.button(option.label, rect, index == self.highlight, "Select " .. option.label .. ". Enter: apply.") end
                end
            end
        end,
        mousepressed = function(widget, x, y, button)
            if button ~= 1 then return true end
            local index = math.floor((y - widget.y - 3) / (self.rowHeight or 30)) + 1 + self.scroll
            local option = self.options[index]
            if option then self:setValue(option.value) end
            self.root:dismissPopup()
            return true
        end,
        keypressed = function(_, key)
            if #self.options == 0 then return true end
            if key == "down" then self.highlight = self.highlight % #self.options + 1
            elseif key == "up" then self.highlight = (self.highlight - 2) % #self.options + 1
            elseif key == "return" or key == "kpenter" then
                self:setValue(self.options[self.highlight].value)
                self.root:dismissPopup()
            end
            self.scroll = math.max(math.min(self.scroll, self.highlight - 1), self.highlight - self.visibleRows)
            return true
        end,
        wheelmoved = function(_, _, _, amount)
            self.scroll = math.floor(math.max(0, math.min(#self.options - self.visibleRows, self.scroll - amount * 3)))
            return true
        end
    })
    return self
end

function Dropdown:setValue(value)
    for _, option in ipairs(self.options) do
        if option.value == value then
            if self.onChange and self.onChange(value) == false then return false end
            self.value = value
            return true
        end
    end
    return false
end

function Dropdown:draw()
    local label = ""
    for _, option in ipairs(self.options) do if option.value == self.value then label = option.label end end
    if self.flat then
        Ui.button(self.label or label, {x = self.x, y = self.y, w = self.width, h = self.height},
            self.root.popup == self.menu, self.hint, true)
        return
    end
    Ui.button("", {x = self.x, y = self.y, w = self.width, h = self.height}, false,
        self.hint or "Open the choices. Up/Down: select. Enter: apply. Esc: close.")
    local divider = self.x + self.width - 28
    Ui.text(label, self.x + 10, self.y + (self.height - love.graphics.getFont():getHeight()) / 2,
        math.max(0, self.width - 46))
    love.graphics.push("all")
    Theme.setColor("border")
    love.graphics.line(divider, self.y + 5, divider, self.y + self.height - 5)
    Theme.setColor("textMuted")
    love.graphics.setLineWidth(1.5)
    local cx, cy = divider + 14, self.y + self.height / 2
    love.graphics.line(cx - 4, cy - 2, cx, cy + 2, cx + 4, cy - 2)
    love.graphics.pop()
end

function Dropdown:dispatch(event, ...)
    if event ~= "mousepressed" then return false end
    local _, _, button = ...
    if button ~= 1 then return true end
    local windowHeight = love.graphics.getHeight()
    if #self.options == 0 then return true end
    self.highlight = 1
    for i, option in ipairs(self.options) do if option.value == self.value then self.highlight = i end end
    local rowHeight = self.rowHeight or 30
    self.visibleRows = math.max(1, math.min(#self.options, 10, math.floor((windowHeight - 16) / rowHeight)))
    self.scroll = math.max(0, self.highlight - self.visibleRows)
    local height = self.visibleRows * rowHeight + 6
    local top = self.y + self.height + 2
    if top + height > windowHeight then top = math.max(0, math.min(windowHeight - height, self.y - height - 2)) end
    local width = math.min(love.graphics.getWidth(), self.menuWidth or self.width)
    self.menu:setBounds(math.min(self.x, love.graphics.getWidth() - width), top, width, height)
    self.root:setPopup(self.menu)
    return true
end

return Dropdown
