local Hierarchy = require("project.PrefabHierarchy")
local Edit = {}
-- Prefab도 레벨 편집과 같은 저작 그래프에서 공개 배치·참조와 역변환을 평가한다.
local function evaluate(editor, callback)
    local level = require("editor.Level").new()
    level.layout = require("project.AuthoringLayout").new(editor.project, level)
    local ok, result = pcall(function()
        local root = assert(level:addLObject(0, 0, editor.document.assetId))
        local objects = assert(Hierarchy.expandAuthoring(editor.project, level, root))
        return callback(level, objects)
    end)
    level.layout:clear()
    assert(ok, result)
    return result
end
local function worldTransform(level, object)
    local preview = assert(level.layout:preview(object), level.layout.error)
    return preview:getWorldTransform()
end
local function combined(node, field, scale)
    local value = scale and 1 or 0
    while node do
        if scale then value = value * (node.transform[field] or 1) else value = value + (node.transform[field] or 0) end
        node = node.parent
    end
    return value
end
local function move(editor, path, parentPath, index, rootChange, snapshot)
    local recipe, err = editor:recipe(); if not recipe then return false, err end
    local node, parent = recipe.byPath[path], recipe.byPath[parentPath]
    if not node or node.isInherited then return false, "Inherited objects cannot be moved" end
    if not rootChange and (path == "root" or not parent) then return false, "Invalid object destination" end
    if not rootChange and Hierarchy.isRemoved(parentPath, {path}) then return false, "Object attachment cycle" end
    local before = (rootChange or node.parent ~= parent) and evaluate(editor, function(level, objects)
        return {node = worldTransform(level, objects[path]), root = worldTransform(level, objects.root)}
    end)
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
        local origin, previous = before.node, before.root
        local x, y = require("core.Transform").inversePoint(origin, previous.x, previous.y)
        if not x then return false, "New root Transform cannot be inverted" end
        root.transform = {x = x, y = y, rotation = combined(recipe.root, "rotation") - combined(node, "rotation"),
            rotationX = combined(recipe.root, "rotationX") - combined(node, "rotationX"), rotationY = combined(recipe.root, "rotationY") - combined(node, "rotationY"),
            scaleX = combined(recipe.root, "scaleX", true) / combined(node, "scaleX", true), scaleY = combined(recipe.root, "scaleY", true) / combined(node, "scaleY", true)}
        replacement.id, replacement.transform = nil, nil
        replacement.name = node.name
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
        replacement.transform = Hierarchy.copy(node.transform)
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
    local movedPath = rootChange and mapping("root") or mapping(path)
    if before then evaluate(editor, function(level, objects)
        local object = assert(objects[movedPath])
        assert(level.layout:preview(object), level.layout.error)
        local x, y = before.node.x, before.node.y
        if rootChange then
            x, y = require("core.Transform").inversePoint(before.node, before.root.x, before.root.y)
            x, y = require("core.Transform").point(worldTransform(level, objects.root), x, y)
        end
        local ok, err = level:setWorldPosition(object, x, y)
        assert(ok, err)
        local record = assert(editor:record(movedPath, false))
        record.transform = record.transform or {}
        record.transform.x, record.transform.y = object.transform.x, object.transform.y
    end) end
    editor.selected = mapping(path)
    return true
end
function Edit.move(editor, path, parentPath, index, rootChange)
    local snapshot, selected = Hierarchy.copy(editor.document.data), editor.selected
    local called, ok, err = pcall(move, editor, path, parentPath, index, rootChange, snapshot)
    if not called or not ok then
        editor.document.data, editor.selected = snapshot, selected
        return false, tostring(called and err or ok)
    end
    editor.onChanged()
    return true
end
return Edit
