local Hierarchy = require("project.PrefabHierarchy")
local Edit = {}
local function worldTransform(node)
    return node.parent and require("core.Transform").compose(worldTransform(node.parent), node.transform) or node.transform
end
local function combined(node, field, scale)
    local value = scale and 1 or 0
    while node do
        if scale then value = value * (node.transform[field] or 1) else value = value + (node.transform[field] or 0) end
        node = node.parent
    end
    return value
end
function Edit.move(editor, path, parentPath, index, rootChange)
    local recipe, err = editor:recipe(); if not recipe then return false, err end
    local node, parent = recipe.byPath[path], recipe.byPath[parentPath]
    if not node or node.isInherited then return false, "Inherited objects cannot be moved" end
    if rootChange and editor.document.data.definitionReference then return false, "Inherited Prefab roots cannot be changed" end
    if not rootChange and (path == "root" or not parent) then return false, "Invalid object destination" end
    if not rootChange and Hierarchy.isRemoved(parentPath, {path}) then return false, "Object attachment cycle" end
    local snapshot = Hierarchy.copy(editor.document.data)
    local mapping, replacement
    if rootChange then
        local root = Hierarchy.copy(editor.document.data)
        root.name, root.transform, root.formatVersion, root.bindings = recipe.root.name, {x = 0, y = 0}, nil, nil
        root.removedPaths = nil
        local function take(record, target)
            for position, child in ipairs(record.children or {}) do
                if child.id == target[1] then
                    if #target == 1 then table.remove(record.children, position); return child end
                    table.remove(target, 1); return take(child, target)
                end
            end
        end
        local segments = {}; for id in path:gmatch("/([^/]+)") do segments[#segments + 1] = id end
        replacement = take(root, segments)
        if not replacement then return false, "Missing new root" end
        replacement.children = replacement.children or {}
        local oldId = "previousRoot"; local used = {}; for _, child in ipairs(replacement.children) do used[child.id] = true end
        for _, child in ipairs(node.children) do used[child.path:match("[^/]+$")] = true end
        while used[oldId] do oldId = oldId .. "_" end
        root.id = oldId
        if root.definitionReference == editor.document.assetId then root.definitionReference = false end
        replacement.children[#replacement.children + 1] = root
        local origin, previous = worldTransform(node), worldTransform(recipe.root)
        local x, y = require("core.Transform").inversePoint(origin, previous.x, previous.y)
        if not x then return false, "New root Transform cannot be inverted" end
        root.transform = {x = x, y = y, rotation = combined(recipe.root, "rotation") - combined(node, "rotation"),
            rotationX = combined(recipe.root, "rotationX") - combined(node, "rotationX"), rotationY = combined(recipe.root, "rotationY") - combined(node, "rotationY"),
            scaleX = combined(recipe.root, "scaleX", true) / combined(node, "scaleX", true), scaleY = combined(recipe.root, "scaleY", true) / combined(node, "scaleY", true)}
        replacement.id, replacement.transform = nil, nil
        if replacement.definitionReference == false then replacement.definitionReference = nil end
        mapping = function(old)
            if old == path then return "root" end
            if Hierarchy.isRemoved(old, {path}) then return "root" .. old:sub(#path + 1) end
            return "root/" .. oldId .. old:sub(5)
        end
        replacement.formatVersion = 4
        editor.document.data = replacement
    else
        local siblings, inherited = parent.children, 0
        for _, child in ipairs(siblings) do if child.isInherited then inherited = inherited + 1 end end
        index = index or #siblings + 1
        if index <= inherited then return false, "Cannot insert between inherited objects" end
        replacement = Hierarchy.copy(editor:record(path, false))
        if not replacement then return false, "Missing local object record" end
        local before = worldTransform(node)
        local x, y = require("core.Transform").inversePoint(worldTransform(parent), before.x, before.y)
        if not x then return false, "Parent Transform cannot be inverted" end
        replacement.transform = Hierarchy.copy(node.transform); replacement.transform.x, replacement.transform.y = x, y
        local oldParent = editor:record(node.parent.path, true)
        for position, child in ipairs(oldParent.children or {}) do if child.id == node.path:match("[^/]+$") then table.remove(oldParent.children, position); break end end
        local destination = editor:record(parentPath, true)
        destination.children = destination.children or {}
        local id, number = replacement.id, 1; local used = {}
        for _, child in ipairs(parent.children) do if child ~= node then used[child.path:match("[^/]+$")] = true end end
        while used[id] do id = replacement.id .. "_" .. number; number = number + 1 end
        replacement.id = id
        if node.parent == parent then
            for position, child in ipairs(siblings) do if child == node and position < index then index = index - 1 end end
        end
        -- 해결된 순서에서 다음 로컬 형제를 찾아 실제 저장 배열의 삽입 위치로 변환한다.
        local remaining = {}
        for _, child in ipairs(siblings) do if child ~= node then remaining[#remaining + 1] = child end end
        local insertion = #destination.children + 1
        for position = index, #remaining do
            local child = remaining[position]
            if not child.isInherited then
                local nextId = child.path:match("[^/]+$")
                for stored, record in ipairs(destination.children) do if record.id == nextId then insertion = stored; break end end
                break
            end
        end
        table.insert(destination.children, insertion, replacement)
        local newPath = parentPath .. "/" .. id
        mapping = function(old) return Hierarchy.isRemoved(old, {path}) and newPath .. old:sub(#path + 1) or old end
    end
    local bindings = {}
    -- 원본이 제공하는 바인딩은 새 경로에서 다시 해석하고, 명시적인 로컬 바인딩만 옮긴다.
    for _, binding in ipairs(snapshot.bindings or {}) do
        bindings[#bindings + 1] = {from = mapping(binding.from), to = mapping(binding.to), property = binding.property, toScript = binding.toScript}
    end
    editor.document.data.bindings = bindings
    local removed = rootChange and Hierarchy.copy(editor.document.data.removedPaths or {}) or {}
    for _, old in ipairs(snapshot.removedPaths or {}) do removed[#removed + 1] = mapping(old) end
    editor.document.data.removedPaths = #removed > 0 and removed or nil
    local valid, validationError = editor:recipe()
    if not valid then editor.document.data = snapshot; return false, validationError end
    editor.selected = mapping(path); editor.onChanged(); return true
end
return Edit
