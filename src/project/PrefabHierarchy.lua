local Definition = require("project.ObjectDefinition")
local Transform = require("core.Transform")
local Hierarchy = {}
function Hierarchy.isRemoved(path, removed)
    for _, prefix in ipairs(removed or {}) do if path == prefix or path:sub(1, #prefix + 1) == prefix .. "/" then return true end end
    return false
end

function Hierarchy.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = Hierarchy.copy(item) end
    return result
end

function Hierarchy.mergeChildren(base, overrides)
    local result, byId = Hierarchy.copy(base or {}), {}
    for _, node in ipairs(result) do byId[node.id] = node end
    for _, override in ipairs(overrides or {}) do
        local node = byId[override.id]
        if not node then node = {id = override.id}; result[#result + 1] = node; byId[node.id] = node end
        for key, value in pairs(override) do
            if key == "children" then node.children = Hierarchy.mergeChildren(node.children, value)
            elseif key == "transform" then
                node.transform = node.transform or {}
                for field, item in pairs(value) do node.transform[field] = item end
            elseif key == "overrides" then
                node.overrides = node.overrides or {}
                for kind, fields in pairs(value) do
                    node.overrides[kind] = node.overrides[kind] or {}
                    for name, field in pairs(fields) do
                        if kind == "components" then
                            node.overrides[kind][name] = node.overrides[kind][name] or {}
                            for property, item in pairs(field) do node.overrides[kind][name][property] = item end
                        else node.overrides[kind][name] = field end
                    end
                end
            else node[key] = Hierarchy.copy(value) end
        end
    end
    return result
end

function Hierarchy.resolve(project, reference, loadClass, excludedId)
    loadClass = loadClass or require("project.LuaClass").loader(project)
    local visiting, nodes, bindings, operations = {}, {}, {}, {}
    local function build(reference, override, path, parent, depth, ancestorRemoved)
        if depth > 64 then return nil, "Prefab hierarchy is too deep" end
        local key = reference and (project:getAssetId(reference) or reference)
        if key and key == excludedId then return nil, "Nested Prefab cycle" end
        local definition, err = Definition.resolve(project, reference, loadClass, excludedId)
        if not definition then return nil, err end
        local children, removed, pending = {}, Hierarchy.copy(ancestorRemoved or {}), {}
        local function clearFields(record, prefix)
            for name in pairs(record.overrides and record.overrides.properties or {}) do pending[#pending + 1] = {from = prefix, property = name} end
            for name, fields in pairs(record.overrides and record.overrides.components or {}) do
                for field in pairs(fields) do pending[#pending + 1] = {from = prefix, property = name .. "." .. field} end
            end
            for _, child in ipairs(record.children or {}) do clearFields(child, prefix .. "/" .. child.id) end
        end
        for _, layer in ipairs(definition.layers) do
            children = Hierarchy.mergeChildren(children, layer.children)
            clearFields(layer, path)
            for _, prefix in ipairs(layer.removedPaths or {}) do removed[#removed + 1] = path .. prefix:sub(5) end
            for _, binding in ipairs(layer.bindings or {}) do
                pending[#pending + 1] = {from = path .. binding.from:sub(5), to = path .. binding.to:sub(5), property = binding.property}
            end
        end
        if key and visiting[key] and #children > 0 then return nil, "Nested Prefab cycle" end
        if key then visiting[key] = (visiting[key] or 0) + 1 end
        children = Hierarchy.mergeChildren(children, override and override.children)
        for _, prefix in ipairs(override and override.removedPaths or {}) do removed[#removed + 1] = path .. prefix:sub(5) end
        local initial = {x = 0, y = 0}
        for field, value in pairs(override and override.transform or {}) do initial[field] = value end
        local transform, transformError = Transform.copy(initial)
        if not transform then return nil, transformError end
        local node = {path = path, parent = parent, reference = key, definition = definition,
            transform = transform, name = override and override.name,
            overrides = Hierarchy.copy(override and override.overrides or {}), children = {}}
        nodes[#nodes + 1] = node
        for _, child in ipairs(children) do
            if not Hierarchy.isRemoved(path .. "/" .. child.id, removed) then
            -- 상속용 부분 레코드는 ID 병합으로 원본을 유지하고, 새 무참조 노드는 기본 LObject다.
            local resolved, childError = build(child.definitionReference, child, path .. "/" .. child.id, node, depth + 1, removed)
            if not resolved then return nil, childError end
            node.children[#node.children + 1] = resolved
            end
        end
        if key then visiting[key] = visiting[key] > 1 and visiting[key] - 1 or nil end
        if override then clearFields(override, path) end
        for _, operation in ipairs(pending) do operations[#operations + 1] = operation end
        return node
    end
    local root, err = build(reference, nil, "root", nil, 0)
    if not root then return nil, err end
    local paths = {}; for _, node in ipairs(nodes) do paths[node.path] = node end
    local effective = {}
    for _, operation in ipairs(operations) do effective[operation.from .. "|" .. operation.property] = operation.to and operation or nil end
    for _, binding in pairs(effective) do bindings[#bindings + 1] = binding end
    for _, binding in ipairs(bindings) do
        if not paths[binding.from] or not paths[binding.to] then return nil, "Missing Prefab object binding" end
    end
    return {root = root, nodes = nodes, byPath = paths, bindings = bindings}
end

function Hierarchy.applyBindings(recipe, objects, overridden)
    for _, binding in ipairs(recipe.bindings) do
        local object, target = objects[binding.from], objects[binding.to]
        if object then
        local component, field = binding.property:match("^([^.]+)%.(.+)$")
        local values
        if component then values = object.components[component] and object.components[component].properties
        else values = object.properties end
        if not values then return false, "Missing binding component" end
        if not (overridden and overridden[binding.from] and overridden[binding.from][binding.property]) then
            if not target then return false, "Missing Prefab object binding target" end
            values[field or binding.property] = target
        end
        end
    end
    return true
end

function Hierarchy.capture(project, level, root)
    local paths, records, bindings = {}, {}, {}
    local function visit(object, path)
        paths[object.authoringId] = path
        local record = {id = path:match("([^/]+)$"), name = object.name, definitionReference = object.definitionReference,
            transform = assert(Transform.copy(object.transform)), overrides = {properties = Hierarchy.copy(object.propertyOverrides),
                components = Hierarchy.copy(object.componentOverrides)}, children = {}, removedPaths = Hierarchy.copy(object.prefabRemovedPaths)}
        records[#records + 1] = {object = object, record = record, path = path}
        local children, ids = level:getChildren(object), {}
        local function linkedId(child)
            if child.prefabRootId and child.prefabRootId == object.prefabRootId and child.prefabRootId ~= child.authoringId then
                return child.prefabNodePath:match("([^/]+)$")
            end
        end
        for _, child in ipairs(children) do
            local id = linkedId(child)
            if id then ids[id] = true end
        end
        for _, child in ipairs(children) do
            local linked = linkedId(child)
            local id = linked or "o" .. child.authoringId
            if not linked then
                local base, suffix = id, 1
                while ids[id] do id = base .. "_" .. suffix; suffix = suffix + 1 end
                ids[id] = true
            end
            record.children[#record.children + 1] = visit(child, path .. "/" .. id)
        end
        return record
    end
    local record = visit(root, "root")
    for _, entry in ipairs(records) do
        -- 원래 Prefab 루트를 제외하고 캡처하는 가지는 그 계층의 상속값도 보존한다.
        if entry.object.prefabRootId and not paths[entry.object.prefabRootId] then
            local data, err = Hierarchy.duplicateData(project, level, entry.object)
            if not data then return nil, err end
            entry.record.definitionReference = data.definitionReference
            entry.record.overrides = {properties = data.propertyOverrides, components = data.componentOverrides}
            entry.record.removedPaths = nil
        end
        local definition, err = Definition.resolve(project, entry.record.definitionReference)
        if not definition then return nil, err end
        local target, targetError = Definition.inspectorTarget(project, entry.object, definition, level, "Prefab")
        if not target then return nil, targetError end
        for name, declaration in pairs(target.class.properties) do
            if declaration.type == "object" then
                local component, field = name:match("^([^.]+)%.(.+)$")
                local fields = component and (entry.record.overrides.components or {})[component] or entry.record.overrides.properties
                local value = fields and fields[field or name]
                if value and value ~= false then
                    if not paths[value] then return nil, "Object reference leaves the Prefab hierarchy: " .. name end
                    bindings[#bindings + 1] = {from = entry.path, property = name, to = paths[value]}
                    fields[field or name] = false
                end
            end
        end
    end
    return {formatVersion = 3, definitionReference = record.definitionReference, overrides = record.overrides,
        children = record.children, bindings = bindings, removedPaths = record.removedPaths}
end

function Hierarchy.expandAuthoring(project, level, root)
    local recipe, err = Hierarchy.resolve(project, root.definitionReference)
    if not recipe then return nil, err end
    local objects = {root = root}
    local stale = {}
    for _, object in ipairs(level.lobjects) do
        if object.prefabRootId == root.authoringId then
            if object ~= root and (not recipe.byPath[object.prefabNodePath] or Hierarchy.isRemoved(object.prefabNodePath, root.prefabRemovedPaths)) then stale[#stale + 1] = object
            else objects[object.prefabNodePath] = object end
        end
    end
    if #stale > 0 then level:removeLObjects(stale, true) end
    if #recipe.nodes > 1 then root.prefabRootId, root.prefabNodePath = root.authoringId, "root" end
    for _, node in ipairs(recipe.nodes) do
        if node.parent and not objects[node.path] and not Hierarchy.isRemoved(node.path, root.prefabRemovedPaths) then
            local object = assert(level:addLObject(node.transform.x, node.transform.y, node.reference))
            local reference = node.reference and project:getAssetReference(node.reference)
            object.name = node.name or reference and reference:match("([^/]+)%.[^.]+$") or "LObject"
            object.transform = Hierarchy.copy(node.transform)
            object.prefabRootId, object.prefabNodePath = root.authoringId, node.path
            object.parentAuthoringId = objects[node.parent.path].authoringId
            objects[node.path] = object
        end
    end
    return objects, recipe
end

function Hierarchy.authoringDefinition(project, level, object)
    if not object.prefabRootId then return Definition.resolve(project, object.definitionReference) end
    local root = level:findLObject(object.prefabRootId)
    if not root then return nil, "Missing Prefab root instance" end
    local recipe, err = Hierarchy.resolve(project, root.definitionReference)
    if not recipe then return nil, err end
    local node = recipe.byPath[object.prefabNodePath]
    if not node then return nil, "Missing Prefab node: " .. tostring(object.prefabNodePath) end
    local definition = {class = node.definition.class, componentLoader = node.definition.componentLoader,
        classReference = node.definition.classReference, properties = Hierarchy.copy(node.definition.properties), components = Hierarchy.copy(node.definition.components), layers = node.definition.layers}
    for name, value in pairs(node.overrides.properties or {}) do definition.properties[name] = value end
    for name, fields in pairs(node.overrides.components or {}) do
        definition.components[name] = definition.components[name] or {}
        for field, value in pairs(fields) do definition.components[name][field] = value end
    end
    local objects = {root = root}
    for _, current in ipairs(level.lobjects) do if current.prefabRootId == root.authoringId then objects[current.prefabNodePath] = current end end
    for _, binding in ipairs(recipe.bindings) do
        if binding.from == node.path and objects[binding.to] then
            local component, field = binding.property:match("^([^.]+)%.(.+)$")
            if component then definition.components[component] = definition.components[component] or {}; definition.components[component][field] = objects[binding.to].authoringId
            else definition.properties[binding.property] = objects[binding.to].authoringId end
        end
    end
    return definition
end

function Hierarchy.duplicateData(project, level, object)
    local definition, err = Hierarchy.authoringDefinition(project, level, object)
    if not definition then return nil, err end
    local properties, components = Hierarchy.copy(definition.properties), Hierarchy.copy(definition.components)
    for name, value in pairs(object.propertyOverrides or {}) do properties[name] = value end
    for name, fields in pairs(object.componentOverrides or {}) do
        components[name] = components[name] or {}
        for field, value in pairs(fields) do components[name][field] = value end
    end
    return {definitionReference = definition.classReference, propertyOverrides = properties, componentOverrides = components}
end

function Hierarchy.prepareReparent(project, level, roots, parent)
    local changes, removals, references = {}, {}, {}
    for _, branch in ipairs(roots) do
        local sourceRoot = branch.prefabRootId and level:findLObject(branch.prefabRootId)
        if sourceRoot and sourceRoot ~= branch and (not parent or parent ~= sourceRoot and not level:isDescendant(parent, sourceRoot)) then
            local members, scope = {}, {root = sourceRoot}
            for _, object in ipairs(level.lobjects) do
                if object.prefabRootId == sourceRoot.authoringId then
                    scope[object.prefabNodePath] = object
                    if object == branch or level:isDescendant(object, branch) then
                        local definition, err = Hierarchy.authoringDefinition(project, level, object)
                        if not definition then return false, err end
                        local properties, components = Hierarchy.copy(definition.properties), Hierarchy.copy(definition.components)
                        for name, value in pairs(object.propertyOverrides or {}) do properties[name] = value end
                        for name, fields in pairs(object.componentOverrides or {}) do
                            components[name] = components[name] or {}
                            for field, value in pairs(fields) do components[name][field] = value end
                        end
                        changes[#changes + 1] = {object = object, definition = definition.classReference, properties = properties, components = components}
                        members[object] = true
                    end
                end
            end
            local recipe, err = Hierarchy.resolve(project, sourceRoot.definitionReference)
            if not recipe then return false, err end
            for _, binding in ipairs(recipe.bindings) do
                local from, target = scope[binding.from], scope[binding.to]
                if from and members[target] and not members[from] then references[#references + 1] = {object = from, property = binding.property, target = target.authoringId} end
            end
            removals[#removals + 1] = {root = sourceRoot, path = branch.prefabNodePath}
        end
    end
    for _, entry in ipairs(references) do
        local component, field = entry.property:match("^([^.]+)%.(.+)$")
        if component then
            entry.object.componentOverrides = entry.object.componentOverrides or {}
            entry.object.componentOverrides[component] = entry.object.componentOverrides[component] or {}
            if entry.object.componentOverrides[component][field] == nil then entry.object.componentOverrides[component][field] = entry.target end
        else
            entry.object.propertyOverrides = entry.object.propertyOverrides or {}
            if entry.object.propertyOverrides[entry.property] == nil then entry.object.propertyOverrides[entry.property] = entry.target end
        end
    end
    for _, entry in ipairs(removals) do entry.root.prefabRemovedPaths = entry.root.prefabRemovedPaths or {}; entry.root.prefabRemovedPaths[#entry.root.prefabRemovedPaths + 1] = entry.path end
    for _, entry in ipairs(changes) do
        entry.object.definitionReference, entry.object.propertyOverrides, entry.object.componentOverrides = entry.definition, entry.properties, entry.components
        entry.object.prefabRootId, entry.object.prefabNodePath, entry.object.prefabRemovedPaths = nil, nil, nil
    end
    return true
end
return Hierarchy
