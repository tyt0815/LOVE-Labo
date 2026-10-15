local Schema = require("core.PropertySchema")
local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local LuaScript = require("editor.LuaScript")
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
        self.scroll = math.floor(value + 0.5); self:layoutTrees()
    end)
    self.objectTreeHeight, self.scriptTreeHeight = (3 * Ui.METRICS.treeRowHeight), (3 * Ui.METRICS.treeRowHeight)
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
        self.objectTreeHeight, self.scriptTreeHeight, self.objectTree = (3 * Ui.METRICS.treeRowHeight), (3 * Ui.METRICS.treeRowHeight), nil
    end
    self.treeLayoutKey = key
    self.target, self.scroll, self.error = target, 0, nil
    self.selectedScript, self.tree, self.treeFocused = nil, nil, false
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
    elseif reference then self.class, self.error = LuaScript.load(self.project, reference, self.target.kind) end
    if self.target.mainCameraDetails then
        local properties = {}
        for name, declaration in pairs(self.class and self.class.properties or {}) do properties[name] = declaration end
        properties["$mainCamera"] = {type = "object", default = false, field = "Main Camera", group = "Camera"}
        self.class = {properties = properties, scriptTypes = self.class and self.class.scriptTypes,
            className = self.class and (self.class.className or LuaScript.name(self.class)) or "Level"}
    end
    if not self.preview then self.selectedScript = nil end
    self.allNames = {}
    for name in pairs(self.class and self.class.properties or {}) do self.allNames[#self.allNames + 1] = name end
    table.sort(self.allNames)
    local oldTree = self.tree
    self.tree = nil
    self:rebuildRows()
    local oldObjectTree = self.objectTree
    self.objectTree = nil
    if self.target.getObjectHierarchy then
        local hierarchy = self.target.getObjectHierarchy()
        if hierarchy then
            self.objectTree = require("editor.ui.ObjectTree").new(hierarchy, self.target.onSelectObject, self.target.onObjectContext)
            self.objectTree.rootReference = self.target.objectHierarchyReference
            if oldObjectTree then
                self.objectTree.expanded, self.objectTree.scroll = oldObjectTree.expanded, oldObjectTree.scroll
                self.objectTree.drag = oldObjectTree.drag
                self.objectTree:rebuild()
                self.objectTree:setBounds(oldObjectTree.x, oldObjectTree.y, oldObjectTree.width, oldObjectTree.height)
            end
            self.objectTree.selected = self.target.selectedObjectPath or "root"
            self.objectTree.onLocatePrefab = function(value) if self.onReveal then return self.onReveal(value) end end
            self.objectTree.onDrop = function(source, destination, mode)
                local ok, err = self.target.onObjectDrop(source, destination, mode)
                if ok then
                    if self.onTreeChanged then self.onTreeChanged() end
                else self.error = err end
            end
        end
    end
    self.dropdown = Dropdown.new(self.root, {}, reference or false, function(value) return self:selectParent(value) end)
    self.dropdown.hint = "Choose a Parent Class. None: use the built-in Level or LObject."
    self:updateOptions()
end

function ClassInspector:selectScript(script)
    self:commitEdit()
    assert(not script or self.preview and self.preview.scripts[script], "Missing Inspector script")
    self.selectedScript, self.scroll = script, 0
    if self.tree then self.tree:reveal(script) end
    self:rebuildRows()
    if self.onScopeChanged then self.onScopeChanged() end
    if self.left then self:layoutTrees() end
    return true
end

function ClassInspector:treeBottom()
    if not self.tree then return nil end
    return (self.top or 0) + 100 + Ui.METRICS.contentPaddingY + math.min(156, math.max(26, #self.tree.nodes * 26))
end
function ClassInspector:parentVisible() return self.target and not self.target.hideParent end

function ClassInspector:updateOptions()
    local options = {{label = "None", value = false}}
    local scripts, err = self.project:listScripts(self.target.kind == "lobject" and "script" or self.target.kind)
    if self.target.kind == "lobject" then scripts, err = {}, nil end
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
    if self.target.readOnly then return false, "Labo plugin assets are read-only" end
    self:commitEdit()
    local snapshot = self.target.getSnapshot and self.target.getSnapshot()
    local class, err, parentTarget
    if self.target.parentDefaults then
        parentTarget, err = self.target.parentDefaults(value)
        if not parentTarget then self.error = err; return false end
        class = parentTarget.class
    elseif value then
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
        else class, err = LuaScript.load(self.project, value, self.target.kind) end
        if not class then self.error = err; return false end
    end
    if self.target.setParentReference then self.target.setParentReference(value)
    else self.target.data[self.target.referenceField] = value or nil end
    self.target:setOverrides(LuaScript.compatibleOverrides(class, self.target:getOverrides()), parentTarget)
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
    local prefix, field = name:match("^(.*)%.([^.]+)$")
    local script = prefix and self.preview and (self.preview:getScriptById(prefix) or self.preview:getScriptByName(prefix))
    if script then name = script.id .. "." .. field end
    if self.target.readOnly then return false, "Labo plugin assets are read-only" end
    if name == "$mainCamera" and self.target.mainCameraDetails then
        if value == false then return self.target:setMainCamera(nil) end
        self.error = "Use the eyedropper to select a camera instance"; return false
    end
    local declaration = self.class and self.class.properties[name]
    if declaration and declaration.type == "script" and self.target.resolveScriptReference then value = self.target:resolveScriptReference(value) end
    if not declaration or not LuaScript.validValue(declaration.type, value) then
        self.error = "Invalid value for " .. name
        return false
    end
    if declaration.sceneTransform then
        local transform = require("core.Transform").copy(self.preview.transform)
        transform[declaration.field] = value
        local valid, err = require("core.Transform").copy(transform)
        if not valid then self.error = err; return false end
        value = valid[declaration.field]
    end
    if (Schema.isResource(declaration.type) or Schema.isTemplate(declaration.type)) and value ~= false then
        local reference, err = self.project:getAssetReference(value)
        if not reference then self.error = err; return false end
        if Schema.isTemplate(declaration.type) then
            local template
            template, err = require("project.LObjectTemplate").resolve(self.project, value)
            if not template then self.error = err; return false end
        elseif declaration.type == "audio" then
            local valid, audioError = require("project.AssetData").validateAudio(self.project, value)
            if not valid then self.error = audioError; return false end
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
    elseif (declaration.type == "object" or declaration.type == "script") and value ~= false then
        local found = false
        for _, object in ipairs(self.target.level and self.target.level.lobjects or {}) do
            if object.authoringId == (type(value) == "table" and value.authoringId or value) then found = true end
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
    if self.class.properties[name].type == "audio" or Schema.isTemplate(self.class.properties[name].type) or (self.class.properties[name].type == "object" or self.class.properties[name].type == "script") then
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
    return {x = self.left + self.width - Ui.METRICS.contentPaddingX - width, y = (self.panelTop or self.top or 0) + 8, w = width, h = 26}
end
function ClassInspector:parentPickRect()
    local rect = self:parentBrowseRect()
    return {x = rect.x - 30, y = rect.y, w = 26, h = 26}
end
function ClassInspector:objectLabel(value, name)
    if value == false then return name == "$mainCamera" and "Auto" or "None" end
    for _, object in ipairs(self.target.level and self.target.level.lobjects or {}) do
        if object.authoringId == (type(value) == "table" and value.authoringId or value) then
            local label = object.name or "LObject " .. tostring(value)
            local scriptId = type(value) == "table" and value.script or name == "$mainCamera" and self.target.data.mainCamera.script
            if scriptId then
                local definition = require("project.PrefabHierarchy").authoringDefinition(self.project, self.target.level, object)
                local attachment = definition and require("project.ScriptAttachments").find(definition.attachments, scriptId)
                label = label .. " / " .. (attachment and attachment.name or "Missing Script")
            end
            return label
        end
    end
    return "Missing: " .. tostring(value)
end
function ClassInspector:pickCandidate(name, reference, object)
    if name == "$parent" then
        reference = reference or object and object.definitionReference
        if not reference then return nil, "Select a Parent Prefab asset or a sourced instance" end
        if self.target.kind == "lobject" then
            local definition, err = require("project.ObjectDefinition").resolve(self.project, reference, nil, self.target.parentOwnerId)
            if not definition then return nil, err end
        else
            local class, err = LuaScript.load(self.project, reference, self.target.kind)
            if not class then return nil, err end
        end
        local path, err = self.project:getAssetReference(reference)
        if not path then return nil, err end
        return self.project:getAssetId(path) or path
    end
    local declaration = self.class.properties[name]
    if not declaration then return nil, "Property no longer exists" end
    if (declaration.type == "object" or declaration.type == "script") then
        if not object or not self.target.level then return nil, "Select an instance in the current level" end
        for _, current in ipairs(self.target.level.lobjects) do if current == object then return object.authoringId end end
        return nil, "Instance must belong to the current level"
    end
    if Schema.isTemplate(declaration.type) then
        reference = reference or object and object.definitionReference
        if not reference then return nil, "Select a Prefab or sourced instance" end
        local template, err = require("project.LObjectTemplate").resolve(self.project, reference)
        return template and template.reference or nil, err
    end
    if declaration.type == "audio" then
        local path, err = reference and self.project:getAssetReference(reference)
        if not path or not require("project.AssetData").isAudio(path) then return nil, err or "Select an audio asset" end
        return self.project:getAssetId(path) or path
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
    elseif Schema.isResource(kind) or Schema.isTemplate(kind) then
        local references = {}
        for reference in pairs(self.project.assetMetadata or {}) do
            if reference:lower():match("%.(.*)$") then
                local extension = reference:lower():match("%.([^%.]+)$")
                if kind == "image" and reference:match("^Assets/") and ({png = true, jpg = true, jpeg = true, bmp = true, tga = true, gif = true})[extension]
                    or kind == "audio" and require("project.AssetData").isAudio(reference)
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

-- 부착 단위 안에 프로퍼티 그룹을 중첩해 원본·부착 조작과 필드 분류를 구분한다.
function ClassInspector:rebuildRows()
    local rows = {}
    self.names = {}
    if self.target then
        rows[#rows + 1] = {summary = true, height = 64}
        if self.objectTree then rows[#rows + 1] = {objectTree = true, height = self.objectTreeHeight + 12} end
        if self:parentVisible() then rows[#rows + 1] = {parentClass = true, height = 48} end
    end
    local function addScope(script)
        local groups, groupNames = {}, {}
        local defaultGroup = script and self.class.scriptTypes[script]
            or self.class and (self.class.className or LuaScript.name(self.class)) or "LObject"
        for _, name in ipairs(self.allNames or {}) do
            local declaration = self.class.properties[name]
            local belongs = script and declaration.script == script and not declaration.rootTransform
                or not script and (not declaration.script or declaration.rootTransform)
            if belongs then
                self.names[#self.names + 1] = name
                local group = declaration.rootTransform and "Transform" or declaration.group or defaultGroup
                if not groups[group] then groups[group] = {}; groupNames[#groupNames + 1] = group end
                groups[group][#groups[group] + 1] = name
            end
        end
        if #groupNames == 0 and self.class and (script or not self.preview) then groups[defaultGroup] = {}; groupNames[1] = defaultGroup end
        table.sort(groupNames, function(a, b)
            if a == b then return false end
            if a == "Transform" then return true end
            if b == "Transform" then return false end
            if a == defaultGroup then return true end
            if b == defaultGroup then return false end
            return a < b
        end)
        local scriptHeader
        if script then
            local displayName = self.preview.scripts[script].name
            scriptHeader = {scriptId = script, header = true, label = displayName .. " (" .. defaultGroup .. ")",
                groupKey = "script:" .. script, height = PropertyLayout.HEADER_HEIGHT, groupHeight = PropertyLayout.HEADER_HEIGHT}
            rows[#rows + 1] = scriptHeader
            if self.groupExpanded[scriptHeader.groupKey] == false then
                rows[#rows + 1] = {gap = true, height = 8}
                return
            end
        end
        local rank = {}; for index, field in ipairs(require("core.Transform").ORDER) do rank[field] = index end
        for _, group in ipairs(groupNames) do
            table.sort(groups[group], function(a, b)
                local left, right = self.class.properties[a], self.class.properties[b]
                local first, second = left.sceneTransform and rank[left.field], right.sceneTransform and rank[right.field]
                if first and second then return first < second end
                if first or second then return first ~= nil and first ~= false end
                return a < b
            end)
            local key = (script and "script:" .. script or "object") .. "/" .. group
            -- 헤더는 같은 열에 정렬하고 그룹 안의 프로퍼티 이름만 들여쓴다.
            local nested = script and group ~= defaultGroup
            local isTransform = not script and group == "Transform"
            local header = {header = true, label = group, groupKey = key, depth = 0, builtIn = isTransform,
                height = PropertyLayout.HEADER_HEIGHT, groupHeight = PropertyLayout.HEADER_HEIGHT}
            if not script or nested then rows[#rows + 1] = header end
            if script and not nested or self.groupExpanded[key] ~= false then
                for index, name in ipairs(groups[group]) do
                    local row = {name = name, depth = not isTransform and (not script or nested) and 1 or 0,
                        groupFirst = index == 1,
                        height = PropertyLayout.ROW_HEIGHT * (self.class.properties[name].type == "image" and 2 or 1)}
                    rows[#rows + 1] = row; header.groupHeight = header.groupHeight + row.height
                end
            end
            if scriptHeader then
                scriptHeader.groupHeight = scriptHeader.groupHeight + header.groupHeight - (not nested and PropertyLayout.HEADER_HEIGHT or 0)
            else rows[#rows + 1] = {gap = true, height = 8} end
        end
        if scriptHeader then rows[#rows + 1] = {gap = true, height = 8} end
    end
    addScope(nil)
    if self.preview then
        rows[#rows + 1] = {scriptActions = true, height = 36}
        for _, id in ipairs(self.preview.scriptOrder) do addScope(id) end
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
    local script = not declaration.rootTransform and declaration.script or nil
    if script and script ~= self.selectedScript then self:selectScript(script) end
    if script then self.groupExpanded["script:" .. script] = true end
    local group = declaration.rootTransform and "Transform" or declaration.group or (script and self.class.scriptTypes[script]
        or self.class.className or LuaScript.name(self.class) or "LObject")
    self.groupExpanded[(script and "script:" .. script or "object") .. "/" .. group] = true
    self:rebuildRows()
    for _, row in ipairs(self.rows) do
        if row.name == name then
            self.scroll = math.max(0, math.min(self.maxScroll, math.max(row.offset + row.height - self.propertyHeight, math.min(self.scroll, row.offset))))
            self:layoutTrees()
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
    self.propertyHeight = math.max(0, self.propertyBottom - self.propertyTop)
    self:rebuildRows()
    self:layoutTrees()
end
function ClassInspector:layoutTrees()
    for _, row in ipairs(self.rows) do
        local y = self.propertyTop + row.offset - self.scroll
        local width = self.width - 2 * Ui.METRICS.contentPaddingX - (self.scrollbar.visible and Scrollbar.WIDTH or 0)
        if row.objectTree then self.objectTree:setBounds(self.left + Ui.METRICS.contentPaddingX, y, width, self.objectTreeHeight)
        elseif row.parentClass then
            local _, field = PropertyLayout.cells(self.left, self.width, y)
            self.dropdown:setBounds(field.x, y, math.max(0, self:parentPickRect().x - field.x - 4), 28)
        end
        if row.scriptTree then
            self.tree:setBounds(self.left + Ui.METRICS.contentPaddingX, y + 30, width, self.scriptTreeHeight)
        end
    end
end
function ClassInspector:treeGrip(tree)
    return {x = tree.x, y = tree.y + tree.height, w = tree.width, h = 6}
end
function ClassInspector:resizeAt(x, y)
    -- 빈 선택과 에셋 요약에서는 프로퍼티 영역을 배치하지 않는다.
    if not self.target or not self.propertyTop or not self.propertyHeight then return end
    if self.treeResize then return self.treeResize.kind end
    if y < self.propertyTop or y >= self.propertyTop + self.propertyHeight then return end
    if self.objectTree and Ui.contains(x, y, self:treeGrip(self.objectTree)) then return "object" end
    if self.tree and y >= self.propertyTop and y < self.propertyTop + self.propertyHeight
        and Ui.contains(x, y, self:treeGrip(self.tree)) then return "script" end
end
function ClassInspector:isPointerActive()
    return self.treeResize or self.scrollbar.drag or self.tree and self.tree.scrollbar.drag
        or self.objectTree and (self.objectTree.scrollbar.drag or self.objectTree.drag)
end
function ClassInspector:treeContains(tree, x, y)
    return tree and y >= self.propertyTop and y < self.propertyTop + self.propertyHeight and tree:containsPoint(x, y)
end

function ClassInspector:targetKind()
    if self.target.kind == "lobject" then
        local name = self.class and (self.class.className or LuaScript.name(self.class)) or "LObject"
        return (name or "LObject") .. " Prefab"
    end
    return self.target.label
end
function ClassInspector:draw()
    self.thumbnails:beginFrame()
    local propertyHeight = math.max(0, self.propertyBottom - self.propertyTop)
    if propertyHeight ~= self.propertyHeight then self.propertyHeight = propertyHeight; self:rebuildRows() end
    if not self.target.instance and self.onSave then Ui.button("Save", self:saveRect(), false, "Save this document", true) end
    self:layoutTrees()
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
            local labelRect = PropertyLayout.cells(self.left, self.width, self.dropdown.y)
            Ui.label(self.target.kind == "lobject" and "Parent Prefab" or "Level Script", labelRect.x, self.dropdown.y + 6, labelRect.w)
            self.dropdown:draw()
            Ui.eyedropperButton(self:parentPickRect(), self.isPicking and self.isPicking("$parent"))
            Ui.browseButton(self:parentBrowseRect(), self.dropdown.value ~= false)
        elseif row.scriptActions then
            Ui.label("Scripts", self.left + Ui.METRICS.contentPaddingX, y + 6, self.width - 2 * Ui.METRICS.contentPaddingX)
            if self.isPicking and self.isPicking("$attachScript") then
                local rect = self:attachmentRect(y); self.attachPickRect = rect
                Ui.field("", {x = rect.x, y = rect.y, w = rect.w - 56, h = 26}, false)
                Ui.eyedropperButton({x = rect.x + rect.w - 56, y = rect.y, w = 28, h = 26}, true)
                local x, cy = rect.x + rect.w - 13, rect.y + 13
                Theme.setColor("textMuted"); love.graphics.line(x - 4, cy - 4, x + 4, cy + 4); love.graphics.line(x - 4, cy + 4, x + 4, cy - 4)
            elseif self.target.addScript then self.attachPickRect = nil; Ui.button("Add Script", self:scriptActionRect(y), false, "Attach a script to this object", true) end
        elseif row.scriptTree then
            Ui.label("Scripts", self.left + Ui.METRICS.contentPaddingX, y + 6, self.width - 2 * Ui.METRICS.contentPaddingX)
            self.tree:draw()
            Ui.resizeGrip(self:treeGrip(self.tree))
        elseif row.header and y + row.groupHeight > self.propertyTop and y < self.propertyTop + self.propertyHeight then
            if row.scriptId or row.builtIn then
                PropertyLayout.group(self.left, self.contentWidth or self.width, y, row.groupHeight, row.label,
                    self.groupExpanded[row.groupKey] ~= false, row.scriptId and 60 or 0)
            else
                PropertyLayout.propertyGroup(self.left, self.width, y, row.groupHeight, row.label,
                    self.groupExpanded[row.groupKey] ~= false, self.width - (self.contentWidth or self.width))
                if self.groupExpanded[row.groupKey] ~= false then
                    PropertyLayout.groupBody(self.left, self.width, y + row.height, row.groupHeight - row.height,
                        self.width - (self.contentWidth or self.width))
                end
            end
            if row.scriptId then
                local actions = self:scriptHeaderRects(y)
                Ui.browseButton(actions.browse, self:scriptSource(row.scriptId) ~= nil, "Locate script asset")
                if self.target.removeScript and (not self.target.canRemoveScript or self.target:canRemoveScript(row.scriptId)) then
                    Ui.closeButton(actions.remove, "Remove this script attachment")
                end
            end
        elseif name and y + row.height > self.propertyTop and y < self.propertyTop + self.propertyHeight then
            local indent = (row.depth or 0) * PropertyLayout.GROUP_INDENT
            Ui.row({x = self.left + Ui.METRICS.contentPaddingX + indent, y = y,
                w = (self.contentWidth or self.width) - 2 * Ui.METRICS.contentPaddingX - indent, h = row.height}, false)
            PropertyLayout.separators(self.left, self.width, y, row.height, self.width - (self.contentWidth or self.width),
                indent, indent > 0 and row.groupFirst)
            local declaration = self.class.properties[name]
            local value = self.target:getOverrides()[name]
            if value == nil then value = declaration.default end
            local labelRect, rect = PropertyLayout.cells(self.left, self.width, y)
            labelRect.x, labelRect.w = labelRect.x + indent, math.max(0, labelRect.w - indent)
            if declaration.type == "image" then
                local imageRects = self:imageRects(y)
                rect = imageRects.selector
                labelRect.y = y + (row.height - love.graphics.getFont():getHeight()) / 2
                Ui.thumbnail(self:thumbnail(value), imageRects.preview)
                Ui.eyedropperButton(imageRects.assign, self.isPicking and self.isPicking(name))
                Ui.browseButton(imageRects.browse, value ~= false)
            elseif declaration.type == "audio" or Schema.isTemplate(declaration.type) or (declaration.type == "object" or declaration.type == "script") then
                local actions = self:referenceRects(y)
                rect = actions.selector
                Ui.eyedropperButton(actions.assign, self.isPicking and self.isPicking(name))
                if (declaration.type == "object" or declaration.type == "script") then
                    Ui.browseButton(actions.browse, value ~= false, self.target.prefabScope and "Locate referenced object in this Prefab." or "Frame referenced instance in viewport.")
                else
                    Ui.browseButton(actions.browse, value ~= false)
                end
            end
            Ui.text(declaration.sceneTransform and TRANSFORM_LABELS[declaration.field] or declaration.field or name, labelRect.x, labelRect.y, labelRect.w)
            Ui.hint(labelRect, name .. ": " .. declaration.type .. ". Default: " .. tostring(declaration.default))
            if (declaration.type == "object" or declaration.type == "script") then
                Ui.button("", rect, false, self:objectLabel(value, name) .. ". Use the eyedropper to pick a target.")
                Ui.text(self:objectLabel(value, name), rect.x + 4, rect.y + (rect.h - love.graphics.getFont():getHeight()) / 2, math.max(0, rect.w - 8))
            elseif Schema.isResource(declaration.type) or Schema.isTemplate(declaration.type) then
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

end

function ClassInspector:mousepressed(x, y, button)
    local resize = button == 1 and self:resizeAt(x, y)
    if resize then
        self:commitEdit(); self.treeResize = {kind = resize, startY = y,
            height = resize == "object" and self.objectTreeHeight or self.scriptTreeHeight}
        return true, true
    end
    if button == 2 and y >= self.propertyTop and y < self.propertyTop + self.propertyHeight and self.objectTree and self.objectTree:containsPoint(x, y) then
        self:commitEdit(); return self.objectTree:dispatch("mousepressed", x, y, button)
    end
    if button == 1 and not self.target.instance and self.onSave and Ui.contains(x, y, self:saveRect()) then self:commitEdit(); self.onSave(); return true end
    if y < self.propertyTop or y >= self.propertyTop + self.propertyHeight then self:commitEdit(); return true end
    if button == 2 and self.target.moveScript then
        self:commitEdit()
        for _, row in ipairs(self.rows) do
            local top = self.propertyTop + row.offset - self.scroll
            if row.header and row.scriptId and y >= top and y < top + row.height then
                local id, index = row.scriptId, 1
                for number, current in ipairs(self.preview.scriptOrder) do if current == id then index = number end end
                local function move(destination)
                    local ok, err = self.target:moveScript(id, destination)
                    if ok then self:reload() else self.error = err end
                end
                require("editor.ui.ContextMenu").new(self.root):show(x, y, {
                    {label = "Copy ID", action = function() love.system.setClipboardText(id) end},
                    {label = "Rename", enabled = self.target.renameScript ~= nil, action = function()
                        local rect = {x = self.left + Ui.METRICS.contentPaddingX + 26, y = top + 3, w = math.max(60, self.width - 120), h = 26}
                        require("editor.ui.InlineRename").new(self.root, rect, self.preview.scripts[id].name, function(name)
                            local ok, err = self.target:renameScript(id, name)
                            if ok then self:reload() end
                            return ok, err
                        end)
                    end},
                    {label = "Move Up", enabled = index > 1, action = function() move(index - 1) end},
                    {label = "Move Down", enabled = index < #self.preview.scriptOrder, action = function() move(index + 1) end}})
                return true
            end
        end
    end
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
        if row.header and row.scriptId then
            local actions = self:scriptHeaderRects(top)
            if Ui.contains(x, y, actions.browse) then
                local source = self:scriptSource(row.scriptId)
                if source then return self:reveal(source) end
                return true
            end
            if Ui.contains(x, y, actions.remove) then
                if self.target.removeScript and (not self.target.canRemoveScript or self.target:canRemoveScript(row.scriptId)) then
                    self:commitEdit()
                    local ok, err = self.target:removeScript(row.scriptId)
                    if ok then self:reload() else self.error = err end
                end
                return true
            end
        end
        if Ui.contains(x, y, self:scriptActionRect(top)) then
            if row.scriptActions and self.target.addScript then self:commitEdit(); self:showAddScript(top); return true end
        end
        if row.header and x >= self.left + Ui.METRICS.contentPaddingX and y >= top and y < top + row.height then
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
                or (declaration.type == "audio" or Schema.isTemplate(declaration.type) or (declaration.type == "object" or declaration.type == "script")) and self:referenceRects(rowTop)
            if actions and Ui.contains(x, y, actions.assign) then
                self:commitEdit()
                local ok, err
                if self.onPick then ok, err = self.onPick(name) end
                if not ok then self.error = err or "Instance picking is unavailable" end
                return true
            end
            if actions and Ui.contains(x, y, actions.browse) then
                local value = self.target:getOverrides()[name]
                if (declaration.type == "object" or declaration.type == "script") then
                    self:commitEdit()
                    if value == nil then value = declaration.default end
                    local ok, err
                    if self.onFrame then ok, err = self.onFrame(type(value) == "table" and value.authoringId or value) end
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
            if (declaration.type == "object" or declaration.type == "script") then return true end
            if Schema.isResource(declaration.type) or Schema.isTemplate(declaration.type) then
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

function ClassInspector:scriptActionRect(y)
    return {x = self.left + (self.contentWidth or self.width) - Ui.METRICS.contentPaddingX - 90, y = y + 3, w = 90, h = 26}
end
function ClassInspector:scriptHeaderRects(y)
    local right = self.left + (self.contentWidth or self.width) - Ui.METRICS.contentPaddingX
    return {browse = {x = right - 56, y = y + 3, w = 26, h = 26}, remove = {x = right - 26, y = y + 3, w = 26, h = 26}}
end
function ClassInspector:scriptSource(id)
    local script = self.preview and self.preview.scripts[id]
    local source = script and script.source
    local plugin = source and self.project.plugins.scripts[source]
    if plugin then source = plugin.id end
    local reference = source and self.project:getAssetReference(source)
    return reference and self.project:getAssetId(reference) and reference or nil
end
function ClassInspector:showAddScript(y)
    if not self.target.addScript then return false end
    local options = {}
    for _, name in ipairs(self.project.plugins:scriptNames()) do options[#options + 1] = {label = name, value = name} end
    for _, reference in ipairs(self.project:listScripts("script") or {}) do
        if not self.project.plugins.assetScripts[reference] then
            options[#options + 1] = {label = resourceName(reference):gsub("%.lua$", ""), value = self.project:getAssetId(reference)}
        end
    end
    local rect = self:attachmentRect(y)
    return require("editor.ui.ScriptPicker").new(self.root, rect, options, function(source)
        local ok, err = self.target:addScript(source)
        if ok then self:reload() else self.error = err end
        return ok
    end, function() if self.onPick then self.onPick("$attachScript") end end)
end
function ClassInspector:attachmentRect(y)
    return {x = self.left + (self.contentWidth or self.width) / 2, y = y + 3, w = math.max(80, (self.contentWidth or self.width) / 2 - Ui.METRICS.contentPaddingX), h = 26}
end

function ClassInspector:mousemoved(x, y, dx)
    if self.treeResize then
        local value = math.max((3 * Ui.METRICS.treeRowHeight), math.min(math.max((3 * Ui.METRICS.treeRowHeight), (self.layoutHeight - self.top) * 0.7), self.treeResize.height + y - self.treeResize.startY))
        if self.treeResize.kind == "object" then self.objectTreeHeight = value else self.scriptTreeHeight = value end
        self:layout(self.left, self.width, self.layoutHeight, nil, self.top)
        return true
    end
    if self.scrollbar:dispatch("mousemoved", x, y) then return true end
    for _, tree in pairs({self.tree, self.objectTree}) do
        if tree.scrollbar.drag or tree.drag then return tree:dispatch("mousemoved", x, y, dx) end
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
    self:layoutTrees()
end
return ClassInspector
