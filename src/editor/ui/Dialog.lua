local Theme = require("editor.Theme")
local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Ime = require("editor.ui.Ime")
local Edit = require("editor.ui.TextEdit")
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
    local cancelWidth = Ui.buttonWidth("Cancel")
    local confirmWidth = Ui.buttonWidth(options.confirmLabel or "Create")
    self.cancel = { x = box.x + box.w - 16 - cancelWidth, y = box.y + box.h - 46, w = cancelWidth, h = 30 }
    self.confirm = { x = self.cancel.x - Ui.METRICS.buttonGap - confirmWidth, y = self.cancel.y, w = confirmWidth, h = 30 }
    if options.onBack then self.back = {x = box.x + 16, y = self.cancel.y, w = Ui.buttonWidth("Back"), h = 30} end
    self.choicesRect = { x = box.x + 16, y = box.y + 140, w = box.w - 32, h = 150 }
    self.selected, self.choiceScroll = not options.listOnly and options.choices and #options.choices > 0 and 1 or nil, 0
    if options.checkboxes then
        for _, choice in ipairs(options.choices) do if choice.checked == nil then choice.checked = true end end
    end
    if options.content then
        options.content:setBounds(box.x + 16, box.y + (options.input and 140 or 82), box.w - 32, options.input and 190 or 248)
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
    self.text, self.replace = Ime.finish(self, self.text, self.replace)
    local choice = self.selected and self.options.choices[self.selected]
    local checked
    if self.options.checkboxes then
        checked = {}
        for _, item in ipairs(self.options.choices) do if item.checked then checked[#checked + 1] = item.value end end
    end
    local ok, err = self.options.onConfirm(self.text, choice and choice.value, checked)
    if ok then
        -- 다음 단계가 새 팝업을 열었으면 그 창을 닫지 않는다.
        if self.root.popup == self then self.root:dismissPopup() end
    else self.error = err or "Operation failed" end
end

function Dialog:hitTest()
    return self
end

function Dialog:dispatch(event, ...)
    if event == "dismiss" then Ime.cancel(self)
    elseif event == "textedited" and self.options.input and not self.choiceFocused then
        self.contentFocused = false
        Ime.edited(self, (...))
    elseif event == "textinput" and self.options.input and not self.choiceFocused then
        self.contentFocused = false
        self.text, self.replace = Ime.input(self, self.text, (...), self.replace)
        self.error = nil
    elseif event == "keypressed" then
        local key = ...
        if Ime.handlesKey(self, key) then return true end
        if Ime.endsComposition(key) then
            self.text, self.replace = Ime.finish(self, self.text, self.replace)
        end
        if key == "return" or key == "kpenter" then self:submit()
        elseif key == "tab" and self.options.content and self.options.input then self.contentFocused = not self.contentFocused
        elseif self.contentFocused and self.options.content then self.options.content:dispatch(event, key)
        elseif key == "tab" and self.options.choices then self.choiceFocused = not self.choiceFocused
        elseif key == "space" and self.options.checkboxes and #self.options.choices > 0 then
            self.selected = self.selected or 1
            local choice = self.options.choices[self.selected]
            choice.checked = not choice.checked
        elseif (key == "up" or key == "down") and self.options.choices and #self.options.choices > 0 then
            if self.options.listOnly and not self.options.checkboxes then
                self.choiceScroll = math.max(0, math.min(math.max(0, #self.options.choices - 5),
                    self.choiceScroll + (key == "up" and -1 or 1)))
                return true
            end
            local initial = key == "up" and #self.options.choices + 1 or 0
            self.selected = math.max(1, math.min(#self.options.choices, (self.selected or initial) + (key == "up" and -1 or 1)))
            self.choiceScroll = math.max(0, math.min(self.choiceScroll, self.selected - 1))
            self.choiceScroll = math.max(self.choiceScroll, self.selected - 5)
        elseif self.options.input and not self.choiceFocused then self.text, self.replace = Ui.editKey(self.text, key, self.replace, self) end
    elseif event == "mousepressed" then
        local x, y, button = ...
        if button == 1 then
            if not Ui.contains(x, y, self.field) and not Ui.contains(x, y, self.cancel) then
                self.text, self.replace = Ime.finish(self, self.text, self.replace)
            end
            if Ui.contains(x, y, self.cancel) then self.root:dismissPopup()
            elseif self.back and Ui.contains(x, y, self.back) then self.options.onBack()
            elseif Ui.contains(x, y, self.confirm) then self:submit()
            elseif self.options.input and Ui.contains(x, y, self.field) then
                self.text, self.replace = Ime.finish(self, self.text, self.replace)
                self.choiceFocused, self.contentFocused, self.replace = false, false, false
                Edit.press(self, self.text, self.field, x, false)
            elseif self.options.content and self.options.content:containsPoint(x, y) then
                self.contentFocused = true
                self.options.content:dispatch(event, x, y, button)
            elseif self.options.choices and Ui.contains(x, y, self.choicesRect) then
                local index = math.floor((y - self.choicesRect.y) / 30) + 1 + self.choiceScroll
                if self.options.choices[index] and self.options.checkboxes then
                    self.options.choices[index].checked = not self.options.choices[index].checked
                    self.selected, self.choiceFocused = index, true
                end
                if self.options.choices[index] and not self.options.listOnly then self.selected, self.choiceFocused = index, true end
            end
        end
    elseif event == "mousemoved" then Edit.move(self, (...))
    elseif event == "mousereleased" then Edit.release(self)
    elseif event == "wheelmoved" and self.options.content then
        local x, y = ...
        if self.options.content:containsPoint(x, y) then self.options.content:dispatch(event, ...) end
    elseif event == "wheelmoved" and self.options.choices then
        local x, y, amount = ...
        if Ui.contains(x, y, self.choicesRect) then
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
    Ui.text(self.options.title, box.x + 16, box.y + 16, box.w - 32)
    Ui.text(self.options.message or "", box.x + 16, box.y + 46, box.w - 32)
    if self.options.input then Ui.field(Ime.display(self, self.text, self.replace), self.field,
        not self.choiceFocused and not self.contentFocused, self.composition, self)
    elseif not self.options.content then Ui.text(self.options.detail or "", box.x + 16, box.y + 82, box.w - 32) end
    if self.options.choices then
        Ui.text(self.options.choiceLabel or "Class", box.x + 16, box.y + 118, box.w - 32)
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
                if self.options.checkboxes then Ui.checkbox({x = rect.x + 8, y = y + 8, w = 14, h = 14}, choice.checked) end
                local padding = self.options.checkboxes and 30 or 8
                Ui.text(choice.label, rect.x + padding, y + 7, rect.w - padding - 8)
                Ui.hint({x = rect.x, y = y, w = rect.w, h = 30}, self.options.listOnly and choice.label
                    or "Select " .. choice.label .. ". Enter: confirm.")
            end
        end
        if #self.options.choices == 0 then Ui.text(self.options.emptyLabel or "No matching classes. Create one in Sources.", rect.x + 8, rect.y + 8, rect.w - 16) end
        local hint = self.options.checkboxes and "Click / Space: toggle    Up/Down or wheel: navigate"
            or self.options.listOnly and "Up/Down or wheel: scroll" or "Tab: name/class    Up/Down or wheel: select class"
        Ui.text(hint, box.x + 16, box.y + 294, box.w - 32, Theme.color("textMuted"))
    end
    if self.options.content then
        if self.options.input then Ui.text(self.options.contentLabel or "Destination folder", box.x + 16, box.y + 118, box.w - 32) end
        self.options.content:draw()
        Ui.text(self.options.contentHint or "Tab: path/tree    Arrows: navigate folders", box.x + 16, box.y + 338, box.w - 32, Theme.color("textMuted"))
    end
    if self.error then Ui.text(self.error, box.x + 16, box.y + box.h - 74, box.w - 32, Theme.color("error")) end
    Ui.button("Cancel", self.cancel)
    if self.back then Ui.button("Back", self.back) end
    Ui.button(self.options.confirmLabel or "Create", self.confirm)
end

return Dialog
