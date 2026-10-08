local Theme = require("editor.theme")
local Widget = require("editor.ui.widget")
local UI = require("editor.ui")
local Dialog = setmetatable({}, { __index = Widget })
Dialog.__index = Dialog

function Dialog.new(root, options)
    local self = setmetatable(Widget.new(), Dialog)
    self.root, self.options, self.text, self.replace = root, options, options.value or "", true
    local width, height = love.graphics.getDimensions()
    self:setBounds(0, 0, width, height)
    self.box = { x = math.max(0, (width - 460) / 2), y = math.max(0, (height - 210) / 2), w = 460, h = 210 }
    local box = self.box
    self.field = { x = box.x + 16, y = box.y + 76, w = box.w - 32, h = 32 }
    self.cancel = { x = box.x + box.w - 206, y = box.y + 164, w = 90, h = 30 }
    self.confirm = { x = box.x + box.w - 106, y = box.y + 164, w = 90, h = 30 }
    root:setPopup(self)
    return self
end

function Dialog:submit()
    local ok, err = self.options.onConfirm(self.text)
    if ok then self.root:dismissPopup() else self.error = err or "Operation failed" end
end

function Dialog:hitTest()
    return self
end

function Dialog:dispatch(event, ...)
    if event == "textinput" and self.options.input then
        self.text = (self.replace and "" or self.text) .. (...)
        self.replace, self.error = false, nil
    elseif event == "keypressed" then
        local key = ...
        if key == "return" or key == "kpenter" then self:submit()
        elseif self.options.input then self.text, self.replace = UI.editKey(self.text, key, self.replace) end
    elseif event == "mousepressed" then
        local x, y, button = ...
        if button == 1 then
            if UI.contains(x, y, self.cancel) then self.root:dismissPopup()
            elseif UI.contains(x, y, self.confirm) then self:submit() end
        end
    end
    return true
end

function Dialog:draw()
    local box = self.box
    Theme.setColor("overlay")
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    Theme.setColor("surface")
    love.graphics.rectangle("fill", box.x, box.y, box.w, box.h, 6, 6)
    UI.text(self.options.title, box.x + 16, box.y + 16, box.w - 32)
    UI.text(self.options.message or "", box.x + 16, box.y + 46, box.w - 32)
    if self.options.input then UI.field(self.text, self.field, true)
    else UI.text(self.options.detail or "", box.x + 16, box.y + 82, box.w - 32) end
    if self.error then UI.text(self.error, box.x + 16, box.y + 128, box.w - 32, Theme.color("error")) end
    UI.button("Cancel", self.cancel)
    UI.button(self.options.confirmLabel or "Create", self.confirm)
end

return Dialog
