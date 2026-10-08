local Theme = require("editor.theme")
local UI = require("editor.ui")
local IME = require("editor.ui.ime")
local Inspector = {}
Inspector.__index = Inspector

local DEFAULT_WIDTH = 300

local FIELD_LEFT_OFFSET = 32
local FIELD_HEIGHT = 24
local X_FIELD_Y = 100 + UI.metrics.contentPaddingY
local Y_FIELD_Y = 132 + UI.metrics.contentPaddingY
local TRANSFORM_FIELDS = {x = X_FIELD_Y, y = Y_FIELD_Y,
    rotation = 164 + UI.metrics.contentPaddingY,
    scaleX = 196 + UI.metrics.contentPaddingY, scaleY = 228 + UI.metrics.contentPaddingY}
local function fieldOffset(field) return (field == "x" or field == "y") and FIELD_LEFT_OFFSET or 72 end

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
    for field, top in pairs(TRANSFORM_FIELDS) do
        local offset = fieldOffset(field)
        if pointInRect(x, y, left + UI.metrics.contentPaddingX + offset, top, self.width - offset - 2 * UI.metrics.contentPaddingX, FIELD_HEIGHT) then return field end
    end

    return nil
end

function Inspector:isEditing()
    return self.activeField ~= nil or self.classInspector and self.classInspector:isEditing() or false
end

function Inspector:beginEdit(field, selectedLObject)
    if not TRANSFORM_FIELDS[field]
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
    IME.cancel(self)
    self.activeField = nil
    self.editingLObject = nil
    self.editText = ""
    self.replaceOnTextInput = false
end

function Inspector:commitEdit()
    if self.classInspector and self.classInspector:isEditing() then return self.classInspector:commitEdit() end
    if not self:isEditing() then
        return false
    end

    local field = self.activeField
    local lobject = self.editingLObject
    self.editText, self.replaceOnTextInput = IME.finish(self, self.editText, self.replaceOnTextInput)
    local value = tonumber(self.editText)

    if require("core.transform").finite(value) and lobject and lobject.transform
        and ((field ~= "scaleX" and field ~= "scaleY") or value > 0) then
        lobject.transform[field] = field == "rotation" and require("core.transform").normalizeRotation(value) or value
        self:clearEditState()
        return true
    end

    -- 유효한 숫자가 아니면 authoring data는 변경하지 않고 편집만 종료한다.
    self:clearEditState()
    return false
end

function Inspector:cancelEdit()
    if self.classInspector then self.classInspector:cancelEdit() end
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

    if self.classInspector and self.classInspector.target and not selectedLObject then
        return self.classInspector:mousepressed(x, y, button)
    end
    if selectedLObject and self.classInspector and self.classInspector.target and y >= 270 then
        self:commitEdit()
        return self.classInspector:mousepressed(x, y, button)
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
    if self.classInspector and self.classInspector:isEditing() then return self.classInspector:textinput(text) end
    if not self:isEditing() then
        return false
    end

    self.editText, self.replaceOnTextInput = IME.input(self, self.editText, text, self.replaceOnTextInput)

    return true
end

function Inspector:textedited(text)
    if self.classInspector and self.classInspector:isEditing() then return self.classInspector:textedited(text) end
    if not self:isEditing() then return false end
    IME.edited(self, text)
    return true
end

function Inspector:keypressed(key)
    if self.classInspector and self.classInspector:isEditing() then return self.classInspector:keypressed(key) end
    if not self:isEditing() then
        return false
    end
    if IME.handlesKey(self, key) then return true end
    if IME.endsComposition(key) then
        self.editText, self.replaceOnTextInput = IME.finish(self, self.editText, self.replaceOnTextInput)
    end

    if key == "backspace" then
        if self.replaceOnTextInput then
            self.editText = ""
            self.replaceOnTextInput = false
        else
            self.editText = UI.editKey(self.editText, key, false)
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
    local offset = fieldOffset(field)
    local fieldLeft = left + UI.metrics.contentPaddingX + offset
    local fieldWidth = self.width - offset - 2 * UI.metrics.contentPaddingX
    local isActive =
        self.activeField == field
        and self.editingLObject == selectedLObject

    Theme.setColor("textMuted")
    require("editor.ui").label(label, left + UI.metrics.contentPaddingX, y + 4)

    Theme.setColor("input")

    love.graphics.rectangle("fill", fieldLeft, y, fieldWidth, FIELD_HEIGHT)

    Theme.setColor(isActive and "focus" or "border")
    love.graphics.rectangle("line", fieldLeft, y, fieldWidth, FIELD_HEIGHT)

    local text

    if isActive then
        text = IME.display(self, self.editText, self.replaceOnTextInput)
    else
        text = string.format("%.2f", selectedLObject.transform[field])
    end

    Theme.setColor("text")
    love.graphics.print(text, fieldLeft + 6, y + 4)
end

function Inspector:draw(selectedLObject)
    local windowWidth, windowHeight = love.graphics.getDimensions()
    windowHeight = self.height or windowHeight
    local left = windowWidth - self.width

    love.graphics.push("all")

    local UI = require("editor.ui")
    UI.panel(left, 0, self.width, windowHeight)
    UI.panelHeading("Inspector", left, 0, self.width)

    if self.assetSummary then
        UI.label(self.assetSummary.name, left + UI.metrics.contentPaddingX, 44 + UI.metrics.contentPaddingY, self.width - 2 * UI.metrics.contentPaddingX)
        UI.text(self.assetSummary.kind, left + UI.metrics.contentPaddingX, 60 + UI.metrics.contentPaddingY, self.width - 2 * UI.metrics.contentPaddingX, Theme.color("textMuted"))
        UI.text(self.assetSummary.reference, left + UI.metrics.contentPaddingX, 86 + UI.metrics.contentPaddingY, self.width - 2 * UI.metrics.contentPaddingX, Theme.color("textMuted"))
        local hint = self.assetSummary.kind == "Level" and "Double-click to edit level"
            or self.assetSummary.kind == "Folder" and "Double-click to browse" or "Read-only asset information"
        UI.text(hint, left + UI.metrics.contentPaddingX, 110 + UI.metrics.contentPaddingY, self.width - 2 * UI.metrics.contentPaddingX, Theme.color("textMuted"))
        love.graphics.pop()
        return
    end

    if not selectedLObject then
        if self.classInspector and self.classInspector.target then
            self.classInspector:layout(left, self.width, windowHeight)
            self.classInspector:draw()
            love.graphics.pop()
            return
        end
        Theme.setColor("textMuted")
        love.graphics.print("No selection", left + UI.metrics.contentPaddingX, 44 + UI.metrics.contentPaddingY)
        love.graphics.pop()
        return
    end

    local index = self:getLObjectIndex(selectedLObject)
    local displayId = selectedLObject.authoringId or index

    Theme.setColor("text")

    local name = type(selectedLObject.name) == "string" and selectedLObject.name ~= "" and selectedLObject.name
        or displayId and "LObject " .. displayId or "LObject"
    UI.label(name, left + UI.metrics.contentPaddingX, 44 + UI.metrics.contentPaddingY, self.width - 2 * UI.metrics.contentPaddingX)
    UI.text("LObject Instance", left + UI.metrics.contentPaddingX, 60 + UI.metrics.contentPaddingY, self.width - 2 * UI.metrics.contentPaddingX, Theme.color("textMuted"))

    Theme.setColor("textMuted")
    require("editor.ui").label("Transform", left + UI.metrics.contentPaddingX, 78 + UI.metrics.contentPaddingY, self.width - 2 * UI.metrics.contentPaddingX)

    if selectedLObject.transform then
        self:drawField("X", "x", X_FIELD_Y, selectedLObject, left)
        self:drawField("Y", "y", Y_FIELD_Y, selectedLObject, left)
        self:drawField("Rot Z°", "rotation", TRANSFORM_FIELDS.rotation, selectedLObject, left)
        self:drawField("Scale X", "scaleX", TRANSFORM_FIELDS.scaleX, selectedLObject, left)
        self:drawField("Scale Y", "scaleY", TRANSFORM_FIELDS.scaleY, selectedLObject, left)
    end
    if self.classInspector and self.classInspector.target then
        self.classInspector:layout(left, self.width, windowHeight)
        self.classInspector:draw()
    end

    love.graphics.pop()
end

return Inspector
