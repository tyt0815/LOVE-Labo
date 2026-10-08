local Widget = require("editor.ui.widget")
local UI = require("editor.ui")
local IME = require("editor.ui.ime")
local Controls = setmetatable({}, {__index = Widget})
Controls.__index = Controls
local modes = {"translate", "rotate", "scale"}
local labels = {translate = "Move", rotate = "Rot", scale = "Scale"}
local units = {translate = "world units", rotate = "degrees", scale = "scale units"}

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
        hint = function() return self.error or "W/E/R: mode. Move/Rot/Scale buttons: toggle independent snapping." end,
    }
    return self
end

function Controls:fieldWidth() return love.graphics.getFont():getWidth("000") + 20 end
function Controls:preferredWidth() return 244 + 3 * self:fieldWidth() end
function Controls:preferredHeight(width) return width >= self:preferredWidth() and 56 or 120 end

function Controls:snapRects()
    local result, left = {}, self.x + 16
    local wrapped = self.width < self:preferredWidth()
    for index, mode in ipairs(modes) do
        local buttonWidth = mode == "rotate" and 48 or 58
        local top = self.y + 14 + (wrapped and (index - 1) * 32 or 0)
        if wrapped then left = self.x + 16 end
        local fieldWidth = math.min(self:fieldWidth(), math.max(0, self.width - 40 - buttonWidth))
        result[mode] = {button = {x = left, y = top, w = buttonWidth, h = 28},
            field = {x = left + buttonWidth + 8, y = top, w = fieldWidth, h = 28}}
        left = left + buttonWidth + 8 + fieldWidth + 12
    end
    return result
end

function Controls:rects(mode)
    local rects = self:snapRects()[mode or "translate"]
    return rects.button, rects.field
end

function Controls:apply(mode, enabled, value)
    local ok, err = self.view:setSnap(mode, enabled, value)
    self.error = not ok and (err or "Could not save snap settings") or nil
    return ok
end

function Controls:commit()
    if not self.editing then return end
    self.text, self.replace = IME.finish(self, self.text, self.replace)
    local mode, value = self.editing, tonumber(self.text)
    self.editing = nil
    self:apply(mode, self.view.snapSettings[mode].enabled, value)
end

function Controls:press(x, y, button)
    if button ~= 1 then return true end
    local rects = self:snapRects()
    for _, mode in ipairs(modes) do
        if UI.contains(x, y, rects[mode].field) then
            if self.editing ~= mode then
                self:commit()
                self.editing, self.text, self.replace = mode, tostring(self.view.snapSettings[mode].unit), true
            end
            return true
        end
    end
    self:commit()
    for _, mode in ipairs(modes) do
        if UI.contains(x, y, rects[mode].button) then
            local setting = self.view.snapSettings[mode]
            self:apply(mode, not setting.enabled, setting.unit)
            return true
        end
    end
    return true
end

function Controls:editKey(key)
    if not self.editing then return true end
    if IME.handlesKey(self, key) then return true end
    if IME.endsComposition(key) then self.text, self.replace = IME.finish(self, self.text, self.replace) end
    if key == "return" or key == "kpenter" then self:commit()
    elseif key == "escape" then IME.cancel(self); self.editing, self.error = nil, nil
    else self.text, self.replace = UI.editKey(self.text, key, self.replace) end
    return true
end

function Controls:drawControls()
    if not self.visible then return end
    love.graphics.push("all")
    love.graphics.setScissor(self.x, self.y, self.width, self.height)
    UI.panel(self.x, self.y, self.width, self.height, "background")
    local snapRects = self:snapRects()
    for _, mode in ipairs(modes) do
        local setting, rects = self.view.snapSettings[mode], snapRects[mode]
        UI.button(labels[mode], rects.button, setting.enabled,
            labels[mode] .. " snapping: " .. (setting.enabled and "On" or "Off") .. ". Click to toggle.")
        UI.field(self.editing == mode and IME.display(self, self.text, self.replace) or tostring(setting.unit), rects.field,
            self.editing == mode, self.editing == mode and self.composition)
        UI.hint(rects.field, self.error or labels[mode] .. " snap step in " .. units[mode] .. ". Enter: apply. Esc: cancel.")
    end
    love.graphics.pop()
end
return Controls
