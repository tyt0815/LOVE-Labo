local Level = {}
local Transform = require("core.Transform")
Level.__index = Level

local FORMAT_VERSION = 2

Level.isValidScriptReference = require("project.Reference").validScript

local function isPositiveInteger(value)
    return type(value) == "number"
        and value >= 1
        and value % 1 == 0
end

local function validateDefinitionReference(reference)
    if reference == nil then
        return true
    end

    if type(reference) ~= "string"
        or reference == ""
    then
        return false,
            "lobject definitionReference must be a non-empty string"
    end

    return true
end

local function validateLObjectData(data, usedAuthoringIds)
    if type(data) ~= "table" then
        return nil, "lobject must be a table"
    end

    if not isPositiveInteger(data.authoringId) then
        return nil, "lobject authoringId must be a positive integer"
    end

    if usedAuthoringIds[data.authoringId] then
        return nil, "duplicate lobject authoringId"
    end

    local validDefinitionReference, definitionReferenceError =
        validateDefinitionReference(data.definitionReference)

    if not validDefinitionReference then
        return nil, definitionReferenceError
    end

    if type(data.transform) ~= "table" then
        return nil, "lobject transform must be a table"
    end

    if type(data.transform.x) ~= "number"
        or type(data.transform.y) ~= "number"
    then
        return nil, "lobject transform x/y must be numbers"
    end

    usedAuthoringIds[data.authoringId] = true
    local transform, transformError = Transform.copy(data.transform)
    if not transform then return nil, transformError end
    local properties, propertyError = require("editor.PropertyData").validate(data.propertyOverrides)
    if not properties then return nil, propertyError end
    local components, componentError = require("editor.PropertyData").validateComponents(data.componentOverrides)
    if not components then return nil, componentError end

    -- 입력 data table을 그대로 Level에 넣지 않는다.
    -- serialized/authoring data 사이에 mutable table reference가 공유되지 않게
    -- 필요한 값만 새 table로 복사한다.
    return {
        authoringId = data.authoringId,
        name = data.name, parentAuthoringId = data.parentAuthoringId,
        definitionReference = data.definitionReference,
        propertyOverrides = properties,
        componentOverrides = components,
        transform = transform
    }
end

function Level.new()
    local self = setmetatable({}, Level)

    -- Level이 배치된 LObject Instance의 authoring data를 소유한다.
    self.lobjects = {}
    self.propertyOverrides = {}

    -- authoringId는 현재 Level 안에서만 유일한 증가 숫자로 시작한다.
    -- 삭제된 ID는 재사용하지 않는다.
    self.nextAuthoringId = 1

    return self
end

function Level:addLObject(x, y, definitionReference, name)
    local validDefinitionReference, definitionReferenceError =
        validateDefinitionReference(definitionReference)

    if not validDefinitionReference then
        return nil, definitionReferenceError
    end

    local instance = {
        authoringId = self.nextAuthoringId,
        name = name and self:uniqueName(name),
        definitionReference = definitionReference,
        transform = {
            x = x,
            y = y,
            rotation = 0, rotationX = 0, rotationY = 0, scaleX = 1, scaleY = 1
        }
    }

    self.nextAuthoringId =
        self.nextAuthoringId + 1

    self.lobjects[#self.lobjects + 1] =
        instance

    return instance
end

function Level:setScriptReference(reference)
    local valid, err = Level.isValidScriptReference(reference)
    if not valid then return false, err end
    self.scriptReference = reference
    return true
end

function Level:duplicateLObject(target, x, y)
    if self:findLObject(target.authoringId) ~= target then return nil end
    local duplicate = self:duplicateLObjects({target})[1]
    if x ~= nil then duplicate.transform.x = x end
    if y ~= nil then duplicate.transform.y = y end
    return duplicate
end

function Level:removeLObject(target)
    return self:removeLObjects({target})
end

function Level:toData()
    local lobjects = {}

    for i, lobject in ipairs(self.lobjects) do
        -- Level 내부 authoring table을 그대로 노출하지 않고
        -- serialization 전용 plain data를 새로 만든다.
        lobjects[i] = {
            authoringId = lobject.authoringId,
            name = lobject.name, parentAuthoringId = lobject.parentAuthoringId,
            definitionReference =
                lobject.definitionReference,
            propertyOverrides = next(lobject.propertyOverrides or {}) and require("editor.PropertyData").copy(lobject.propertyOverrides) or nil,
            componentOverrides = next(lobject.componentOverrides or {}) and require("editor.PropertyData").copyComponents(lobject.componentOverrides) or nil,
            transform = Transform.toData(lobject.transform)
        }
    end

    return {
        formatVersion = FORMAT_VERSION,
        scriptReference = self.scriptReference,
        propertyOverrides = require("editor.PropertyData").copy(self.propertyOverrides),
        lobjects = lobjects
    }
end

function Level.fromData(data)
    if type(data) ~= "table" then
        return nil, "level data must be a table"
    end

    if data.formatVersion ~= 1 and data.formatVersion ~= FORMAT_VERSION then
        return nil, "unsupported level format version"
    end

    local validScript, scriptError = Level.isValidScriptReference(data.scriptReference)
    if not validScript then return nil, scriptError end
    local overrides, overrideError = require("editor.PropertyData").validate(data.propertyOverrides)
    if not overrides then return nil, overrideError end

    if type(data.lobjects) ~= "table" then
        return nil, "level lobjects must be a table"
    end

    local validatedLObjects = {}
    local usedAuthoringIds = {}
    local maxAuthoringId = 0

    -- 먼저 전체 입력을 검증하고 복사한다.
    -- 중간에 실패해도 반쯤 구성된 Level을 외부에 노출하지 않는다.
    for i, lobjectData in ipairs(data.lobjects) do
        local lobject, err =
            validateLObjectData(
                lobjectData,
                usedAuthoringIds
            )

        if not lobject then
            return nil,
                "invalid lobject "
                .. i
                .. ": "
                .. err
        end

        validatedLObjects[i] = lobject

        if lobject.authoringId > maxAuthoringId then
            maxAuthoringId =
                lobject.authoringId
        end
    end

    local level = Level.new()
    level.lobjects = validatedLObjects
    local validTree, treeError = level:validateHierarchy()
    if not validTree then return nil, treeError end
    level.scriptReference = data.scriptReference
    level.propertyOverrides = overrides

    -- 저장 시 nextAuthoringId 자체를 직렬화하지 않고,
    -- 가장 큰 stable ID 다음 값으로 복원한다.
    -- 따라서 삭제된 ID를 load 뒤에도 재사용하지 않는다.
    level.nextAuthoringId =
        maxAuthoringId + 1

    return level
end

function Level:findLObject(id)
    for _, object in ipairs(self.lobjects) do if object.authoringId == id then return object end end
end
function Level:uniqueName(base)
    local used = {}; for _, object in ipairs(self.lobjects) do if object.name then used[object.name] = true end end
    local number = 1; while used[base .. " " .. number] do number = number + 1 end
    return base .. " " .. number
end
function Level:getParent(object) return object.parentAuthoringId and self:findLObject(object.parentAuthoringId) end
function Level:isDescendant(object, ancestor)
    local parent = self:getParent(object)
    while parent do if parent == ancestor then return true end; parent = self:getParent(parent) end
    return false
end
function Level:getWorldTransform(object)
    local parent = self:getParent(object)
    return parent and Transform.compose(self:getWorldTransform(parent), object.transform) or object.transform
end
function Level:setWorldPosition(object, x, y)
    local parent = self:getParent(object)
    if parent then x, y = Transform.inversePoint(self:getWorldTransform(parent), x, y) end
    if not x then return false, "Parent Transform cannot be inverted" end
    object.transform.x, object.transform.y = x, y
    return true
end
function Level:selectionRoots(objects)
    local roots = {}
    for _, object in ipairs(objects) do
        local nested = false
        for _, other in ipairs(objects) do if object ~= other and self:isDescendant(object, other) then nested = true; break end end
        if not nested then roots[#roots + 1] = object end
    end
    return roots
end
function Level:reparent(objects, parent)
    if parent and self:findLObject(parent.authoringId) ~= parent then return false, "Parent is not in this level" end
    local roots, positions = self:selectionRoots(objects), {}
    for _, object in ipairs(roots) do
        if parent == object or parent and self:isDescendant(parent, object) then return false, "Object attachment cycle" end
        local world = self:getWorldTransform(object)
        local x, y = world.x, world.y
        if parent then x, y = Transform.inversePoint(self:getWorldTransform(parent), x, y) end
        if not x then return false, "Parent Transform cannot be inverted" end
        positions[object] = {x, y}
    end
    for _, object in ipairs(roots) do
        object.parentAuthoringId = parent and parent.authoringId or nil
        object.transform.x, object.transform.y = unpack(positions[object])
    end
    return true
end
function Level:validateHierarchy()
    for _, object in ipairs(self.lobjects) do
        if object.name ~= nil and (type(object.name) ~= "string" or object.name == "") then return false, "Invalid object name" end
        local visited, current = {}, object
        while current do
            if visited[current] then return false, "Object attachment cycle" end
            visited[current] = true
            if current.parentAuthoringId ~= nil and not self:findLObject(current.parentAuthoringId) then return false, "Missing object parent" end
            current = self:getParent(current)
        end
    end
    return true
end
function Level:treeRows(collapsed)
    local rows = {}
    local function visit(parent, depth)
        for _, object in ipairs(self.lobjects) do
            if object.parentAuthoringId == (parent and parent.authoringId or nil) then
                local children = false
                for _, child in ipairs(self.lobjects) do if child.parentAuthoringId == object.authoringId then children = true; break end end
                rows[#rows + 1] = {object = object, depth = depth, children = children}
                if not collapsed or not collapsed[object.authoringId] then visit(object, depth + 1) end
            end
        end
    end
    visit(nil, 0); return rows
end
function Level:removeLObjects(objects)
    local removed = {}
    for _, object in ipairs(self.lobjects) do
        for _, selected in ipairs(objects) do
            if object == selected or self:isDescendant(object, selected) then removed[object] = true; break end
        end
    end
    for i = #self.lobjects, 1, -1 do if removed[self.lobjects[i]] then table.remove(self.lobjects, i) end end
    return next(removed) ~= nil
end
function Level:duplicateLObjects(objects)
    local roots, result, originals = self:selectionRoots(objects), {}, {}
    for _, object in ipairs(self.lobjects) do originals[#originals + 1] = object end
    local function clone(object, parentId)
        local duplicate = assert(self:addLObject(object.transform.x, object.transform.y, object.definitionReference, object.name and object.name:gsub(" %d+$", "") or "LObject"))
        duplicate.transform = assert(Transform.copy(object.transform))
        duplicate.parentAuthoringId = parentId
        duplicate.propertyOverrides = require("editor.PropertyData").copy(object.propertyOverrides)
        duplicate.componentOverrides = require("editor.PropertyData").copyComponents(object.componentOverrides)
        result[#result + 1] = duplicate
        for _, child in ipairs(originals) do if child.parentAuthoringId == object.authoringId then clone(child, duplicate.authoringId) end end
        return duplicate
    end
    for _, root in ipairs(roots) do clone(root, root.parentAuthoringId) end
    return result
end

return Level
