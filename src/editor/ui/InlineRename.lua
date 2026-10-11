local Ui = require("editor.Ui")
local Edit = require("editor.ui.TextEdit")
local Ime = require("editor.ui.Ime")
local Rename = {}
Rename.__index = Rename
function Rename.new(root, rect, text, confirm, multiline)
    local self = setmetatable({root = root, rect = rect, text = text, confirm = confirm, handlers = {}, previousRepeat = love.keyboard.hasKeyRepeat()}, Rename)
    Edit.begin(self, text, true)
    self.multiline, self.baseY = multiline, rect.y
    root:setPopup(self)
    love.keyboard.setKeyRepeat(true)
    love.keyboard.setTextInput(true, rect.x, rect.y, rect.w, rect.h)
    return self
end
function Rename:hitTest() return self end
function Rename:update() end
function Rename:finish()
    self.text = Ime.finish(self, self.text, false)
    local ok, err = self.confirm(self.text)
    if ok then self.root:dismissPopup() else self.error = err end
    return ok
end
function Rename:dispatch(event, ...)
    if event == "keypressed" then
        local key = ...
        if Ime.handlesKey(self, key) then return true end
        if Ime.endsComposition(key) then self.text = Ime.finish(self, self.text, false) end
        if key == "return" or key == "kpenter" then self:finish()
        elseif not self.multiline or not require("editor.ui.MultilineField").key(self, key) then self.text = Edit.key(self, self.text, key, false) end
    elseif event == "textinput" then self.text = Ime.input(self, self.text, ..., false); self.error = nil
    elseif event == "textedited" then Ime.edited(self, (...))
    elseif event == "mousepressed" then
        local x, y, button = ...
        if not Ui.contains(x, y, self.rect) then self:finish()
        elseif button == 1 then
            self.text = Ime.finish(self, self.text, false)
            if self.multiline then require("editor.ui.MultilineField").press(self, x, y) else Edit.press(self, self.text, self.rect, x, false) end
            return true, true
        end
    elseif event == "mousemoved" then
        if self.multiline and self.editState and self.editState.dragging then local x, y = ...; require("editor.ui.MultilineField").press(self, x, y, true)
        else Edit.move(self, (...)) end
    elseif event == "mousereleased" then Edit.release(self)
    elseif event == "dismiss" or event == "cancel" then Ime.cancel(self); love.keyboard.setTextInput(false); love.keyboard.setKeyRepeat(self.previousRepeat) end
    return true
end
function Rename:draw()
    if self.multiline then require("editor.ui.MultilineField").draw(self, Ime.display(self, self.text, false))
    else Ui.field(self.text, self.rect, true, self.composition, self) end
    if self.error then Ui.text(self.error, self.rect.x, self.rect.y + self.rect.h + 3, math.max(self.rect.w, 240), require("editor.Theme").color("error")) end
end
return Rename
