local Level = {}
local Transform = require("core.transform")
Level.__index = Level

local FORMAT_VERSION = 2

Level.isValidScriptReference = require("project.reference").validScript

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
    local properties, propertyError = require("editor.property_data").validate(data.propertyOverrides)
    if not properties then return nil, propertyError end
    local components, componentError = require("editor.property_data").validateComponents(data.componentOverrides)
    if not components then return nil, componentError end

    -- 입력 data table을 그대로 Level에 넣지 않는다.
    -- serialized/authoring data 사이에 mutable table reference가 공유되지 않게
    -- 필요한 값만 새 table로 복사한다.
    return {
        authoringId = data.authoringId,
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

function Level:addLObject(x, y, definitionReference)
    local validDefinitionReference, definitionReferenceError =
        validateDefinitionReference(definitionReference)

    if not validDefinitionReference then
        return nil, definitionReferenceError
    end

    local instance = {
        authoringId = self.nextAuthoringId,
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
    -- 복제본은 원본과 다른 stable authoring identity를 가져야 한다.
    -- source identity는 유지하고 mutable Transform은 새 table로 만든다.
    for _, lobject in ipairs(self.lobjects) do
        if lobject == target then
            local transform = lobject.transform
            local duplicateX = x or transform.x
            local duplicateY = y or transform.y

            local duplicate = self:addLObject(
                duplicateX,
                duplicateY,
                lobject.definitionReference
            )
            duplicate.propertyOverrides = require("editor.property_data").copy(lobject.propertyOverrides)
            duplicate.componentOverrides = require("editor.property_data").copyComponents(lobject.componentOverrides)
            duplicate.transform.rotation = lobject.transform.rotation or 0
            duplicate.transform.scaleX, duplicate.transform.scaleY = lobject.transform.scaleX or 1, lobject.transform.scaleY or 1
            duplicate.transform.rotationX, duplicate.transform.rotationY = lobject.transform.rotationX or 0, lobject.transform.rotationY or 0
            return duplicate
        end
    end

    return nil
end

function Level:removeLObject(target)
    -- Level이 authoring data의 소유자이므로
    -- LObject 제거도 Level을 통해 수행한다.
    -- 제거된 authoringId는 재사용하지 않는다.
    for i, lobject in ipairs(self.lobjects) do
        if lobject == target then
            table.remove(self.lobjects, i)
            return true
        end
    end

    return false
end

function Level:toData()
    local lobjects = {}

    for i, lobject in ipairs(self.lobjects) do
        -- Level 내부 authoring table을 그대로 노출하지 않고
        -- serialization 전용 plain data를 새로 만든다.
        lobjects[i] = {
            authoringId = lobject.authoringId,
            definitionReference =
                lobject.definitionReference,
            propertyOverrides = next(lobject.propertyOverrides or {}) and require("editor.property_data").copy(lobject.propertyOverrides) or nil,
            componentOverrides = next(lobject.componentOverrides or {}) and require("editor.property_data").copyComponents(lobject.componentOverrides) or nil,
            transform = Transform.toData(lobject.transform)
        }
    end

    return {
        formatVersion = FORMAT_VERSION,
        scriptReference = self.scriptReference,
        propertyOverrides = require("editor.property_data").copy(self.propertyOverrides),
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
    local overrides, overrideError = require("editor.property_data").validate(data.propertyOverrides)
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
    level.scriptReference = data.scriptReference
    level.propertyOverrides = overrides

    -- 저장 시 nextAuthoringId 자체를 직렬화하지 않고,
    -- 가장 큰 stable ID 다음 값으로 복원한다.
    -- 따라서 삭제된 ID를 load 뒤에도 재사용하지 않는다.
    level.nextAuthoringId =
        maxAuthoringId + 1

    return level
end

return Level
