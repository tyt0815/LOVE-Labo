local Widget = require("editor.ui.widget")
local UI = require("editor.ui")
local Theme = require("editor.theme")
local IME = require("editor.ui.ime")
local Controls = setmetatable({}, {__index = Widget})
Controls.__index = Controls

function Controls.new(view)
    local self = setmetatable(Widget.new(), Controls)
    self.view = view
    self.handlers = {
        draw = function() self:drawControls() end,
        mousepressed = function(_, x, y, button) return self:press(x, y, button) end,
        wheelmoved = function() return true end,
        keypressed = function(_, key) return self:editKey(key) end,
        textinput = function(_, text)
            if self.editing then self.text, self.replace = IME.input(self, self.text, text, self.replace) end
            return true
        end,
        textedited = function(_, text) if self.editing then IME.edited(self, text) end; return true end,
        hint = function() return self.error or "Snap: align movement to world units. Enter: apply. Esc: cancel." end,
    }
    return self
end

function Controls:rects()
    local check = {x = self.x + 16, y = self.y + 18, w = 20, h = 20}
    local field = {x = self.x + 94, y = self.y + 14, w = math.max(0, self.width - 110), h = 28}
    return check, field
end

function Controls:commit()
    if not self.editing then return end
    self.text, self.replace = IME.finish(self, self.text, self.replace)
    local value = tonumber(self.text)
    if value and value > 0 and value < math.huge then self.view.snapUnit, self.error = value, nil
    else self.error = "Snap unit must be a positive finite number" end
    self.editing = false
end

function Controls:press(x, y, button)
    if button ~= 1 then return true end
    local check, field = self:rects()
    if UI.contains(x, y, field) then
        if not self.editing then self.editing, self.text, self.replace = true, tostring(self.view.snapUnit), true end
    else
        self:commit()
        if x >= check.x and x < field.x - 8 and y >= check.y and y < check.y + check.h then self.view.snapEnabled = not self.view.snapEnabled end
    end
    return true
end

function Controls:editKey(key)
    if not self.editing then return true end
    if IME.handlesKey(self, key) then return true end
    if IME.endsComposition(key) then self.text, self.replace = IME.finish(self, self.text, self.replace) end
    if key == "return" or key == "kpenter" then self:commit()
    elseif key == "escape" then IME.cancel(self); self.editing, self.error = false, nil
    else self.text, self.replace = UI.editKey(self.text, key, self.replace) end
    return true
end

function Controls:drawControls()
    if not self.visible then return end
    love.graphics.push("all")
    love.graphics.setScissor(self.x, self.y, self.width, self.height)
    UI.panel(self.x, self.y, self.width, self.height, "background")
    local check, field = self:rects()
    Theme.setColor("input")
    love.graphics.rectangle("fill", check.x, check.y, check.w, check.h, 3, 3)
    Theme.setColor("border")
    love.graphics.rectangle("line", check.x, check.y, check.w, check.h, 3, 3)
    if self.view.snapEnabled then
        Theme.setColor("focus")
        love.graphics.setLineWidth(2)
        love.graphics.line(check.x + 4, check.y + 10, check.x + 8, check.y + 15, check.x + 16, check.y + 5)
    end
    UI.text("Snap", check.x + 28, check.y + 2)
    UI.hint(check, "Enable snapping to world units.")
    UI.field(self.editing and IME.display(self, self.text, self.replace) or tostring(self.view.snapUnit), field, self.editing, self.composition)
    UI.hint(field, self.error or "Snap unit in world coordinates. Enter: apply. Esc: cancel.")
    love.graphics.pop()
end
return Controls
