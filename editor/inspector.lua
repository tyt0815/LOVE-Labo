local Theme = require("editor.theme")
local UI = require("editor.ui")
local IME = require("editor.ui.ime")
local Edit = require("editor.ui.text_edit")
local PropertyLayout = require("editor.ui.property_layout")
local Inspector = {}
Inspector.__index = Inspector

local DEFAULT_WIDTH = 300

local TRANSFORM_ORDER = {"x", "y", "rotationX", "rotationY", "rotation", "scaleX", "scaleY"}
local TRANSFORM_FIELDS = {}
for i, field in ipairs(TRANSFORM_ORDER) do TRANSFORM_FIELDS[field] = i end
local TRANSFORM_LABELS = {x = "X", y = "Y", rotationX = "Rot X°", rotationY = "Rot Y°", rotation = "Rot Z°", scaleX = "Scale X", scaleY = "Scale Y"}
local TRANSFORM_TOP = 78 + UI.metrics.contentPaddingY

function Inspector.new(level, width)
    local self = setmetatable({}, Inspector)

    self.level = level
    self.width = width or DEFAULT_WIDTH

    -- Inspector의 text edit 상태는 authoring data와 분리된 transient Editor state다.
    self.activeField = nil
    self.editingLObject = nil
    self.editText = ""
    self.replaceOnTextInput = false
    self.transformExpanded = true

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

    if not self.transformExpanded then return nil end
    for _, field in ipairs(TRANSFORM_ORDER) do
        if UI.contains(x, y, self:fieldRect(field, windowWidth)) then return field end
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
    Edit.begin(self, self.editText, true)

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
        lobject.transform[field] = field:match("^rotation") and require("core.transform").normalizeRotation(value) or value
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
    if selectedLObject and UI.contains(x, y, {x = windowWidth - self.width + UI.metrics.contentPaddingX, y = TRANSFORM_TOP, w = self.width - 2 * UI.metrics.contentPaddingX, h = PropertyLayout.headerHeight}) and button == 1 then
        self:commitEdit()
        self.transformExpanded = not self.transformExpanded
        if self.classInspector and self.classInspector.target then self.classInspector:layout(windowWidth - self.width, self.width, self.height or love.graphics.getHeight(), self:getPropertyTop()) end
        return true
    end
    if selectedLObject and self.classInspector and self.classInspector.target and y >= self:getPropertyTop() then
        if self.activeField then self:commitEdit() end
        return self.classInspector:mousepressed(x, y, button)
    end

    -- Inspector 영역의 mouse press는 button 종류와 관계없이 소비한다.
    if button ~= 1 then
        return true
    end

    if selectedLObject and self.transformExpanded then
        for _, field in ipairs(TRANSFORM_ORDER) do
            local _, _, reset = PropertyLayout.cells(windowWidth - self.width, self.width, self:fieldRect(field, windowWidth).y - 3)
            if UI.contains(x, y, reset) then
                self:commitEdit()
                selectedLObject.transform[field] = field:match("^scale") and 1 or 0
                return true
            end
        end
    end

    local field = self:getFieldAtPosition(x, y, windowWidth)

    if not field or not selectedLObject then
        self:commitEdit()
        return true
    end

    if self.activeField == field and self.editingLObject == selectedLObject then
        self.editText, self.replaceOnTextInput = IME.finish(self, self.editText, self.replaceOnTextInput)
        Edit.press(self, self.editText, self:fieldRect(field, windowWidth), x, false)
        self.replaceOnTextInput = false
        return true, true
    end

    self:commitEdit()
    self:beginEdit(field, selectedLObject)
    Edit.press(self, self.editText, self:fieldRect(field, windowWidth), x, true)
    return true, true
end

function Inspector:fieldRect(field, windowWidth)
    local _, rect = PropertyLayout.cells(windowWidth - self.width, self.width, TRANSFORM_TOP + 32 + (TRANSFORM_FIELDS[field] - 1) * PropertyLayout.rowHeight)
    return rect
end
function Inspector:getPropertyTop()
    return TRANSFORM_TOP + (self.transformExpanded and 32 + #TRANSFORM_ORDER * PropertyLayout.rowHeight or PropertyLayout.headerHeight) + 8
end
function Inspector:mousemoved(x)
    if self.classInspector and self.classInspector:isEditing() then return self.classInspector:mousemoved(x) end
    return Edit.move(self, x)
end
function Inspector:mousereleased() Edit.release(self); if self.classInspector then self.classInspector:mousereleased() end; return true end

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

    if key == "return" or key == "kpenter" then
        self:commitEdit()
        return true
    end

    if key == "escape" then
        self:cancelEdit()
        return true
    end

    self.editText, self.replaceOnTextInput = UI.editKey(self.editText, key, self.replaceOnTextInput, self)
    -- 편집 중 다른 key도 Scene View shortcut으로 전달하지 않는다.
    return true
end

function Inspector:drawField(label, field, y, selectedLObject, left)
    local labelRect, rect, reset = PropertyLayout.cells(left, self.width, y - 3)
    local isActive =
        self.activeField == field
        and self.editingLObject == selectedLObject

    UI.text(label, labelRect.x, labelRect.y, labelRect.w)

    local text

    if isActive then
        text = IME.display(self, self.editText, self.replaceOnTextInput)
    else
        text = string.format("%.2f", selectedLObject.transform[field])
    end

    UI.field(text, rect, isActive, isActive and self.composition, self)
    UI.resetButton(reset)
end

function Inspector:draw(selectedLObject)
    local windowWidth, windowHeight = love.graphics.getDimensions()
    windowHeight = self.height or windowHeight
    local left = windowWidth - self.width

    love.graphics.push("all")
    love.graphics.intersectScissor(left, 0, self.width, windowHeight)

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

    if selectedLObject.transform then
        PropertyLayout.group(left, self.width, TRANSFORM_TOP, self:getPropertyTop() - TRANSFORM_TOP - 8, "Transform", self.transformExpanded)
        if self.transformExpanded then
            for _, field in ipairs(TRANSFORM_ORDER) do
                self:drawField(TRANSFORM_LABELS[field], field, self:fieldRect(field, windowWidth).y, selectedLObject, left)
            end
        end
    end
    if self.classInspector and self.classInspector.target then
        self.classInspector:layout(left, self.width, windowHeight, self:getPropertyTop())
        self.classInspector:draw()
    end

    love.graphics.pop()
end

return Inspector
