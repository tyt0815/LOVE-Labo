local Inspector = {}
Inspector.__index = Inspector

local DEFAULT_WIDTH = 240

local FIELD_LEFT_OFFSET = 44
local FIELD_RIGHT_MARGIN = 12
local FIELD_HEIGHT = 24
local X_FIELD_Y = 100
local Y_FIELD_Y = 132

local function pointInRect(x, y, left, top, width, height)
    return x >= left
        and x < left + width
        and y >= top
        and y < top + height
end

function Inspector.new(level, width)
    local self = setmetatable({}, Inspector)

    self.level = level
    self.width = width or DEFAULT_WIDTH

    -- Inspector의 text edit 상태는 authoring data와 분리된 transient Editor state다.
    self.activeField = nil
    self.editingLObject = nil
    self.editText = ""
    self.replaceOnTextInput = false

    return self
end

function Inspector:containsPoint(x, y, windowWidth)
    if windowWidth == nil then
        return false
    end

    local left = windowWidth - self.width
    return x >= left and x < windowWidth and y >= 0
end

function Inspector:getLObjectIndex(target)
    if not self.level or not target then
        return nil
    end

    for i, lobject in ipairs(self.level.lobjects) do
        if lobject == target then
            return i
        end
    end

    return nil
end

function Inspector:getFieldAtPosition(x, y, windowWidth)
    if not self:containsPoint(x, y, windowWidth) then
        return nil
    end

    local left = windowWidth - self.width
    local fieldLeft = left + FIELD_LEFT_OFFSET
    local fieldWidth = self.width - FIELD_LEFT_OFFSET - FIELD_RIGHT_MARGIN

    if pointInRect(x, y, fieldLeft, X_FIELD_Y, fieldWidth, FIELD_HEIGHT) then
        return "x"
    end

    if pointInRect(x, y, fieldLeft, Y_FIELD_Y, fieldWidth, FIELD_HEIGHT) then
        return "y"
    end

    return nil
end

function Inspector:isEditing()
    return self.activeField ~= nil
end

function Inspector:beginEdit(field, selectedLObject)
    if (field ~= "x" and field ~= "y")
        or not selectedLObject
        or not selectedLObject.transform
    then
        return false
    end

    local value = selectedLObject.transform[field]

    if type(value) ~= "number" then
        return false
    end

    self.activeField = field
    self.editingLObject = selectedLObject
    self.editText = tostring(value)

    -- 새 field를 클릭하면 기존 값 전체가 선택된 것처럼 동작한다.
    -- 따라서 첫 text input은 기존 숫자 뒤에 붙지 않고 값을 교체한다.
    self.replaceOnTextInput = true

    return true
end

function Inspector:clearEditState()
    self.activeField = nil
    self.editingLObject = nil
    self.editText = ""
    self.replaceOnTextInput = false
end

function Inspector:commitEdit()
    if not self:isEditing() then
        return false
    end

    local field = self.activeField
    local lobject = self.editingLObject
    local value = tonumber(self.editText)

    if value ~= nil and lobject and lobject.transform then
        lobject.transform[field] = value
        self:clearEditState()
        return true
    end

    -- 유효한 숫자가 아니면 authoring data는 변경하지 않고 편집만 종료한다.
    self:clearEditState()
    return false
end

function Inspector:cancelEdit()
    if not self:isEditing() then
        return false
    end

    self:clearEditState()
    return true
end

function Inspector:mousepressed(x, y, button, windowWidth, selectedLObject)
    if not self:containsPoint(x, y, windowWidth) then
        return false
    end

    -- Inspector 영역의 mouse press는 button 종류와 관계없이 소비한다.
    if button ~= 1 then
        return true
    end

    local field = self:getFieldAtPosition(x, y, windowWidth)

    if not field or not selectedLObject then
        self:commitEdit()
        return true
    end

    if self.activeField == field and self.editingLObject == selectedLObject then
        return true
    end

    self:commitEdit()
    self:beginEdit(field, selectedLObject)

    return true
end

function Inspector:textinput(text)
    if not self:isEditing() then
        return false
    end

    if self.replaceOnTextInput then
        self.editText = text
        self.replaceOnTextInput = false
    else
        self.editText = self.editText .. text
    end

    return true
end

function Inspector:keypressed(key)
    if not self:isEditing() then
        return false
    end

    if key == "backspace" then
        if self.replaceOnTextInput then
            self.editText = ""
            self.replaceOnTextInput = false
        else
            -- Transform field는 ASCII 숫자 입력만을 목표로 하므로
            -- 현재 단계에서는 byte 단위 삭제로 충분하다.
            self.editText = self.editText:sub(1, -2)
        end

        return true
    end

    if key == "return" or key == "kpenter" then
        self:commitEdit()
        return true
    end

    if key == "escape" then
        self:cancelEdit()
        return true
    end

    -- 편집 중 다른 key도 Scene View shortcut으로 전달하지 않는다.
    return true
end

function Inspector:drawField(label, field, y, selectedLObject, left)
    local fieldLeft = left + FIELD_LEFT_OFFSET
    local fieldWidth = self.width - FIELD_LEFT_OFFSET - FIELD_RIGHT_MARGIN
    local isActive =
        self.activeField == field
        and self.editingLObject == selectedLObject

    love.graphics.setColor(0.72, 0.74, 0.78, 1.0)
    love.graphics.print(label, left + 20, y + 4)

    if isActive then
        love.graphics.setColor(0.22, 0.28, 0.36, 1.0)
    else
        love.graphics.setColor(0.15, 0.16, 0.19, 1.0)
    end

    love.graphics.rectangle("fill", fieldLeft, y, fieldWidth, FIELD_HEIGHT)

    love.graphics.setColor(0.34, 0.35, 0.39, 1.0)
    love.graphics.rectangle("line", fieldLeft, y, fieldWidth, FIELD_HEIGHT)

    local text

    if isActive then
        text = self.editText
    else
        text = string.format("%.2f", selectedLObject.transform[field])
    end

    love.graphics.setColor(0.90, 0.91, 0.93, 1.0)
    love.graphics.print(text, fieldLeft + 6, y + 4)
end

function Inspector:draw(selectedLObject)
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local left = windowWidth - self.width

    love.graphics.push("all")

    -- 현재는 별도 Docking/Layout system 없이 오른쪽 고정 폭 패널로 시작한다.
    love.graphics.setColor(0.11, 0.12, 0.14, 1.0)
    love.graphics.rectangle("fill", left, 0, self.width, windowHeight)

    love.graphics.setColor(0.28, 0.29, 0.33, 1.0)
    love.graphics.line(left, 0, left, windowHeight)

    love.graphics.setColor(0.92, 0.92, 0.94, 1.0)
    love.graphics.print("Inspector", left + 12, 10)

    if not selectedLObject then
        love.graphics.setColor(0.62, 0.63, 0.67, 1.0)
        love.graphics.print("No selection", left + 12, 44)
        love.graphics.pop()
        return
    end

    local index = self:getLObjectIndex(selectedLObject)

    love.graphics.setColor(0.86, 0.87, 0.90, 1.0)

    if index then
        love.graphics.print("LObject " .. index, left + 12, 44)
    else
        love.graphics.print("LObject", left + 12, 44)
    end

    love.graphics.setColor(0.72, 0.74, 0.78, 1.0)
    love.graphics.print("Transform", left + 12, 78)

    if selectedLObject.transform then
        self:drawField("X", "x", X_FIELD_Y, selectedLObject, left)
        self:drawField("Y", "y", Y_FIELD_Y, selectedLObject, left)
    end

    love.graphics.pop()
end

return Inspector
