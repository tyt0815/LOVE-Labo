local Theme = require("editor.theme")
local Widget = require("editor.ui.widget")
local UI = require("editor.ui")
local IME = require("editor.ui.ime")
local Dialog = setmetatable({}, { __index = Widget })
Dialog.__index = Dialog

function Dialog.new(root, options)
    local self = setmetatable(Widget.new(), Dialog)
    self.root, self.options, self.text, self.replace = root, options, options.value or "", true
    local width, height = love.graphics.getDimensions()
    self:setBounds(0, 0, width, height)
    local dialogHeight = options.content and 430 or options.choices and 386 or 210
    self.box = { x = math.max(0, (width - 460) / 2), y = math.max(0, (height - dialogHeight) / 2), w = 460, h = dialogHeight }
    local box = self.box
    self.field = { x = box.x + 16, y = box.y + 76, w = box.w - 32, h = 32 }
    local cancelWidth = UI.buttonWidth("Cancel")
    local confirmWidth = UI.buttonWidth(options.confirmLabel or "Create")
    self.cancel = { x = box.x + box.w - 16 - cancelWidth, y = box.y + box.h - 46, w = cancelWidth, h = 30 }
    self.confirm = { x = self.cancel.x - UI.metrics.buttonGap - confirmWidth, y = self.cancel.y, w = confirmWidth, h = 30 }
    self.choicesRect = { x = box.x + 16, y = box.y + 140, w = box.w - 32, h = 150 }
    self.selected, self.choiceScroll = options.choices and #options.choices > 0 and 1 or nil, 0
    if options.content then
        options.content:setBounds(box.x + 16, box.y + 140, box.w - 32, 190)
        options.content:clampScroll()
        for i, node in ipairs(options.content.nodes) do
            if node.reference == options.content.selected then
                options.content.scroll = math.max(0, i - options.content.rows)
                break
            end
        end
        self.contentFocused = true
    end
    root:setPopup(self)
    return self
end

function Dialog:submit()
    self.text, self.replace = IME.finish(self, self.text, self.replace)
    local choice = self.selected and self.options.choices[self.selected]
    local ok, err = self.options.onConfirm(self.text, choice and choice.value)
    if ok then self.root:dismissPopup() else self.error = err or "Operation failed" end
end

function Dialog:hitTest()
    return self
end

function Dialog:dispatch(event, ...)
    if event == "dismiss" then IME.cancel(self)
    elseif event == "textedited" and self.options.input and not self.choiceFocused then
        self.contentFocused = false
        IME.edited(self, (...))
    elseif event == "textinput" and self.options.input and not self.choiceFocused then
        self.contentFocused = false
        self.text, self.replace = IME.input(self, self.text, (...), self.replace)
        self.error = nil
    elseif event == "keypressed" then
        local key = ...
        if IME.handlesKey(self, key) then return true end
        if IME.endsComposition(key) then
            self.text, self.replace = IME.finish(self, self.text, self.replace)
        end
        if key == "return" or key == "kpenter" then self:submit()
        elseif key == "tab" and self.options.content then self.contentFocused = not self.contentFocused
        elseif self.contentFocused and self.options.content then self.options.content:dispatch(event, key)
        elseif key == "tab" and self.options.choices then self.choiceFocused = not self.choiceFocused
        elseif (key == "up" or key == "down") and self.options.choices and #self.options.choices > 0 then
            self.selected = math.max(1, math.min(#self.options.choices, (self.selected or 1) + (key == "up" and -1 or 1)))
            self.choiceScroll = math.max(0, math.min(self.choiceScroll, self.selected - 1))
            self.choiceScroll = math.max(self.choiceScroll, self.selected - 5)
        elseif self.options.input and not self.choiceFocused then self.text, self.replace = UI.editKey(self.text, key, self.replace) end
    elseif event == "mousepressed" then
        local x, y, button = ...
        if button == 1 then
            if not UI.contains(x, y, self.field) and not UI.contains(x, y, self.cancel) then
                self.text, self.replace = IME.finish(self, self.text, self.replace)
            end
            if UI.contains(x, y, self.cancel) then self.root:dismissPopup()
            elseif UI.contains(x, y, self.confirm) then self:submit()
            elseif UI.contains(x, y, self.field) then self.choiceFocused, self.contentFocused = false, false
            elseif self.options.content and self.options.content:containsPoint(x, y) then
                self.contentFocused = true
                self.options.content:dispatch(event, x, y, button)
            elseif self.options.choices and UI.contains(x, y, self.choicesRect) then
                local index = math.floor((y - self.choicesRect.y) / 30) + 1 + self.choiceScroll
                if self.options.choices[index] then self.selected, self.choiceFocused = index, true end
            end
        end
    elseif event == "wheelmoved" and self.options.content then
        local x, y = ...
        if self.options.content:containsPoint(x, y) then self.options.content:dispatch(event, ...) end
    elseif event == "wheelmoved" and self.options.choices then
        local x, y, amount = ...
        if UI.contains(x, y, self.choicesRect) then
            self.choiceScroll = math.floor(math.max(0, math.min(math.max(0, #self.options.choices - 5), self.choiceScroll - amount * 3)))
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
    if self.options.input then UI.field(IME.display(self, self.text, self.replace), self.field,
        not self.choiceFocused and not self.contentFocused, self.composition)
    else UI.text(self.options.detail or "", box.x + 16, box.y + 82, box.w - 32) end
    if self.options.choices then
        UI.text(self.options.choiceLabel or "Class", box.x + 16, box.y + 118, box.w - 32)
        local rect = self.choicesRect
        Theme.setColor("input")
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 3, 3)
        for row = 1, 5 do
            local index = row + self.choiceScroll
            local choice = self.options.choices[index]
            if choice then
                local y = rect.y + (row - 1) * 30
                if index == self.selected then
                    Theme.setColor("selection")
                    love.graphics.rectangle("fill", rect.x + 2, y + 1, rect.w - 4, 28, 3, 3)
                end
                UI.text(choice.label, rect.x + 8, y + 7, rect.w - 16)
                UI.hint({x = rect.x, y = y, w = rect.w, h = 30}, "Select " .. choice.label .. ". Enter: confirm.")
            end
        end
        if #self.options.choices == 0 then UI.text("No matching classes. Create one in Sources.", rect.x + 8, rect.y + 8, rect.w - 16) end
        UI.text("Tab: name/class    Up/Down or wheel: select class", box.x + 16, box.y + 294, box.w - 32, Theme.color("textMuted"))
    end
    if self.options.content then
        UI.text("Destination folder", box.x + 16, box.y + 118, box.w - 32)
        self.options.content:draw()
        UI.text("Tab: path/tree    Arrows: navigate folders", box.x + 16, box.y + 338, box.w - 32, Theme.color("textMuted"))
    end
    if self.error then UI.text(self.error, box.x + 16, box.y + box.h - 74, box.w - 32, Theme.color("error")) end
    UI.button("Cancel", self.cancel)
    UI.button(self.options.confirmLabel or "Create", self.confirm)
end

return Dialog
