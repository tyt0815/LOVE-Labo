local Schema = require("core.PropertySchema")
local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local LuaClass = require("editor.LuaClass")
local Dropdown = require("editor.ui.Dropdown")
local Ime = require("editor.ui.Ime")
local Edit = require("editor.ui.TextEdit")
local PropertyLayout = require("editor.ui.PropertyLayout")
local NumberDrag = require("editor.ui.NumberDrag")
local Thumbnail = require("editor.AssetThumbnail")
local Scrollbar = require("editor.ui.Scrollbar")
local ClassInspector = {}
ClassInspector.__index = ClassInspector
local TRANSFORM_LABELS = {x = "X", y = "Y", rotationX = "Rot X°", rotationY = "Rot Y°", rotation = "Rot Z°", scaleX = "Scale X", scaleY = "Scale Y"}

function ClassInspector.new(project, root)
    local self = setmetatable({project = project, root = root, scroll = 0, groupExpanded = {}, thumbnails = Thumbnail.new(project)}, ClassInspector)
    self.scrollbar = Scrollbar.new(function() return self.scroll end, function(value)
        self.scroll = math.floor(value + 0.5); self:layoutComponentTree()
    end)
    self.objectTreeHeight, self.componentTreeHeight = 78, 78
    return self
end

local function resourceName(reference)
    return tostring(reference):match("([^/]+)$") or tostring(reference)
end

function ClassInspector:thumbnail(value)
    if not value then return nil end
    local reference = self.project:getAssetReference(value)
    if not reference then return nil end
    return self.thumbnails:get({type = "file", name = resourceName(reference), reference = reference})
end

function ClassInspector:reveal(value)
    self:commitEdit()
    if value and self.onReveal then
        local ok, err = self.onReveal(value)
        if not ok then self.error = err end
    end
    return true
end

function ClassInspector:setTarget(target)
    if self.target == target then return end
    self:commitEdit()
    local key = target and (target.documentKey or target.data)
    if key ~= self.treeLayoutKey then
        self.objectTreeHeight, self.componentTreeHeight, self.objectTree = 78, 78, nil
    end
    self.treeLayoutKey = key
    self.target, self.scroll, self.error = target, 0, nil
    self.selectedComponent, self.tree, self.treeFocused = nil, nil, false
    self:reload()
end

function ClassInspector:reload()
    self.thumbnails:clear()
    if not self.target then self.class, self.dropdown, self.tree, self.names = nil, nil, nil, {}; return end
    if self.target.reloadTarget then
        local fresh, err = self.target.reloadTarget()
        if not fresh then self.error = err; return end
        for key, value in pairs(fresh) do self.target[key] = value end
    end
    local reference = self.target and self.target.data[self.target.referenceField]
    self.class, self.preview, self.error = nil, nil, nil
    if self.target.class then self.class, self.preview = self.target.class, self.target.preview
    elseif self.target.kind == "lobject" then
        local Definition = require("editor.ObjectDefinition")
        local definition, err = Definition.resolve(self.project, reference, nil, self.target.parentOwnerId)
        local target
        if definition then target, err = Definition.inspectorTarget(self.project, {}, definition, nil, "Prefab") end
        if target then self.class, self.preview = target.class, target.preview else self.error = err end
    elseif reference then self.class, self.error = LuaClass.load(self.project, reference, self.target.kind) end
    if self.target.mainCameraDetails then
        local properties = {}
        for name, declaration in pairs(self.class and self.class.properties or {}) do properties[name] = declaration end
        properties["$mainCamera"] = {type = "object", default = false, field = "Main Camera", group = "Camera"}
        self.class = {properties = properties, className = self.class and (self.class.className or LuaClass.name(self.class)) or "Level"}
    end
    if not self.preview then self.selectedComponent = nil end
    self.allNames = {}
    for name in pairs(self.class and self.class.properties or {}) do self.allNames[#self.allNames + 1] = name end
    table.sort(self.allNames)
    local oldTree = self.tree
    self.tree = nil
    if self.preview then
        if self.selectedComponent and not self.preview.components[self.selectedComponent] then self.selectedComponent = nil end
        local label = self.target.getDisplayName and self.target:getDisplayName() or self.target.label
        self.tree = require("editor.ui.ComponentTree").new(self.preview, label, function(component) self:selectComponent(component) end, true)
        if oldTree then self.tree.expanded, self.tree.scroll = oldTree.expanded, oldTree.scroll end
        self.tree:reveal(self.selectedComponent)
    end
    self:rebuildRows()
    local oldObjectTree = self.objectTree
    self.objectTree = nil
    if self.target.getObjectHierarchy then
        local hierarchy = self.target.getObjectHierarchy()
        if hierarchy then
            self.objectTree = require("editor.ui.ObjectTree").new(hierarchy, self.target.onSelectObject, self.target.onObjectContext)
            if oldObjectTree then
                self.objectTree.expanded, self.objectTree.scroll = oldObjectTree.expanded, oldObjectTree.scroll
                self.objectTree:rebuild()
            end
            self.objectTree.selected = self.target.selectedObjectPath or "root"
        end
    end
    self.dropdown = Dropdown.new(self.root, {}, reference or false, function(value) return self:selectParent(value) end)
    self.dropdown.hint = "Choose a Parent Class. None: use the built-in Level or LObject."
    self:updateOptions()
end

function ClassInspector:selectComponent(component)
    self:commitEdit()
    assert(not component or self.preview and self.preview.components[component], "Missing Inspector component")
    self.selectedComponent, self.scroll = component, 0
    if self.tree then self.tree:reveal(component) end
    self:rebuildRows()
    if self.onScopeChanged then self.onScopeChanged() end
    if self.left then self:layoutComponentTree() end
    return true
end

function ClassInspector:treeBottom()
    if not self.tree then return nil end
    return (self.top or 0) + 100 + Ui.METRICS.contentPaddingY + math.min(156, math.max(26, #self.tree.nodes * 26))
end
function ClassInspector:parentVisible() return self.target and not self.target.hideParent end

function ClassInspector:updateOptions()
    local options = {{label = "None", value = false}}
    local scripts, err = self.project:listScripts(self.target.kind)
    local current = self.target.data[self.target.referenceField]
    local found = not current
    for _, reference in ipairs(scripts or {}) do
        local id = self.project:getAssetId(reference) or reference
        options[#options + 1] = {label = resourceName(reference), value = id}
        if id == current or reference == current then found = true; self.dropdown.value = id end
    end
    if self.target.kind == "lobject" and not self.target.hideParent then
        local paths = {}
        for reference in pairs(self.project.assetMetadata or {}) do
            if reference:match("^Assets/.+%.prefab$") then paths[#paths + 1] = reference end
        end
        table.sort(paths)
        for _, reference in ipairs(paths) do
            local id = self.project:getAssetId(reference)
            if require("editor.ObjectDefinition").resolve(self.project, id, nil, self.target.parentOwnerId) then
                options[#options + 1] = {label = resourceName(reference), value = id}
                if id == current then found = true end
            end
        end
    end
    if not found then options[#options + 1] = {label = "Missing: " .. resourceName(current), value = current} end
    self.dropdown.options = options
    if err then self.error = err end
end

function ClassInspector:selectParent(value)
    self:commitEdit()
    local snapshot = self.target.getSnapshot and self.target.getSnapshot()
    local class, err, parentTarget
    if value then
        if self.target.kind == "lobject" then
            local valid, parentError = require("project.PrefabHierarchy").resolve(self.project, value, nil, self.target.parentOwnerId)
            if not valid then self.error = parentError; return false end
            local Definition = require("editor.ObjectDefinition")
            local definition
            definition, err = Definition.resolve(self.project, value, nil, self.target.parentOwnerId)
            if not definition then self.error = err; return false end
            local target
            target, err = Definition.inspectorTarget(self.project, {transform = self.target.data.transform}, definition, nil, "Prefab")
            if target then class, parentTarget = target.class, target end
        else class, err = LuaClass.load(self.project, value, self.target.kind) end
        if not class then self.error = err; return false end
    end
    if self.target.setParentReference then self.target.setParentReference(value)
    else self.target.data[self.target.referenceField] = value or nil end
    self.target:setOverrides(LuaClass.compatibleOverrides(class, self.target:getOverrides()), parentTarget)
    if self.target.reloadTarget then
        local target, reloadError = self.target.reloadTarget()
        if not target then
            if snapshot then self.target.restoreSnapshot(snapshot); self:reload() end
            self.error = reloadError; return false
        end
        if self.onTargetReloaded then self.onTargetReloaded(target) else self:setTarget(target) end
        return true
    end
    self:reload()
    return true
end

function ClassInspector:setProperty(name, value)
    if name == "$mainCamera" and self.target.mainCameraDetails then
        if value == false then return self.target:setMainCamera(nil) end
        self.error = "Use the eyedropper to select a camera instance"; return false
    end
    local declaration = self.class and self.class.properties[name]
    if not declaration or not LuaClass.validValue(declaration.type, value) then
        self.error = "Invalid value for " .. name
        return false
    end
    if declaration.sceneTransform then
        local component = self.preview.components[declaration.component]
        local transform = require("core.Transform").copy(component.transform)
        transform[declaration.field] = value
        local valid, err = require("core.Transform").copy(transform)
        if not valid then self.error = err; return false end
        value = valid[declaration.field]
    end
    if (declaration.type == "image" or Schema.isTemplate(declaration.type)) and value ~= false then
        local reference, err = self.project:getAssetReference(value)
        if not reference then self.error = err; return false end
        if Schema.isTemplate(declaration.type) then
            local template
            template, err = require("project.LObjectTemplate").resolve(self.project, value)
            if not template then self.error = err; return false end
        else
            local extension = reference:lower():match("%.([^%.]+)$")
            if not reference:match("^Assets/") or not ({png = true, jpg = true, jpeg = true, bmp = true, tga = true, gif = true})[extension or ""] then
                self.error = "Expected an image resource"; return false
            end
            local ok, result = pcall(function()
                local path = assert(self.project:resolveAssetFile(value))
                local bytes = assert(self.project:readAsset(value))
                local pixels = love.image.newImageData(love.filesystem.newFileData(bytes, path)); pixels:release()
            end)
            if not ok then self.error = tostring(result); return false end
        end
        value = self.project:getAssetId(reference) or reference
    elseif declaration.type == "object" and value ~= false then
        local found = false
        for _, object in ipairs(self.target.level and self.target.level.lobjects or {}) do
            if object.authoringId == value then found = true end
        end
        if not found then self.error = "Instance must belong to the current level"; return false end
    end
    local overrides = self.target:getOverrides()
    if value == declaration.default then overrides[name] = nil else overrides[name] = value end
    self.target:setOverrides(overrides)
    self.error = nil
    return true
end

function ClassInspector:commitEdit()
    if not self.editing then return false end
    NumberDrag.finish(self)
    self.text, self.replace = Ime.finish(self, self.text, self.replace)
    local name, text = self.editing, self.text
    self.editing = nil
    local declaration = self.class.properties[name]
    local value = declaration.type == "number" and tonumber(text) or text
    local updated = self:setProperty(name, value)
    if self.onCommitEdit then self.onCommitEdit() end
    return updated
end

function ClassInspector:cancelEdit() NumberDrag.cancel(self); Ime.cancel(self); self.editing = nil end
function ClassInspector:isEditing() return self.editing ~= nil end

function ClassInspector:propertyRect(name, top)
    if self.class.properties[name].type == "image" then return self:imageRects(top - 3).selector end
    if Schema.isTemplate(self.class.properties[name].type) or self.class.properties[name].type == "object" then
        local rect = self:referenceRects(top - 3).selector
        return rect
    end
    local _, rect = PropertyLayout.cells(self.left, self.width, top - 3)
    return rect
end

function ClassInspector:resetRect(name, top)
    if self.class.properties[name].type == "image" then return self:imageRects(top - 3).reset end
    local _, _, rect = PropertyLayout.cells(self.left, self.width, top - 3)
    return rect
end
function ClassInspector:imageRects(top)
    local _, field, reset = PropertyLayout.cells(self.left, self.width, top)
    local size = math.min(56, math.max(0, field.w * 0.4))
    local selectorX = field.x + size + 6
    return {preview = {x = field.x, y = top + (64 - size) / 2, w = size, h = size},
        selector = {x = selectorX, y = top + 3, w = math.max(0, field.x + field.w - selectorX), h = 26},
        assign = {x = selectorX, y = top + 35, w = 26, h = 26},
        browse = {x = selectorX + 30, y = top + 35, w = 26, h = 26}, reset = reset}
end

function ClassInspector:referenceRects(top)
    local _, field, reset = PropertyLayout.cells(self.left, self.width, top)
    local right = field.x + field.w
    return {selector = {x = field.x, y = field.y, w = math.max(0, field.w - 60), h = field.h},
        assign = {x = right - 56, y = field.y, w = 26, h = 26},
        browse = {x = right - 26, y = field.y, w = 26, h = 26}, reset = reset}
end

function ClassInspector:parentBrowseRect()
    return {x = self.left + (self.contentWidth or self.width) - Ui.METRICS.contentPaddingX - 26, y = self.dropdown.y, w = 26, h = 26}
end

function ClassInspector:saveRect()
    local width = Ui.buttonWidth("Save")
    return {x = self.left + self.width - Ui.METRICS.contentPaddingX - width, y = (self.top or 0) + 8, w = width, h = 26}
end
function ClassInspector:parentPickRect()
    local rect = self:parentBrowseRect()
    return {x = rect.x - 30, y = rect.y, w = 26, h = 26}
end
function ClassInspector:objectLabel(value, name)
    if value == false then return name == "$mainCamera" and "Auto" or "None" end
    for _, object in ipairs(self.target.level and self.target.level.lobjects or {}) do
        if object.authoringId == value then
            local label = object.name or "LObject " .. tostring(value)
            if name == "$mainCamera" then label = label .. " / " .. self.target.data.mainCamera.component end
            return label
        end
    end
    return "Missing: " .. tostring(value)
end
function ClassInspector:pickCandidate(name, reference, object)
    if name == "$parent" then
        reference = reference or object and object.definitionReference
        if not reference then return nil, "Select a Parent Class asset or an instance with a source" end
        if self.target.kind == "lobject" then
            local definition, err = require("project.ObjectDefinition").resolve(self.project, reference, nil, self.target.parentOwnerId)
            if not definition then return nil, err end
        else
            local class, err = LuaClass.load(self.project, reference, self.target.kind)
            if not class then return nil, err end
        end
        local path, err = self.project:getAssetReference(reference)
        if not path then return nil, err end
        return self.project:getAssetId(path) or path
    end
    local declaration = self.class.properties[name]
    if not declaration then return nil, "Property no longer exists" end
    if declaration.type == "object" then
        if not object or not self.target.level then return nil, "Select an instance in the current level" end
        for _, current in ipairs(self.target.level.lobjects) do if current == object then return object.authoringId end end
        return nil, "Instance must belong to the current level"
    end
    if Schema.isTemplate(declaration.type) then
        reference = reference or object and object.definitionReference
        if not reference then return nil, "Select an LObject Lua Class, Prefab or sourced instance" end
        local template, err = require("project.LObjectTemplate").resolve(self.project, reference)
        return template and template.reference or nil, err
    end
    if declaration.type == "image" then
        if not reference then return nil, "Select an image asset" end
        local path, err = self.project:getAssetReference(reference)
        local extension = path and path:lower():match("%.([^%.]+)$")
        if not path or not path:match("^Assets/") or not ({png = true, jpg = true, jpeg = true, bmp = true, tga = true, gif = true})[extension or ""] then return nil, err or "Select an image asset" end
        return self.project:getAssetId(path) or path
    end
    return nil, "This property cannot be picked"
end
function ClassInspector:applyPicked(name, value)
    if name == "$parent" then return self:selectParent(value) end
    return self:setProperty(name, value)
end
function ClassInspector:assetDropTarget() return false, nil, "Use the eyedropper to assign resources" end
function ClassInspector:dropAsset() self.error = "Use the eyedropper to assign resources"; return false end

function ClassInspector:choices(name, value)
    local kind = self.class.properties[name].type
    local options = {{label = "None", value = false}}
    if kind == "object" then
        for _, object in ipairs(self.target.level and self.target.level.lobjects or {}) do
            options[#options + 1] = {label = "LObject " .. object.authoringId, value = object.authoringId}
        end
    elseif kind == "image" or Schema.isTemplate(kind) then
        local references = {}
        for reference in pairs(self.project.assetMetadata or {}) do
            if reference:lower():match("%.(.*)$") then
                local extension = reference:lower():match("%.([^%.]+)$")
                if kind == "image" and reference:match("^Assets/") and ({png = true, jpg = true, jpeg = true, bmp = true, tga = true, gif = true})[extension]
                    or Schema.isTemplate(kind) and require("project.LObjectTemplate").source(self.project, reference) then references[#references + 1] = reference end
            end
        end
        table.sort(references)
        for _, reference in ipairs(references) do options[#options + 1] = {label = resourceName(reference), value = self.project:getAssetId(reference) or reference} end
    end
    local found = false
    for _, option in ipairs(options) do if option.value == value then found = true end end
    if not found then options[#options + 1] = {label = "Missing: " .. resourceName(value), value = value} end
    local dropdown = Dropdown.new(self.root, options, value, function(selected) return self:setProperty(name, selected) end)
    if kind == "image" then
        dropdown.rowHeight, dropdown.menuWidth = PropertyLayout.ROW_HEIGHT * 2, 300
        dropdown.beginMenuDraw = function() self.thumbnails:beginFrame() end
        dropdown.drawOption = function(option, rect, active)
            Ui.button("", rect, active, "Select " .. option.label .. ". Enter: apply.")
            local size = math.min(80, rect.h - 12)
            Ui.thumbnail(self:thumbnail(option.value), {x = rect.x + 6, y = rect.y + 6, w = size, h = size})
            Ui.text(option.label, rect.x + size + 16, rect.y + (rect.h - love.graphics.getFont():getHeight()) / 2, math.max(0, rect.w - size - 22))
        end
    end
    return dropdown
end

-- 선택 대상의 그룹은 같은 깊이로 배치하고, 이미지 행을 포함해 픽셀 단위로 스크롤한다.
function ClassInspector:rebuildRows()
    local rows = {}
    self.names = {}
    if self.target then
        rows[#rows + 1] = {summary = true, height = 64}
        if self.objectTree then rows[#rows + 1] = {objectTree = true, height = self.objectTreeHeight + 12} end
        if self:parentVisible() then rows[#rows + 1] = {parentClass = true, height = 48} end
    end
    local function addScope(component)
        local groups, groupNames = {}, {}
        local defaultGroup = component and self.class.componentTypes[component]
            or self.class and (self.class.className or LuaClass.name(self.class)) or "LObject"
        for _, name in ipairs(self.allNames or {}) do
            local declaration = self.class.properties[name]
            local belongs = component and declaration.component == component and not declaration.rootTransform
                or not component and (not declaration.component or declaration.rootTransform)
            if belongs then
                self.names[#self.names + 1] = name
                local group = declaration.rootTransform and "Transform" or declaration.group or defaultGroup
                if not groups[group] then groups[group] = {}; groupNames[#groupNames + 1] = group end
                groups[group][#groups[group] + 1] = name
            end
        end
        if #groupNames == 0 and not component and self.class then groups[defaultGroup] = {}; groupNames[1] = defaultGroup end
        table.sort(groupNames, function(a, b)
            if a == b then return false end
            if a == "Transform" then return true end
            if b == "Transform" then return false end
            if a == defaultGroup then return true end
            if b == defaultGroup then return false end
            return a < b
        end)
        local rank = {}; for index, field in ipairs(require("core.Transform").ORDER) do rank[field] = index end
        for _, group in ipairs(groupNames) do
            table.sort(groups[group], function(a, b)
                local left, right = self.class.properties[a], self.class.properties[b]
                local first, second = left.sceneTransform and rank[left.field], right.sceneTransform and rank[right.field]
                if first and second then return first < second end
                if first or second then return first ~= nil and first ~= false end
                return a < b
            end)
            local key = (component and "component:" .. component or "object") .. "/" .. group
            local header = {header = true, label = group, groupKey = key, height = PropertyLayout.HEADER_HEIGHT, groupHeight = PropertyLayout.HEADER_HEIGHT}
            rows[#rows + 1] = header
            if self.groupExpanded[key] ~= false then
                for _, name in ipairs(groups[group]) do
                    local row = {name = name, height = PropertyLayout.ROW_HEIGHT * (self.class.properties[name].type == "image" and 2 or 1)}
                    rows[#rows + 1] = row; header.groupHeight = header.groupHeight + row.height
                end
            end
            rows[#rows + 1] = {gap = true, height = 8}
        end
    end
    addScope(nil)
    if self.tree then
        rows[#rows + 1] = {componentTree = true, height = 36 + self.componentTreeHeight}
        if self.selectedComponent then addScope(self.selectedComponent) end
    end
    local offset = 0
    for _, row in ipairs(rows) do row.offset = offset; offset = offset + row.height end
    self.rows, self.totalHeight = rows, offset
    self.maxScroll = math.max(0, offset - (self.propertyHeight or 0))
    self.scroll = math.min(self.scroll, self.maxScroll)
    if self.left then self.scrollbar:layout({x = self.left + self.width - 12, y = self.propertyTop or 0,
        w = Scrollbar.WIDTH, h = self.propertyHeight or 0}, self.totalHeight, self.propertyHeight or 0) end
    self.contentWidth = self.width and self.width - (self.scrollbar.visible and Scrollbar.WIDTH or 0)
end

function ClassInspector:ensurePropertyVisible(name)
    local declaration = assert(self.class.properties[name], "Missing property " .. name)
    local component = not declaration.rootTransform and declaration.component or nil
    if component and component ~= self.selectedComponent then self:selectComponent(component) end
    local group = declaration.rootTransform and "Transform" or declaration.group or (component and self.class.componentTypes[component]
        or self.class.className or LuaClass.name(self.class) or "LObject")
    self.groupExpanded[(component and "component:" .. component or "object") .. "/" .. group] = true
    self:rebuildRows()
    for _, row in ipairs(self.rows) do
        if row.name == name then
            self.scroll = math.max(0, math.min(self.maxScroll, math.max(row.offset + row.height - self.propertyHeight, math.min(self.scroll, row.offset))))
            self:layoutComponentTree()
            return self:propertyRect(name, self.propertyTop + row.offset - self.scroll + 3)
        end
    end
end

function ClassInspector:layout(left, width, height, propertyTop, top)
    self.left, self.width = left, width
    self.layoutHeight = height
    self.top = top or self.top or 0
    if not self.dropdown then return end
    self.propertyTop = self.top + 36 + Ui.METRICS.contentPaddingY
    self.propertyBottom = height - 10
    self.propertyHeight = math.max(0, self.propertyBottom - self.propertyTop - (self.error and 32 or 0))
    self:rebuildRows()
    self:layoutComponentTree()
end
function ClassInspector:layoutComponentTree()
    for _, row in ipairs(self.rows) do
        local y = self.propertyTop + row.offset - self.scroll
        local width = self.width - 2 * Ui.METRICS.contentPaddingX - (self.scrollbar.visible and Scrollbar.WIDTH or 0)
        if row.objectTree then self.objectTree:setBounds(self.left + Ui.METRICS.contentPaddingX, y, width, self.objectTreeHeight)
        elseif row.parentClass then self.dropdown:setBounds(self.left + self.width / 2 + 4, y, math.max(0, self.width / 2 - Ui.METRICS.contentPaddingX - 64 - (self.width - (self.contentWidth or self.width))), 28)
        end
        if row.componentTree then
            self.tree:setBounds(self.left + Ui.METRICS.contentPaddingX, y + 30, width, self.componentTreeHeight)
        end
    end
end
function ClassInspector:treeGrip(tree)
    return {x = tree.x, y = tree.y + tree.height, w = tree.width, h = 6}
end
function ClassInspector:resizeAt(x, y)
    if self.treeResize then return self.treeResize.kind end
    if y < self.propertyTop or y >= self.propertyTop + self.propertyHeight then return end
    if self.objectTree and Ui.contains(x, y, self:treeGrip(self.objectTree)) then return "object" end
    if self.tree and y >= self.propertyTop and y < self.propertyTop + self.propertyHeight
        and Ui.contains(x, y, self:treeGrip(self.tree)) then return "component" end
end
function ClassInspector:isPointerActive()
    return self.treeResize or self.scrollbar.drag or self.tree and self.tree.scrollbar.drag
        or self.objectTree and self.objectTree.scrollbar.drag
end
function ClassInspector:treeContains(tree, x, y)
    return tree and y >= self.propertyTop and y < self.propertyTop + self.propertyHeight and tree:containsPoint(x, y)
end

function ClassInspector:targetKind()
    if self.target.kind == "lobject" then
        local name = self.class and (self.class.className or LuaClass.name(self.class)) or "LObject"
        return (name or "LObject") .. " Prefab"
    end
    return self.target.label
end
function ClassInspector:draw()
    self.thumbnails:beginFrame()
    local propertyHeight = math.max(0, self.propertyBottom - self.propertyTop - (self.error and 32 or 0))
    if propertyHeight ~= self.propertyHeight then self.propertyHeight = propertyHeight; self:rebuildRows() end
    if not self.target.instance and self.onSave then Ui.button("Save", self:saveRect(), false, "Save this document", true) end
    self:layoutComponentTree()
    love.graphics.push("all")
    love.graphics.intersectScissor(self.left, self.propertyTop, self.width, self.propertyHeight)
    for _, row in ipairs(self.rows) do
        local name = row.name
        local y = self.propertyTop + row.offset - self.scroll
        if row.summary then
            local label = self.target.getDisplayName and self.target:getDisplayName() or self.target.data.name or self.target.label
            local kind = self:targetKind()
            if self.target.instance then
                label = self.target.data.name or "LObject " .. tostring(self.target.data.authoringId)
                local reference = self.target.data.definitionReference and self.project:getAssetReference(self.target.data.definitionReference)
                kind = (reference and reference:match("([^/]+)%.[^.]+$") or "LObject") .. " Instance"
            elseif self.target.isDirty and self.target:isDirty() then label = label .. " *" end
            Ui.label(label, self.left + Ui.METRICS.contentPaddingX, y + 8, self.width - 2 * Ui.METRICS.contentPaddingX)
            Ui.text(kind, self.left + Ui.METRICS.contentPaddingX, y + 24, self.width - 2 * Ui.METRICS.contentPaddingX, Theme.color("textMuted"))
        elseif row.objectTree then
            self.objectTree:draw(); Ui.resizeGrip(self:treeGrip(self.objectTree))
        elseif row.parentClass then
            Ui.label("Parent Class", self.left + Ui.METRICS.contentPaddingX + 12, self.dropdown.y + 6, self.width / 2 - Ui.METRICS.contentPaddingX - 20)
            self.dropdown:draw()
            Ui.eyedropperButton(self:parentPickRect(), self.isPicking and self.isPicking("$parent"))
            Ui.browseButton(self:parentBrowseRect(), self.dropdown.value ~= false)
        elseif row.componentTree then
            Ui.label("Components", self.left + Ui.METRICS.contentPaddingX, y + 6, self.width - 2 * Ui.METRICS.contentPaddingX)
            self.tree:draw()
            Ui.resizeGrip(self:treeGrip(self.tree))
        elseif row.header and y + row.groupHeight > self.propertyTop and y < self.propertyTop + self.propertyHeight then
            PropertyLayout.group(self.left, self.contentWidth or self.width, y, row.groupHeight, row.label, self.groupExpanded[row.groupKey] ~= false)
        elseif name and y + row.height > self.propertyTop and y < self.propertyTop + self.propertyHeight then
            PropertyLayout.separators(self.left, self.width, y, row.height, self.width - (self.contentWidth or self.width))
            local declaration = self.class.properties[name]
            local value = self.target:getOverrides()[name]
            if value == nil then value = declaration.default end
            local labelRect, rect = PropertyLayout.cells(self.left, self.width, y)
            if declaration.type == "image" then
                local imageRects = self:imageRects(y)
                rect = imageRects.selector
                labelRect.y = y + (row.height - love.graphics.getFont():getHeight()) / 2
                Ui.thumbnail(self:thumbnail(value), imageRects.preview)
                Ui.eyedropperButton(imageRects.assign, self.isPicking and self.isPicking(name))
                Ui.browseButton(imageRects.browse, value ~= false)
            elseif Schema.isTemplate(declaration.type) or declaration.type == "object" then
                local actions = self:referenceRects(y)
                rect = actions.selector
                Ui.eyedropperButton(actions.assign, self.isPicking and self.isPicking(name))
                if declaration.type == "object" then
                    Ui.browseButton(actions.browse, value ~= false, self.target.prefabScope and "Locate referenced object in this Prefab." or "Frame referenced instance in viewport.")
                else
                    Ui.browseButton(actions.browse, value ~= false)
                end
            end
            Ui.text(declaration.sceneTransform and TRANSFORM_LABELS[declaration.field] or declaration.field or name, labelRect.x, labelRect.y, labelRect.w)
            Ui.hint(labelRect, name .. ": " .. declaration.type .. ". Default: " .. tostring(declaration.default))
            if declaration.type == "object" then
                Ui.button("", rect, false, self:objectLabel(value, name) .. ". Use the eyedropper to pick a target.")
                Ui.text(self:objectLabel(value, name), rect.x + 4, rect.y + (rect.h - love.graphics.getFont():getHeight()) / 2, math.max(0, rect.w - 8))
            elseif declaration.type == "image" or Schema.isTemplate(declaration.type) then
                local choice = self:choices(name, value)
                choice:setBounds(rect.x, rect.y, rect.w, rect.h)
                choice:draw()
            elseif declaration.type == "boolean" then Ui.button(value and "True" or "False", rect, false, "Toggle " .. name .. ". Ctrl+S: save.")
            else Ui.field(self.editing == name and Ime.display(self, self.text, self.replace) or tostring(value),
                rect, self.editing == name, self.editing == name and self.composition, self) end
            Ui.resetButton(self:resetRect(name, y + 3))
        end
    end
    self.scrollbar:draw()
    love.graphics.pop()
    if self.error then
        local rect = {x = self.left + Ui.METRICS.contentPaddingX, y = self.propertyTop + self.propertyHeight + 4,
            w = self.width - 2 * Ui.METRICS.contentPaddingX, h = 24}
        Ui.text(self.error, rect.x, rect.y, rect.w, Theme.color("error"))
        Ui.hint(rect, self.error)
    end
end

function ClassInspector:mousepressed(x, y, button)
    local resize = button == 1 and self:resizeAt(x, y)
    if resize then
        self:commitEdit(); self.treeResize = {kind = resize, startY = y,
            height = resize == "object" and self.objectTreeHeight or self.componentTreeHeight}
        return true, true
    end
    if button == 2 and y >= self.propertyTop and y < self.propertyTop + self.propertyHeight and self.objectTree and self.objectTree:containsPoint(x, y) then
        self:commitEdit(); return self.objectTree:dispatch("mousepressed", x, y, button)
    end
    if button == 1 and not self.target.instance and self.onSave and Ui.contains(x, y, self:saveRect()) then self:commitEdit(); self.onSave(); return true end
    if y < self.propertyTop or y >= self.propertyTop + self.propertyHeight then self:commitEdit(); return true end
    if button ~= 1 then return true end
    local handled, capture = self.scrollbar:dispatch("mousepressed", x, y, button)
    if handled then self:commitEdit(); return true, capture end
    if self.objectTree and self.objectTree:containsPoint(x, y) then
        self.objectTreeFocused = true; self.treeFocused = false
        self:commitEdit(); return self.objectTree:dispatch("mousepressed", x, y, button)
    end
    self.objectTreeFocused = false
    if self.tree and y >= self.propertyTop and y < self.propertyTop + self.propertyHeight and self.tree:containsPoint(x, y) then
        self.treeFocused = true
        self:commitEdit(); return self.tree:dispatch("mousepressed", x, y, button)
    end
    self.treeFocused = false
    local dropdown = self.dropdown
    if self:parentVisible() and Ui.contains(x, y, self:parentPickRect()) then
        self:commitEdit()
        if self.onPick then
            local ok, err = self.onPick("$parent")
            if not ok then self.error = err end
        end
        return true
    end
    if self:parentVisible() and Ui.contains(x, y, self:parentBrowseRect()) then return self:reveal(dropdown.value) end
    if self:parentVisible() and dropdown:containsPoint(x, y) then
        self:commitEdit()
        self:updateOptions()
        return dropdown:dispatch("mousepressed", x, y, button)
    end
    if y < self.propertyTop or y >= self.propertyTop + self.propertyHeight then self:commitEdit(); return true end
    for _, row in ipairs(self.rows) do
        local name = row.name
        local top = self.propertyTop + row.offset - self.scroll
        if row.header and y >= top and y < top + row.height then
            self:commitEdit()
            self.groupExpanded[row.groupKey] = self.groupExpanded[row.groupKey] == false
            self:rebuildRows()
            return true
        end
        local rowTop = top
        top = top + 3
        if name and y >= rowTop and y < rowTop + row.height then
            local declaration = self.class.properties[name]
            local actions = declaration.type == "image" and self:imageRects(rowTop)
                or (Schema.isTemplate(declaration.type) or declaration.type == "object") and self:referenceRects(rowTop)
            if actions and Ui.contains(x, y, actions.assign) then
                self:commitEdit()
                local ok, err
                if self.onPick then ok, err = self.onPick(name) end
                if not ok then self.error = err or "Instance picking is unavailable" end
                return true
            end
            if actions and Ui.contains(x, y, actions.browse) then
                local value = self.target:getOverrides()[name]
                if declaration.type == "object" then
                    self:commitEdit()
                    if value == nil then value = declaration.default end
                    local ok, err
                    if self.onFrame then ok, err = self.onFrame(value) end
                    if not ok then self.error = err or "Instance was not found" end
                    return true
                end
                return self:reveal(value == nil and declaration.default or value)
            end
            if Ui.contains(x, y, self:resetRect(name, top)) then
                self:commitEdit()
                return self:setProperty(name, declaration.default)
            end
            if not Ui.contains(x, y, self:propertyRect(name, top)) then return true end
            if self.editing == name then
                self.text, self.replace = Ime.finish(self, self.text, self.replace)
                Edit.press(self, self.text, self:propertyRect(name, top), x, false)
                self.replace = false
                return true, true
            end
            self:commitEdit()
            local value = self.target:getOverrides()[name]
            if value == nil then value = declaration.default end
            if declaration.type == "object" then return true end
            if declaration.type == "image" or Schema.isTemplate(declaration.type) then
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
            if declaration.type == "number" then
                local scale = declaration.sceneTransform and declaration.field:match("^scale")
                NumberDrag.begin(self, self.text, x, {pointerY = y, step = scale and 0.01 or 1, minimum = scale and 0.01 or nil,
                    normalize = declaration.sceneTransform and declaration.field:match("^rotation") and require("core.Transform").normalizeRotation or nil,
                    onChange = function(value) self:setProperty(name, value) end})
            end
            return true, true
        end
    end
    self:commitEdit()
    return true
end

function ClassInspector:mousemoved(x, y, dx)
    if self.treeResize then
        local value = math.max(78, math.min(math.max(78, (self.layoutHeight - self.top) * 0.7), self.treeResize.height + y - self.treeResize.startY))
        if self.treeResize.kind == "object" then self.objectTreeHeight = value else self.componentTreeHeight = value end
        self:layout(self.left, self.width, self.layoutHeight, nil, self.top)
        return true
    end
    if self.scrollbar:dispatch("mousemoved", x, y) then return true end
    for _, tree in pairs({self.tree, self.objectTree}) do
        if tree.scrollbar.drag then return tree:dispatch("mousemoved", x, y, dx) end
    end
    local handled, text = NumberDrag.move(self, x, dx)
    if handled then
        if text then self.text, self.replace = text, false; Edit.begin(self, text, false) end
        return true
    end
    return Edit.move(self, x)
end
function ClassInspector:mousereleased(x, y, button)
    self.treeResize = nil
    self.scrollbar:dispatch("mousereleased", x, y, button)
    for _, tree in pairs({self.tree, self.objectTree}) do tree:dispatch("mousereleased", x, y, button) end
    if NumberDrag.finish(self) then self:commitEdit() end
    Edit.release(self); return true
end
function ClassInspector:cancelPointer()
    self.treeResize = nil
    self.scrollbar:dispatch("cancel")
    for _, tree in pairs({self.tree, self.objectTree}) do tree:dispatch("cancel") end
    if self.numberDrag then self:cancelEdit() end
    Edit.release(self); return true
end
function ClassInspector:keypressed(key)
    if not self.editing then
        if self.objectTreeFocused and self.objectTree then return self.objectTree:dispatch("keypressed", key) end
        if self.treeFocused and self.tree and (key == "up" or key == "down" or key == "left" or key == "right") then
            return self.tree:dispatch("keypressed", key)
        end
        return false
    end
    if NumberDrag.modifier(self, key) then return true end
    if Ime.handlesKey(self, key) then return true end
    if Ime.endsComposition(key) then self.text, self.replace = Ime.finish(self, self.text, self.replace) end
    if key == "return" or key == "kpenter" then self:commitEdit()
    elseif key == "escape" then self:cancelEdit()
    else self.text, self.replace = Ui.editKey(self.text, key, self.replace, self) end
    return true
end
function ClassInspector:textinput(text)
    if not self.editing then return false end
    self.text, self.replace = Ime.input(self, self.text, text, self.replace)
    return true
end
function ClassInspector:textedited(text)
    if not self.editing then return false end
    Ime.edited(self, text)
    return true
end
function ClassInspector:wheelmoved(amount, x, y)
    self:commitEdit()
    if y and (y < self.propertyTop or y >= self.propertyTop + self.propertyHeight) then return end
    if self.objectTree and x and self.objectTree:hitTest(x, y) then
        local previous = self.objectTree.scroll
        self.objectTree:dispatch("wheelmoved", x, y, amount)
        if self.objectTree.scroll ~= previous then return end
    end
    if self.tree and x and y >= self.propertyTop and y < self.propertyTop + self.propertyHeight and self.tree:hitTest(x, y) then
        local previous = self.tree.scroll
        self.tree:dispatch("wheelmoved", x, y, amount)
        if self.tree.scroll ~= previous then return end
    end
    self.scroll = math.floor(math.max(0, math.min(self.maxScroll or 0, self.scroll - amount * PropertyLayout.ROW_HEIGHT)))
    self:layoutComponentTree()
end
return ClassInspector
