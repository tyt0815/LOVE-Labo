local Widget = require("editor.ui.Widget")
local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Color = require("editor.Color")
local Edit = require("editor.ui.TextEdit")
local Ime = require("editor.ui.Ime")
local Picker = setmetatable({}, {__index = Widget})
Picker.__index = Picker

function Picker.new(root, options)
    local self = setmetatable(Widget.new(), Picker)
    self.root, self.options = root, options
    self.entries = options.entries or {{label = "Background", color = options.color, defaultColor = Color.default()}}
    self.selected = 1
    local offset = #self.entries > 1 and 36 or 0
    local popupHeight = 408 + offset
    local width, height = love.graphics.getDimensions()
    local anchor = assert(options.anchor, "Color picker requires a button anchor")
    local left = math.max(0, math.min(anchor.x + anchor.w - 440, width - 440))
    local top = anchor.y + anchor.h + 4
    -- 아래 공간이 부족하면 버튼 위로 펼치고 화면 경계 안으로 보정한다.
    if top + popupHeight > height then top = anchor.y - popupHeight - 4 end
    self.box = {x = left, y = math.max(0, math.min(top, height - popupHeight)), w = 440, h = popupHeight}
    local x, y = self.box.x, self.box.y
    self.tabs = {}
    if offset > 0 then
        for i, entry in ipairs(self.entries) do
            self.tabs[i] = {x = x + 20 + (i - 1) * 134, y = y + 44, w = 126, h = 28, label = entry.label}
        end
    end
    y = y + offset
    self.square = {x = x + 20, y = y + 50, w = 240, h = 240}
    self.hue = {x = x + 274, y = y + 50, w = 24, h = 240}
    self.swatch = {x = x + 316, y = y + 50, w = 104, h = 80}
    self.fields = {}
    for i, name in ipairs({"R", "G", "B", "HEX"}) do
        self.fields[i] = {name = name, x = x + 316, y = y + 156 + (i - 1) * 42, w = 104, h = 28}
    end
    self.reset = {x = x + 20, y = y + 358, w = 126, h = 30}
    self.apply = {x = x + 238, y = y + 358, w = 92, h = 30}
    self.cancel = {x = x + 340, y = y + 358, w = 80, h = 30}
    self:setColor(self.entries[1].color)
    self.useDefault = self.entries[1].useDefault
    root:setPopup(self)
    return self
end

function Picker:changed()
    local entry = self.entries[self.selected]
    entry.color, entry.useDefault = {unpack(self.color)}, self.useDefault == true
    if self.options.onChange then self.options.onChange(entry.color, entry.useDefault, self.selected) end
end

function Picker:setColor(color)
    self.color = assert(Color.rgb(color))
    self.h, self.s, self.v = Color.toHsv(self.color)
end

function Picker:fieldText(index)
    return index == 4 and Color.hex(self.color) or tostring(math.floor(self.color[index] + 0.5))
end

function Picker:inputColor()
    local color, err
    if self.editing == 4 then color, err = Color.fromHex(self.text)
    else
        color = {unpack(self.color)}
        local value = tonumber(self.text)
        if not value then return nil, "RGB values must be between 0 and 255" end
        color[self.editing] = value
        color, err = Color.rgb(color)
    end
    return color, err
end

function Picker:previewInput()
    local color = self:inputColor()
    if color then
        self:setColor(color); self.useDefault, self.error = false, nil; self:changed()
    end
end

function Picker:commit()
    if not self.editing then return true end
    self.text, self.replace = Ime.finish(self, self.text, self.replace)
    local color, err = self:inputColor()
    if not color then self.error = err; return false end
    self:setColor(color)
    self.editing, self.error, self.useDefault = nil, nil, false
    self:changed()
    return true
end

function Picker:submit()
    if not self:commit() then return false end
    local color = self.color
    if self.useDefault then color = nil end
    local ok, err = self.options.onConfirm(color, self.useDefault == true, self.entries)
    if ok then self.root:dismissPopup() else self.error = err or "Could not apply background" end
    return ok
end

function Picker:pick(x, y)
    local function ratio(value, start, size) return math.max(0, math.min(1, (value - start) / size)) end
    if self.drag == "hue" then self.h = ratio(y, self.hue.y, self.hue.h)
    else self.s, self.v = ratio(x, self.square.x, self.square.w), 1 - ratio(y, self.square.y, self.square.h) end
    self.color, self.useDefault = Color.fromHsv(self.h, self.s, self.v), false
    self:changed()
end

function Picker:hitTest(x, y) return Ui.contains(x, y, self.box) and self or nil end

function Picker:dispatch(event, ...)
    if event == "dismiss" or event == "cancel" then
        self.drag = nil; Ime.cancel(self); Edit.release(self)
        if event == "dismiss" and self.options.onDismiss then self.options.onDismiss() end
    elseif event == "mousepressed" then
        local x, y, button = ...
        if button ~= 1 then return true end
        if Ui.contains(x, y, self.cancel) then self.root:dismissPopup(); return true end
        if Ui.contains(x, y, self.reset) then
            Ime.cancel(self); self.editing, self.error = nil, nil
            self:setColor(self.entries[self.selected].defaultColor or Color.default()); self.useDefault = true
            self:changed()
            return true
        end
        if Ui.contains(x, y, self.apply) then self:submit(); return true end
        if not self:commit() then return true end
        for i, tab in ipairs(self.tabs) do if Ui.contains(x, y, tab) then
            self.selected = i
            self:setColor(self.entries[i].color); self.useDefault = self.entries[i].useDefault
            return true
        end end
        for i, field in ipairs(self.fields) do if Ui.contains(x, y, field) then
            self.editing, self.text, self.replace = i, self:fieldText(i), true
            Edit.begin(self, self.text, true)
            return true
        end end
        if Ui.contains(x, y, self.square) or Ui.contains(x, y, self.hue) then
            self.drag = Ui.contains(x, y, self.hue) and "hue" or "square"
            self:pick(x, y); return true, true
        end
    elseif event == "mousemoved" and self.drag then self:pick(...)
    elseif event == "mousereleased" then self.drag = nil
    elseif event == "textinput" and self.editing then
        self.text, self.replace = Ime.input(self, self.text, (...), self.replace); self.error = nil
        self:previewInput()
    elseif event == "textedited" and self.editing then Ime.edited(self, (...))
    elseif event == "keypressed" then
        local key = ...
        if Ime.handlesKey(self, key) then return true end
        if key == "return" or key == "kpenter" then
            if self.editing then self:commit() else self:submit() end
        elseif key == "tab" then
            local nextField = (self.editing or 0) % 4 + 1
            if self:commit() then
                self.editing, self.text, self.replace = nextField, self:fieldText(nextField), true
                Edit.begin(self, self.text, true)
            end
        elseif self.editing then
            if Ime.endsComposition(key) then self.text, self.replace = Ime.finish(self, self.text, self.replace) end
            self.text, self.replace = Ui.editKey(self.text, key, self.replace, self)
            self:previewInput()
        end
    end
    return true
end

function Picker:draw()
    local box, square = self.box, self.square
    Theme.setColor("surface"); love.graphics.rectangle("fill", box.x, box.y, box.w, box.h, 6, 6)
    Theme.setColor("border"); love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", box.x + 0.5, box.y + 0.5, box.w - 1, box.h - 1, 6, 6)
    Ui.text(self.options.title or "Background", box.x + 20, box.y + 18, box.w - 40)
    for i, tab in ipairs(self.tabs) do Ui.button(tab.label, tab, self.selected == i) end
    -- 두 선형 그라데이션을 합성하면 삼각형 대각선 없이 연속적인 SV 평면이 된다.
    local hue = Color.fromHsv(self.h, 1, 1)
    local function gradient(rect, colors)
        local mesh = love.graphics.newMesh({
            {0, 0, 0, 0, unpack(colors[1])}, {rect.w, 0, 0, 0, unpack(colors[2])},
            {rect.w, rect.h, 0, 0, unpack(colors[3])}, {0, rect.h, 0, 0, unpack(colors[4])}}, "fan", "stream")
        love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(mesh, rect.x, rect.y); mesh:release()
    end
    local white, tint = {1, 1, 1, 1}, {hue[1] / 255, hue[2] / 255, hue[3] / 255, 1}
    gradient(square, {white, tint, tint, white})
    gradient(square, {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 1}, {0, 0, 0, 1}})
    for i = 0, 5 do
        local a, b = Color.fromHsv(i / 6, 1, 1), Color.fromHsv((i + 1) / 6, 1, 1)
        a, b = {a[1] / 255, a[2] / 255, a[3] / 255, 1}, {b[1] / 255, b[2] / 255, b[3] / 255, 1}
        gradient({x = self.hue.x, y = self.hue.y + i * self.hue.h / 6, w = self.hue.w, h = self.hue.h / 6}, {a, a, b, b})
    end
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0, 0, 0, 1); love.graphics.circle("line", square.x + self.s * square.w, square.y + (1 - self.v) * square.h, 6)
    love.graphics.setColor(1, 1, 1, 1); love.graphics.circle("line", square.x + self.s * square.w, square.y + (1 - self.v) * square.h, 4)
    love.graphics.rectangle("line", self.hue.x - 2, self.hue.y + self.h * self.hue.h - 2, self.hue.w + 4, 4)
    love.graphics.setColor(self.color[1] / 255, self.color[2] / 255, self.color[3] / 255, 1)
    love.graphics.rectangle("fill", self.swatch.x, self.swatch.y, self.swatch.w, self.swatch.h)
    for i, field in ipairs(self.fields) do
        Ui.text(field.name, field.x, field.y - 14, field.w, Theme.color("textMuted"))
        Ui.field(self.editing == i and Ime.display(self, self.text, self.replace) or self:fieldText(i),
            field, self.editing == i, self.editing == i and self.composition, self)
    end
    Ui.text(self.error or "RGB: 0–255    HEX: RRGGBB    Tab: next field", box.x + 20, self.reset.y - 34, box.w - 40, Theme.color(self.error and "error" or "textMuted"))
    Ui.button("Theme default", self.reset, self.useDefault)
    Ui.button("Cancel", self.cancel); Ui.button("Apply", self.apply)
end

return Picker
