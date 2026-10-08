local UI = require("editor.ui")
local Theme = require("editor.theme")
local LuaClass = require("editor.lua_class")
local Dropdown = require("editor.ui.dropdown")
local IME = require("editor.ui.ime")
local Edit = require("editor.ui.text_edit")
local ClassInspector = {}
ClassInspector.__index = ClassInspector

function ClassInspector.new(project, root)
    return setmetatable({project = project, root = root, scroll = 0, expanded = {}}, ClassInspector)
end

function ClassInspector:setTarget(target)
    if self.target == target then return end
    self:commitEdit()
    self.target, self.scroll, self.error = target, 0, nil
    self:reload()
end

function ClassInspector:reload()
    if not self.target then self.class, self.dropdown, self.names = nil, nil, {}; return end
    local reference = self.target and self.target.data[self.target.referenceField]
    self.class, self.error = nil, nil
    if self.target.class then self.class = self.target.class
    elseif reference then
        self.class, self.error = LuaClass.load(self.project, reference, self.target.kind)
        if self.class and self.target.kind == "lobject" then
            local Definition = require("editor.object_definition")
            local target, err = Definition.inspectorTarget(self.project, {}, {class = self.class, properties = {}, components = {}}, nil, "Prefab")
            if target then self.class = target.class else self.class, self.error = nil, err end
        end
    end
    self.names = {}
    for name in pairs(self.class and self.class.properties or {}) do self.names[#self.names + 1] = name end
    table.sort(self.names)
    self:rebuildRows()
    self.dropdown = Dropdown.new(self.root, {}, reference or false, function(value) return self:selectParent(value) end)
    self.dropdown.hint = "Choose a Parent Class. None: use the built-in Level or LObject."
    self:updateOptions()
end

function ClassInspector:updateOptions()
    local options = {{label = "None", value = false}}
    local scripts, err = self.project:listScripts(self.target.kind)
    local current = self.target.data[self.target.referenceField]
    local found = not current
    for _, reference in ipairs(scripts or {}) do
        local id = self.project:getAssetId(reference) or reference
        options[#options + 1] = {label = reference, value = id}
        if id == current or reference == current then found = true; self.dropdown.value = id end
    end
    if not found then options[#options + 1] = {label = "Missing: " .. current, value = current} end
    self.dropdown.options = options
    if err then self.error = err end
end

function ClassInspector:selectParent(value)
    self:commitEdit()
    local class, err
    if value then class, err = LuaClass.load(self.project, value, self.target.kind) end
    if value and not class then self.error = err; return false end
    if class and self.target.kind == "lobject" then
        local target, targetError = require("editor.object_definition").inspectorTarget(self.project, {}, {class = class, properties = {}, components = {}}, nil, "Prefab")
        if not target then self.error = targetError; return false end
        class = target.class
    end
    self.target.data[self.target.referenceField] = value or nil
    self.target:setOverrides(LuaClass.compatibleOverrides(class, self.target:getOverrides()))
    self:reload()
    return true
end

function ClassInspector:setProperty(name, value)
    local declaration = self.class and self.class.properties[name]
    if not declaration or not LuaClass.validValue(declaration.type, value) then
        self.error = "Invalid value for " .. name
        return false
    end
    local overrides = self.target:getOverrides()
    if value == declaration.default then overrides[name] = nil else overrides[name] = value end
    self.target:setOverrides(overrides)
    self.error = nil
    return true
end

function ClassInspector:commitEdit()
    if not self.editing then return false end
    self.text, self.replace = IME.finish(self, self.text, self.replace)
    local name, text = self.editing, self.text
    self.editing = nil
    local declaration = self.class.properties[name]
    local value = declaration.type == "number" and tonumber(text) or text
    return self:setProperty(name, value)
end

function ClassInspector:cancelEdit() IME.cancel(self); self.editing = nil end
function ClassInspector:isEditing() return self.editing ~= nil end

function ClassInspector:propertyRect(name, top)
    local declaration = self.class.properties[name]
    local indent = declaration.component and 12 or 0
    local resetWidth = 26
    local width = self.width - 2 * UI.metrics.contentPaddingX - UI.metrics.buttonGap - resetWidth - 2 * indent
    if declaration.type == "boolean" then
        local value = self.target:getOverrides()[name]
        if value == nil then value = declaration.default end
        width = math.min(width, UI.buttonWidth(value and "True" or "False"))
    end
    return {x = self.left + UI.metrics.contentPaddingX + indent, y = top, w = math.max(0, width), h = 26}
end

function ClassInspector:resetRect(name, top)
    local width = 26
    local indent = self.class.properties[name].component and 12 or 0
    return {x = self.left + self.width - UI.metrics.contentPaddingX - width - indent, y = top, w = width, h = 26}
end
function ClassInspector:choices(name, value)
    local kind = self.class.properties[name].type
    local options = {{label = "None", value = false}}
    if kind == "object" then
        for _, object in ipairs(self.target.level and self.target.level.lobjects or {}) do
            options[#options + 1] = {label = "LObject " .. object.authoringId, value = object.authoringId}
        end
    elseif kind == "image" then
        local references = {}
        for reference in pairs(self.project.assetMetadata or {}) do
            if reference:match("^Assets/") and reference:lower():match("%.(.*)$") then
                local extension = reference:lower():match("%.([^%.]+)$")
                if ({png = true, jpg = true, jpeg = true, bmp = true, tga = true, gif = true})[extension] then references[#references + 1] = reference end
            end
        end
        table.sort(references)
        for _, reference in ipairs(references) do options[#options + 1] = {label = reference, value = self.project:getAssetId(reference) or reference} end
    end
    local found = false
    for _, option in ipairs(options) do if option.value == value then found = true end end
    if not found then options[#options + 1] = {label = "Missing: " .. tostring(value), value = value} end
    return Dropdown.new(self.root, options, value, function(selected) return self:setProperty(name, selected) end)
end

-- 컴포넌트 헤더와 프로퍼티의 높이가 달라 스크롤을 픽셀 단위로 관리한다.
function ClassInspector:rebuildRows()
    local groups, groupNames, rows, objectRows = {}, {}, {}, {}
    for component in pairs(self.class and self.class.componentTypes or {}) do
        groups[component] = {}; groupNames[#groupNames + 1] = component
    end
    for _, name in ipairs(self.names or {}) do
        local component = self.class.properties[name].component
        if component then
            if not groups[component] then groups[component] = {}; groupNames[#groupNames + 1] = component end
            groups[component][#groups[component] + 1] = name
        else objectRows[#objectRows + 1] = {name = name, height = 56} end
    end
    table.sort(groupNames)
    for _, component in ipairs(groupNames) do
        local header = {component = component, height = self.expanded[component] and 32 or 26}
        rows[#rows + 1] = header
        if self.expanded[component] then
            for _, name in ipairs(groups[component]) do rows[#rows + 1] = {name = name, height = 56} end
        end
        header.groupHeight = header.height + (self.expanded[component] and #groups[component] * 56 or 0)
        rows[#rows + 1] = {gap = true, height = 8}
    end
    for _, row in ipairs(objectRows) do rows[#rows + 1] = row end
    local offset = 0
    for _, row in ipairs(rows) do row.offset = offset; offset = offset + row.height end
    self.rows, self.totalHeight = rows, offset
    self.maxScroll = math.max(0, offset - (self.propertyHeight or 0))
    self.scroll = math.min(self.scroll, self.maxScroll)
end

function ClassInspector:ensurePropertyVisible(name)
    local declaration = assert(self.class.properties[name], "Missing property " .. name)
    if declaration.component then self.expanded[declaration.component] = true end
    self:rebuildRows()
    for _, row in ipairs(self.rows) do
        if row.name == name then
            self.scroll = math.max(0, math.min(self.maxScroll, math.max(row.offset + row.height - self.propertyHeight, math.min(self.scroll, row.offset))))
            return self:propertyRect(name, self.propertyTop + row.offset - self.scroll + 20)
        end
    end
end

function ClassInspector:layout(left, width, height)
    self.left, self.width = left, width
    if not self.dropdown then return end
    self.dropdown:setBounds(left + UI.metrics.contentPaddingX, 100 + UI.metrics.contentPaddingY, math.max(0, width - 2 * UI.metrics.contentPaddingX), 28)
    self.propertyTop = (self.target.instance and 334 or 170) + UI.metrics.contentPaddingY
    self.propertyHeight = math.max(0, height - self.propertyTop - 10)
    self:rebuildRows()
end

function ClassInspector:draw()
    if not self.target.instance then
        local label = self.target.getDisplayName and self.target:getDisplayName() or self.target.label
        if self.target.isDirty and self.target:isDirty() then label = label .. " *" end
        UI.label(label, self.left + UI.metrics.contentPaddingX, 44 + UI.metrics.contentPaddingY, self.width - 2 * UI.metrics.contentPaddingX)
        UI.text(self.target.label .. "  |  Ctrl+S: Save", self.left + UI.metrics.contentPaddingX, 60 + UI.metrics.contentPaddingY, self.width - 2 * UI.metrics.contentPaddingX, Theme.color("textMuted"))
        if not self.target.hideParent then
            UI.label("Parent Class", self.left + UI.metrics.contentPaddingX, 78 + UI.metrics.contentPaddingY, self.width - 2 * UI.metrics.contentPaddingX)
            self.dropdown:draw()
        end
    end
    if self.error then UI.text(self.error, self.left + UI.metrics.contentPaddingX, 138 + UI.metrics.contentPaddingY, self.width - 2 * UI.metrics.contentPaddingX, Theme.color("error")) end
    love.graphics.push("all")
    love.graphics.intersectScissor(self.left, self.propertyTop, self.width, self.propertyHeight)
    for _, row in ipairs(self.rows) do
        local name = row.name
        local y = self.propertyTop + row.offset - self.scroll
        if row.component and y + row.groupHeight > self.propertyTop and y < self.propertyTop + self.propertyHeight then
            local groupLeft, groupWidth = self.left + UI.metrics.contentPaddingX, self.width - 2 * UI.metrics.contentPaddingX
            if self.expanded[row.component] then
                Theme.setColor("surface")
                love.graphics.rectangle("fill", groupLeft, y, groupWidth, row.groupHeight, 4, 4)
                Theme.setColor("border")
                love.graphics.rectangle("line", groupLeft + 0.5, y + 0.5, groupWidth - 1, row.groupHeight - 1, 4, 4)
            end
            local label = row.component .. " (" .. self.class.componentTypes[row.component] .. ")"
            UI.button("", {x = groupLeft, y = y, w = groupWidth, h = 26}, false, "Click to expand or collapse component properties.")
            UI.chevron(groupLeft + 10, y + 13, self.expanded[row.component])
            UI.text(label, groupLeft + 26, y + (26 - love.graphics.getFont():getHeight()) / 2, groupWidth - 36)
        elseif name and y + row.height > self.propertyTop and y < self.propertyTop + self.propertyHeight then
            local declaration = self.class.properties[name]
            local value = self.target:getOverrides()[name]
            if value == nil then value = declaration.default end
            local indent = declaration.component and 12 or 0
            UI.label((declaration.field or name) .. " (" .. declaration.type .. ")", self.left + UI.metrics.contentPaddingX + indent, y, self.width - 2 * UI.metrics.contentPaddingX - indent)
            UI.hint({x = self.left + UI.metrics.contentPaddingX, y = y, w = self.width - 2 * UI.metrics.contentPaddingX, h = 20}, name .. ": " .. declaration.type .. ". Default: " .. tostring(declaration.default))
            local rect = self:propertyRect(name, y + 20)
            if declaration.type == "object" or declaration.type == "image" then
                local choice = self:choices(name, value)
                choice:setBounds(rect.x, rect.y, rect.w, rect.h)
                choice:draw()
            elseif declaration.type == "boolean" then UI.button(value and "True" or "False", rect, false, "Toggle " .. name .. ". Ctrl+S: save.")
            else UI.field(self.editing == name and IME.display(self, self.text, self.replace) or tostring(value),
                rect, self.editing == name, self.editing == name and self.composition, self) end
            UI.resetButton(self:resetRect(name, y + 20))
        end
    end
    love.graphics.pop()
end

function ClassInspector:mousepressed(x, y, button)
    if button ~= 1 then return true end
    local dropdown = self.dropdown
    if not self.target.hideParent and dropdown:containsPoint(x, y) then
        self:commitEdit()
        self:updateOptions()
        return dropdown:dispatch("mousepressed", x, y, button)
    end
    if y < self.propertyTop or y >= self.propertyTop + self.propertyHeight then self:commitEdit(); return true end
    for _, row in ipairs(self.rows) do
        local name = row.name
        local top = self.propertyTop + row.offset - self.scroll
        if row.component and y >= top and y < top + row.height then
            self:commitEdit()
            self.expanded[row.component] = not self.expanded[row.component]
            self:rebuildRows()
            return true
        end
        top = top + 20
        if name and y >= top and y < top + 26 then
            local declaration = self.class.properties[name]
            if UI.contains(x, y, self:resetRect(name, top)) then
                self:commitEdit()
                return self:setProperty(name, declaration.default)
            end
            if not UI.contains(x, y, self:propertyRect(name, top)) then return true end
            if self.editing == name then
                self.text, self.replace = IME.finish(self, self.text, self.replace)
                Edit.press(self, self.text, self:propertyRect(name, top), x, false)
                self.replace = false
                return true, true
            end
            self:commitEdit()
            local value = self.target:getOverrides()[name]
            if value == nil then value = declaration.default end
            if declaration.type == "object" or declaration.type == "image" then
                local choice = self:choices(name, value)
                local rect = self:propertyRect(name, top)
                choice:setBounds(rect.x, rect.y, rect.w, rect.h)
                self.propertyChoice = choice
                return choice:dispatch("mousepressed", x, y, button)
            end
            if declaration.type == "boolean" then return self:setProperty(name, not value) end
            self.editing, self.text, self.replace = name, tostring(value), true
            Edit.begin(self, self.text, true)
            Edit.press(self, self.text, self:propertyRect(name, top), x, true)
            return true, true
        end
    end
    self:commitEdit()
    return true
end

function ClassInspector:mousemoved(x) return Edit.move(self, x) end
function ClassInspector:mousereleased() Edit.release(self); return true end
function ClassInspector:keypressed(key)
    if not self.editing then return false end
    if IME.handlesKey(self, key) then return true end
    if IME.endsComposition(key) then self.text, self.replace = IME.finish(self, self.text, self.replace) end
    if key == "return" or key == "kpenter" then self:commitEdit()
    elseif key == "escape" then self:cancelEdit()
    else self.text, self.replace = UI.editKey(self.text, key, self.replace, self) end
    return true
end
function ClassInspector:textinput(text)
    if not self.editing then return false end
    self.text, self.replace = IME.input(self, self.text, text, self.replace)
    return true
end
function ClassInspector:textedited(text)
    if not self.editing then return false end
    IME.edited(self, text)
    return true
end
function ClassInspector:wheelmoved(amount)
    self:commitEdit()
    self.scroll = math.floor(math.max(0, math.min(self.maxScroll or 0, self.scroll - amount * 56)))
end
return ClassInspector
