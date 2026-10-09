local Hierarchy = require("project.PrefabHierarchy")
local Definition = require("project.ObjectDefinition")
local Editor = {}
Editor.__index = Editor
function Editor.new(project, document, onChanged, onSelect)
    return setmetatable({project = project, document = document, onChanged = onChanged, onSelect = onSelect, selected = "root"}, Editor)
end
function Editor:record(path, create)
    local current = self.document.data
    for id in path:gmatch("/([^/]+)") do
        local found
        for _, node in ipairs(current.children or {}) do if node.id == id then found = node; break end end
        if not found and create then
            current.children = current.children or {}; found = {id = id, overrides = {}}
            current.children[#current.children + 1] = found
        end
        if not found then return nil end
        current = found
    end
    return current
end
function Editor:recipe()
    local recipe, err = Hierarchy.resolve(self.project, self.document.assetId)
    if recipe then
        local reference = self.project:getAssetReference(self.document.assetId)
        recipe.root.name = reference and reference:match("([^/]+)%.prefab$") or "Prefab"
        for _, node in ipairs(recipe.nodes) do
            if not node.name then
                local path = node.reference and self.project:getAssetReference(node.reference)
                node.name = path and path:match("([^/]+)%.[^.]+$") or "LObject"
            end
        end
    end
    return recipe, err
end
function Editor:baseRecipe(path)
    local data = Hierarchy.copy(self.document.data)
    local record = data
    for id in path:gmatch("/([^/]+)") do
        local found
        for _, child in ipairs(record.children or {}) do if child.id == id then found = child; break end end
        record = found
        if not record then break end
    end
    if record then record.overrides, record.transform = {}, nil end
    local bindings = {}
    for _, binding in ipairs(data.bindings or {}) do if binding.from ~= path then bindings[#bindings + 1] = binding end end
    data.bindings = bindings
    local bytes, err = require("project.Prefab").encodeData(data)
    if not bytes then return nil, err end
    -- 현재 노드의 값만 제외한 문서로 중첩 원본·조상 상속을 동일하게 해석한다.
    local project = setmetatable({readAsset = function(_, reference)
        if self.project:getAssetId(self.project:getAssetReference(reference)) == self.document.assetId then return bytes end
        return self.project:readAsset(reference)
    end}, {__index = self.project})
    return Hierarchy.resolve(project, self.document.assetId)
end

function Editor:target(path)
    local recipe, err = self:recipe()
    if not recipe then return nil, err end
    local node = recipe.byPath[path or self.selected] or recipe.root
    self.selected = node.path
    local record = self:record(node.path, false)
    local proxy = {definitionReference = node.reference, propertyOverrides = Hierarchy.copy(record and record.overrides and record.overrides.properties),
        componentOverrides = Hierarchy.copy(record and record.overrides and record.overrides.components),
        transform = node.parent and Hierarchy.copy(node.transform) or nil}
    local parentReference = self.document.data.definitionReference
    if node.parent then parentReference = node.reference end
    local definition, definitionError = Definition.resolve(self.project, parentReference)
    if not definition then return nil, definitionError end
    local inherited, inheritError = self:baseRecipe(node.path)
    if not inherited then return nil, inheritError end
    local baseNode = inherited.byPath[node.path]
    if baseNode and baseNode.reference == node.reference then
        definition = {class = definition.class, componentLoader = definition.componentLoader,
            properties = Hierarchy.copy(definition.properties), components = Hierarchy.copy(definition.components)}
        for name, value in pairs(baseNode.overrides.properties or {}) do definition.properties[name] = value end
        for name, fields in pairs(baseNode.overrides.components or {}) do
            definition.components[name] = definition.components[name] or {}
            for field, value in pairs(fields) do definition.components[name][field] = value end
        end
    end
    local scope = {lobjects = {}}
    local byPath = {}
    for index, current in ipairs(recipe.nodes) do
        local object = {authoringId = index, name = current.name, path = current.path}
        scope.lobjects[index], byPath[current.path] = object, object
    end
    local target, targetError = Definition.inspectorTarget(self.project, proxy, definition, scope, "Prefab")
    if not target then return nil, targetError end
    target.instance, target.hideParent, target.parentOwnerId = false, false, self.document.assetId
    target.documentKey = self.document.assetId
    target.prefabScope, target.scopeByPath = true, byPath
    local baseBindings = inherited.bindings
    for _, binding in ipairs(baseBindings) do
        local from, to = binding.from, binding.to
        if from == node.path and byPath[to] and target.class.properties[binding.property] then
            target.class.properties[binding.property].default = byPath[to].authoringId
        end
    end
    for _, binding in ipairs(self.document.data.bindings or {}) do
        if binding.from == node.path and byPath[binding.to] then
            local component, field = binding.property:match("^([^.]+)%.(.+)$")
            if component then proxy.componentOverrides = proxy.componentOverrides or {}; proxy.componentOverrides[component] = proxy.componentOverrides[component] or {}; proxy.componentOverrides[component][field] = byPath[binding.to].authoringId
            else proxy.propertyOverrides = proxy.propertyOverrides or {}; proxy.propertyOverrides[binding.property] = byPath[binding.to].authoringId end
        end
    end
    local baseTransform = baseNode and baseNode.transform or assert(require("core.Transform").copy({x = 0, y = 0}))
    for name, declaration in pairs(target.class.properties) do if declaration.rootTransform then declaration.default = baseTransform[declaration.field] end end
    target.data = proxy; target.referenceField = "definitionReference"; proxy.definitionReference = parentReference
    target.getDisplayName = function() return node.name end
    target.isDirty = function() return self.document:isDirty() end
    target.getObjectHierarchy = function() local current = self:recipe(); return current and current.root end
    target.selectedObjectPath = node.path
    target.onSelectObject = function(selected) self.selected = selected; self.onSelect(selected) end
    target.onObjectContext = function(path, x, y) if self.onContext then self.onContext(path, x, y) end end
    target.reloadTarget = function() return self:target(node.path) end
    target.getSnapshot = function() return assert(require("editor.Prefab").encodeData(self.document.data)) end
    target.restoreSnapshot = function(text)
        self.document.data = assert(require("editor.Prefab").decode(text)); self.onChanged()
    end
    local set = target.setOverrides
    local parentChanged = false
    target.setParentReference = function(value)
        proxy.definitionReference, parentChanged = value or nil, true
    end
    target.setOverrides = function(current, values)
        set(current, values)
        local data = self:record(node.path, true)
        if parentChanged then
            data.definitionReference = proxy.definitionReference
            if node.parent and not proxy.definitionReference then data.definitionReference = false end
            parentChanged = false
        end
        data.overrides = {properties = next(proxy.propertyOverrides or {}) and Hierarchy.copy(proxy.propertyOverrides) or nil,
            components = next(proxy.componentOverrides or {}) and Hierarchy.copy(proxy.componentOverrides) or nil}
        local bindings = {}
        for _, binding in ipairs(self.document.data.bindings or {}) do
            if binding.from ~= node.path then bindings[#bindings + 1] = binding end
        end
        for name, declaration in pairs(target.class.properties) do
            if declaration.type == "object" then
                local component, field = name:match("^([^.]+)%.(.+)$")
                local fields = component and (data.overrides.components or {})[component] or data.overrides.properties
                local value = fields and fields[field or name]
                if value and value ~= false then
                    local destination = scope.lobjects[value]
                    bindings[#bindings + 1] = {from = node.path, property = name, to = destination.path}
                    fields[field or name] = false
                end
            end
        end
        self.document.data.bindings = #bindings > 0 and bindings or nil
        if node.parent then
            local transform = {}
            for field, value in pairs(proxy.transform) do if value ~= baseTransform[field] then transform[field] = value end end
            data.transform = next(transform) and transform or nil
        end
        if node.parent or #bindings > 0 then self.document.data.formatVersion = 3 end
        self.onChanged()
    end
    return target
end
function Editor:insertChild(reference, name, parentPath)
    local recipe, err = self:recipe()
    if not recipe then return false, err end
    local path = parentPath or self.selected
    local selected = recipe.byPath[path]
    if not selected then return false, "Missing child parent" end
    local parent = self:record(path, true)
    parent.children = parent.children or {}
    local ids = {}; for _, child in ipairs(selected.children) do ids[child.path:match("([^/]+)$")] = true end
    local number = 1; while ids["o" .. number] do number = number + 1 end
    parent.children[#parent.children + 1] = {id = "o" .. number, name = name, definitionReference = reference,
        transform = {x = 0, y = 0}, overrides = {}}
    self.document.data.formatVersion = 3; self.onChanged()
    return true, nil, path .. "/o" .. number
end
function Editor:add(reference, parentPath)
    local template, err = require("project.LObjectTemplate").resolve(self.project, reference)
    if not template then return false, err end
    if not Hierarchy.resolve(self.project, reference, nil, self.document.assetId) then return false, "Nested Prefab cycle" end
    return self:insertChild(template.reference, template.name, parentPath)
end
function Editor:addInstance(level, object, parentPath)
    local captured, err = Hierarchy.capture(self.project, level, object)
    if not captured then return false, err end
    local previous = Hierarchy.copy(self.document.data)
    local ok, addError = self:insertChild(captured.definitionReference, object.name or "LObject", parentPath)
    if not ok then return false, addError end
    local parent = self:record(parentPath or self.selected, true)
    local node = parent.children[#parent.children]
    node.name, node.transform = object.name, Hierarchy.copy(object.transform)
    node.overrides, node.children = captured.overrides, captured.children
    node.removedPaths = captured.removedPaths
    local path = (parentPath or self.selected) .. "/" .. node.id
    self.document.data.bindings = self.document.data.bindings or {}
    for _, binding in ipairs(captured.bindings) do
        self.document.data.bindings[#self.document.data.bindings + 1] = {
            from = path .. binding.from:sub(5), to = path .. binding.to:sub(5), property = binding.property}
    end
    self.onChanged()
    local recipe, validationError = self:recipe()
    if not recipe then
        self.document.data = previous; self.onChanged()
        return false, validationError
    end
    return true, nil, path
end
return Editor
