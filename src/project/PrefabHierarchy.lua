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

function Hierarchy.mergeChildren(base, overrides, inherited)
    local result, byId = Hierarchy.copy(base or {}), {}
    for _, node in ipairs(result) do byId[node.id] = node end
    for _, override in ipairs(overrides or {}) do
        local node = byId[override.id]
        if not node then node = {id = override.id, isInherited = inherited == true}; result[#result + 1] = node; byId[node.id] = node end
        local removed = {}
        for _, id in ipairs(node.removedScripts or {}) do removed[id] = true end
        for _, item in ipairs(override.scripts or {}) do removed[item.id] = nil end
        for _, id in ipairs(override.removedScripts or {}) do removed[id] = true end
        for key, value in pairs(override) do
            if key == "isInherited" then if inherited == nil then node.isInherited = node.isInherited or value == true end
            elseif key == "scripts" then node.scripts = require("project.ScriptAttachments").merge(node.scripts, value)
            elseif key == "children" then node.children = Hierarchy.mergeChildren(node.children, value, inherited)
            elseif key == "transform" then
                node.transform = node.transform or {}
                for field, item in pairs(value) do node.transform[field] = item end
            elseif key == "overrides" then
                node.overrides = node.overrides or {}
                for kind, fields in pairs(value) do
                    node.overrides[kind] = node.overrides[kind] or {}
                    for name, field in pairs(fields) do
                        if kind == "scripts" then
                            node.overrides[kind][name] = node.overrides[kind][name] or {}
                            for property, item in pairs(field) do node.overrides[kind][name][property] = item end
                        else node.overrides[kind][name] = field end
                    end
                end
            else node[key] = Hierarchy.copy(value) end
        end
        node.removedScripts = {}; for id in pairs(removed) do node.removedScripts[#node.removedScripts + 1] = id end
        table.sort(node.removedScripts)
        node.scripts = require("project.ScriptAttachments").merge(node.scripts, nil, node.removedScripts)
        for _, id in ipairs(node.removedScripts or {}) do
            if node.overrides and node.overrides.scripts then node.overrides.scripts[id] = nil end
        end
    end
    return result
end

function Hierarchy.resolve(project, reference, loadClass, excludedId)
    local documentId = reference and (project:getAssetId(reference) or reference)
    loadClass = loadClass or require("project.LuaScript").loader(project)
    local nodes, bindings, operations, removedPaths = {}, {}, {}, {}
    local function build(reference, override, path, parent, depth, ancestorRemoved, visiting)
        visiting = visiting or {}
        if depth > 64 then return nil, "Prefab hierarchy is too deep" end
        local key = reference and (project:getAssetId(reference) or reference) or nil
        if key and key == excludedId then return nil, "Nested Prefab cycle" end
        local definition, err = Definition.resolve(project, reference, loadClass, excludedId)
        if not definition then return nil, err end
        definition = Definition.withAttachments(definition, override and override.scripts, override and override.removedScripts)
        definition.attachments = require("project.ScriptAttachments").reorder(definition.attachments, override and override.scriptOrder)
        local children, removed, pending, name = {}, Hierarchy.copy(ancestorRemoved or {}), {}, nil
        local function clearFields(record, prefix)
            for name in pairs(record.overrides and record.overrides.properties or {}) do pending[#pending + 1] = {from = prefix, property = name} end
            for name, fields in pairs(record.overrides and record.overrides.scripts or {}) do
                for field in pairs(fields) do pending[#pending + 1] = {from = prefix, property = name .. "." .. field} end
            end
            for _, child in ipairs(record.children or {}) do clearFields(child, prefix .. "/" .. child.id) end
        end
        for _, layer in ipairs(definition.layers) do
            if layer.name ~= nil then name = layer.name end
            children = Hierarchy.mergeChildren(children, layer.children, key ~= documentId or layer ~= definition.layers[#definition.layers])
            clearFields(layer, path)
            for _, prefix in ipairs(layer.removedPaths or {}) do removed[#removed + 1] = path .. prefix:sub(5) end
            for _, binding in ipairs(layer.bindings or {}) do
                pending[#pending + 1] = {from = path .. binding.from:sub(5), to = path .. binding.to:sub(5), property = binding.property, toScript = binding.toScript}
            end
        end
        if key and visiting[key] and #children > 0 then return nil, "Nested Prefab cycle" end
        if key then visiting[key] = (visiting[key] or 0) + 1 end
        local sourceChildren = {}
        for _, child in ipairs(children) do sourceChildren[child.id] = true end
        children = Hierarchy.mergeChildren(children, override and override.children)
        for _, prefix in ipairs(override and override.removedPaths or {}) do removed[#removed + 1] = path .. prefix:sub(5) end
        for _, prefix in ipairs(removed) do removedPaths[#removedPaths + 1] = prefix end
        local initial = {x = 0, y = 0}
        for field, value in pairs(override and override.transform or {}) do initial[field] = value end
        local transform, transformError = Transform.copy(initial)
        if not transform then return nil, transformError end
        local node = {path = path, parent = parent, reference = key, definition = definition,
            isInherited = override and override.isInherited == true,
            transform = transform, name = override and override.name or name,
            overrides = Hierarchy.copy(override and override.overrides or {}), children = {}}
        for _, id in ipairs(override and override.removedScripts or {}) do
            if node.overrides.scripts then node.overrides.scripts[id] = nil end
        end
        nodes[#nodes + 1] = node
        for _, child in ipairs(children) do
            if not Hierarchy.isRemoved(path .. "/" .. child.id, removed) then
            -- 상속용 부분 레코드는 ID 병합으로 원본을 유지하고, 새 무참조 노드는 기본 LObject다.
            -- 명시적으로 추가한 가지는 원본의 재귀 확장과 별개인 유한한 구성이다.
            local resolved, childError = build(child.definitionReference, child, path .. "/" .. child.id, node, depth + 1, removed,
                sourceChildren[child.id] and visiting or {})
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
    -- 제거된 발신 노드의 상속 바인딩은 사라진다. 살아 있는 노드의 끊어진 대상은 오류로 남긴다.
    for _, binding in pairs(effective) do
        local node = paths[binding.from]
        local script = binding.property:match("^([^.]+)%.")
        local removedScript = node and script and node.definition.removedScripts[script]
        if not removedScript and (node or not Hierarchy.isRemoved(binding.from, removedPaths)) then bindings[#bindings + 1] = binding end
    end
    for _, binding in ipairs(bindings) do
        if not paths[binding.from] or not paths[binding.to] then return nil, "Missing Prefab object binding" end
    end
    return {root = root, nodes = nodes, byPath = paths, bindings = bindings}
end

function Hierarchy.applyBindings(recipe, objects, overridden)
    for _, binding in ipairs(recipe.bindings) do
        local object, target = objects[binding.from], objects[binding.to]
        if object then
        local script, field = binding.property:match("^([^.]+)%.(.+)$")
        local values
        if script then local instance = object:getScriptById(script) or object:getScriptByName(script); values = instance and instance.properties
        else values = object.properties end
        if not values then return false, "Missing binding script" end
        if not (overridden and overridden[binding.from] and overridden[binding.from][binding.property]) then
            if not target then return false, "Missing Prefab object binding target" end
            values[field or binding.property] = binding.toScript and assert(target:getScriptById(binding.toScript) or target:getScriptByName(binding.toScript), "Missing script binding target") or target
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
            transform = assert(Transform.copy(object.transform)), scripts = require("project.ScriptAttachments").copy(object.scripts), overrides = {properties = Hierarchy.copy(object.propertyOverrides),
                scripts = Hierarchy.copy(object.scriptOverrides)}, children = {}, removedPaths = Hierarchy.copy(object.prefabRemovedPaths)}
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
            entry.record.scripts = require("project.ScriptAttachments").copy(data.scripts)
            entry.record.overrides = {properties = data.propertyOverrides, scripts = data.scriptOverrides}
            entry.record.removedPaths = nil
        end
        local definition, err = Hierarchy.authoringDefinition(project, level, entry.object)
        if not definition then return nil, err end
        local target, targetError = Definition.inspectorTarget(project, entry.object, definition, level, "Prefab")
        if not target then return nil, targetError end
        for name, declaration in pairs(target.class.properties) do
            if (declaration.type == "object" or declaration.type == "script") then
                local script, field = name:match("^([^.]+)%.(.+)$")
                local fields = script and (entry.record.overrides.scripts or {})[script] or entry.record.overrides.properties
                local value = fields and fields[field or name]
                if value and value ~= false then
                    local targetId = type(value) == "table" and value.authoringId or value
                    if not paths[targetId] then return nil, "Object reference leaves the Prefab hierarchy: " .. name end
                    bindings[#bindings + 1] = {from = entry.path, property = name, to = paths[targetId], toScript = type(value) == "table" and value.script or nil}
                    fields[field or name] = false
                end
            end
        end
    end
    return {formatVersion = 4, name = record.name, definitionReference = record.definitionReference, scripts = record.scripts, overrides = record.overrides,
        children = record.children, bindings = bindings, removedPaths = record.removedPaths}, nil, paths
end

function Hierarchy.canLinkCapture(root)
    if root.prefabRootId and root.prefabRootId ~= root.authoringId then
        return false, "Cannot replace an inherited member; select its owning Prefab root"
    end
    return true
end
function Hierarchy.linkCapture(project, level, root, reference, paths)
    local allowed, err = Hierarchy.canLinkCapture(root)
    if not allowed then return false, err end
    local recipe, resolveError = Hierarchy.resolve(project, reference)
    if not recipe then return false, resolveError end
    local objects = {}
    for id, path in pairs(paths) do
        local object = level:findLObject(id)
        if not object or not recipe.byPath[path] then return false, "Captured object hierarchy changed" end
        objects[path] = object
    end
    if objects.root ~= root then return false, "Captured root changed" end
    for _, node in ipairs(recipe.nodes) do if not objects[node.path] then return false, "Captured source hierarchy changed; refresh before creating a Prefab" end end
    -- ID·이름·Transform은 유지하고 에셋에 저장한 값은 인스턴스에서 제거한다.
    for _, node in ipairs(recipe.nodes) do
        local object = objects[node.path]
        if node.parent then object.definitionReference = node.reference
        else object.definitionReference = project:getAssetId(reference) or reference end
        object.prefabRootId, object.prefabNodePath = root.authoringId, node.path
        object.scripts, object.propertyOverrides, object.scriptOverrides, object.prefabRemovedPaths = nil, nil, nil, nil
        if node.parent then object.parentAuthoringId = objects[node.parent.path].authoringId end
    end
    return true
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
    if not object.prefabRootId then
        local definition, err = Definition.resolve(project, object.definitionReference)
        if not definition then return nil, err end
        return Definition.withAttachments(definition, object.scripts)
    end
    local root = level:findLObject(object.prefabRootId)
    if not root then return nil, "Missing Prefab root instance" end
    local recipe, err = Hierarchy.resolve(project, root.definitionReference)
    if not recipe then return nil, err end
    local node = recipe.byPath[object.prefabNodePath]
    if not node then return nil, "Missing Prefab node: " .. tostring(object.prefabNodePath) end
    local definition = {class = node.definition.class, scriptLoader = node.definition.scriptLoader,
        attachments = node.definition.attachments, classReference = node.definition.classReference, properties = Hierarchy.copy(node.definition.properties), scripts = Hierarchy.copy(node.definition.scripts), layers = node.definition.layers}
    for name, value in pairs(node.overrides.properties or {}) do definition.properties[name] = value end
    for name, fields in pairs(node.overrides.scripts or {}) do
        definition.scripts[name] = definition.scripts[name] or {}
        for field, value in pairs(fields) do definition.scripts[name][field] = value end
    end
    local objects = {root = root}
    for _, current in ipairs(level.lobjects) do if current.prefabRootId == root.authoringId then objects[current.prefabNodePath] = current end end
    for _, binding in ipairs(recipe.bindings) do
        if binding.from == node.path and objects[binding.to] then
            local script, field = binding.property:match("^([^.]+)%.(.+)$")
            if script then definition.scripts[script] = definition.scripts[script] or {}; definition.scripts[script][field] = binding.toScript and {authoringId = objects[binding.to].authoringId, script = binding.toScript} or objects[binding.to].authoringId
            else definition.properties[binding.property] = objects[binding.to].authoringId end
        end
    end
    return Definition.withAttachments(definition, object.scripts)
end

function Hierarchy.duplicateData(project, level, object)
    local definition, err = Hierarchy.authoringDefinition(project, level, object)
    if not definition then return nil, err end
    local properties, scripts = Hierarchy.copy(definition.properties), Hierarchy.copy(definition.scripts)
    for name, value in pairs(object.propertyOverrides or {}) do properties[name] = value end
    for name, fields in pairs(object.scriptOverrides or {}) do
        local attachment = require("project.ScriptAttachments").find(definition.attachments, name)
        name = attachment and attachment.id or name
        scripts[name] = scripts[name] or {}
        for field, value in pairs(fields) do scripts[name][field] = value end
    end
    local target, targetError = Definition.inspectorTarget(project, object, definition, level)
    if not target then return nil, targetError end
    local referenceFields = {}
    for name, declaration in pairs(target.class.properties) do if (declaration.type == "object" or declaration.type == "script") then
        referenceFields[#referenceFields + 1] = name
        local prefix, field = name:match("^([^.]+)%.(.+)$")
        local script = prefix and target.preview:getScriptById(prefix)
        if script then referenceFields[#referenceFields + 1] = script.name .. "." .. field end
    end end
    return {definitionReference = nil, scripts = require("project.ScriptAttachments").copy(definition.attachments), propertyOverrides = properties, scriptOverrides = scripts, referenceFields = referenceFields}
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
                        local properties, scripts = Hierarchy.copy(definition.properties), Hierarchy.copy(definition.scripts)
                        for name, value in pairs(object.propertyOverrides or {}) do properties[name] = value end
                        for name, fields in pairs(object.scriptOverrides or {}) do
                            scripts[name] = scripts[name] or {}
                            for field, value in pairs(fields) do scripts[name][field] = value end
                        end
                        changes[#changes + 1] = {object = object, attachments = definition.attachments, properties = properties, scripts = scripts}
                        members[object] = true
                    end
                end
            end
            local recipe, err = Hierarchy.resolve(project, sourceRoot.definitionReference)
            if not recipe then return false, err end
            for _, binding in ipairs(recipe.bindings) do
                local from, target = scope[binding.from], scope[binding.to]
                if from and members[target] and not members[from] then references[#references + 1] = {object = from, property = binding.property, target = binding.toScript and {authoringId = target.authoringId, script = binding.toScript} or target.authoringId} end
            end
            removals[#removals + 1] = {root = sourceRoot, path = branch.prefabNodePath}
        end
    end
    for _, entry in ipairs(references) do
        local script, field = entry.property:match("^([^.]+)%.(.+)$")
        if script then
            entry.object.scriptOverrides = entry.object.scriptOverrides or {}
            entry.object.scriptOverrides[script] = entry.object.scriptOverrides[script] or {}
            if entry.object.scriptOverrides[script][field] == nil then entry.object.scriptOverrides[script][field] = entry.target end
        else
            entry.object.propertyOverrides = entry.object.propertyOverrides or {}
            if entry.object.propertyOverrides[entry.property] == nil then entry.object.propertyOverrides[entry.property] = entry.target end
        end
    end
    for _, entry in ipairs(removals) do entry.root.prefabRemovedPaths = entry.root.prefabRemovedPaths or {}; entry.root.prefabRemovedPaths[#entry.root.prefabRemovedPaths + 1] = entry.path end
    for _, entry in ipairs(changes) do
        entry.object.definitionReference, entry.object.propertyOverrides, entry.object.scriptOverrides = entry.definition, entry.properties, entry.scripts
        entry.object.scripts = require("project.ScriptAttachments").copy(entry.attachments)
        entry.object.prefabRootId, entry.object.prefabNodePath, entry.object.prefabRemovedPaths = nil, nil, nil
    end
    return true
end
return Hierarchy
