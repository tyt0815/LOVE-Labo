local Ui = require("editor.Ui")
local Edit = require("editor.ui.TextEdit")
local Ime = require("editor.ui.Ime")
local Picker = {}
Picker.__index = Picker
function Picker.new(root, rect, options, choose, pick)
    local self = setmetatable({root = root, rect = rect, options = options, choose = choose, pick = pick, text = "", handlers = {}, index = 1, previousRepeat = love.keyboard.hasKeyRepeat()}, Picker)
    self.field = {x = rect.x, y = rect.y, w = math.max(60, rect.w - 56), h = 26}
    Edit.begin(self, "", false); root:setPopup(self); love.keyboard.setTextInput(true); love.keyboard.setKeyRepeat(true)
    return self
end
function Picker:matches()
    local result = {}; for _, option in ipairs(self.options) do if option.label:lower():find(self.text:lower(), 1, true) then result[#result + 1] = option end end
    self.index = math.max(1, math.min(self.index, #result)); return result
end
function Picker:hitTest() return self end
function Picker:update() end
function Picker:apply(option)
    if option and self.choose(option.value) ~= false then self.root:dismissPopup() end
end
function Picker:listLayout()
    local matches = self:matches()
    local rows = math.min(8, #matches, math.max(1, math.floor((love.graphics.getHeight() - 56) / 26)))
    local top = self.rect.y + 28
    if top + rows * 26 > love.graphics.getHeight() then top = math.max(0, self.rect.y - rows * 26 - 2) end
    return top, rows, math.max(1, self.index - rows + 1)
end
function Picker:dispatch(event, ...)
    if event == "dismiss" or event == "cancel" then Ime.cancel(self); love.keyboard.setTextInput(false); love.keyboard.setKeyRepeat(self.previousRepeat)
    elseif event == "textinput" then self.text = Ime.input(self, self.text, ..., false)
    elseif event == "textedited" then Ime.edited(self, (...))
    elseif event == "keypressed" then
        local key = ...; if Ime.handlesKey(self, key) then return true end
        if Ime.endsComposition(key) or key == "return" then self.text = Ime.finish(self, self.text, false) end
        local matches = self:matches()
        if key == "return" then self:apply(matches[self.index])
        elseif key == "down" then self.index = math.min(#matches, self.index + 1)
        elseif key == "up" then self.index = math.max(1, self.index - 1)
        else self.text = Edit.key(self, self.text, key, false) end
    elseif event == "wheelmoved" then local _, _, amount = ...; self.index = math.max(1, math.min(#self:matches(), self.index - math.floor(amount * 3)))
    elseif event == "mousepressed" then
        local x, y, button = ...; if button ~= 1 then return true end
        if Ui.contains(x, y, self.field) then self.text = Ime.finish(self, self.text, false); Edit.press(self, self.text, self.field, x, false); return true, true
        elseif y >= self.rect.y and y < self.rect.y + 26 and x >= self.field.x + self.field.w and x < self.rect.x + self.rect.w - 26 then
            self.root:dismissPopup(); self.pick()
        else
            local top, rows, first = self:listLayout()
            if y >= top and y < top + rows * 26 and x >= self.rect.x and x < self.rect.x + self.rect.w then
                self:apply(self:matches()[first + math.floor((y - top) / 26)])
            else self.root:dismissPopup() end
        end
    elseif event == "mousemoved" then Edit.move(self, (...))
    elseif event == "mousereleased" then Edit.release(self) end
    return true
end
function Picker:draw()
    love.graphics.push("all")
    require("editor.Theme").setColor("surface"); love.graphics.rectangle("fill", self.rect.x, self.rect.y, self.rect.w, self.rect.h)
    Ui.field(self.text, self.field, true, self.composition, self)
    Ui.eyedropperButton({x = self.field.x + self.field.w, y = self.rect.y, w = 28, h = 26}, false)
    local x, y = self.rect.x + self.rect.w - 13, self.rect.y + 13
    Ui.button("", {x = x - 13, y = y - 13, w = 26, h = 26}, false, "Cancel script selection", true)
    require("editor.Theme").setColor("textMuted"); love.graphics.setLineWidth(1.5)
    love.graphics.line(x - 4, y - 4, x + 4, y + 4); love.graphics.line(x - 4, y + 4, x + 4, y - 4)
    local matches = self:matches()
    local top, rows, first = self:listLayout()
    for row = first, math.min(#matches, first + rows - 1) do
        Ui.button(matches[row].label, {x = self.rect.x, y = top + (row - first) * 26, w = self.rect.w, h = 26}, row == self.index)
    end
    love.graphics.pop()
end
return Picker
