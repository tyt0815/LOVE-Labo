local LObject = {}
LObject.__index = LObject

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
            "runtime definitionReference must be a non-empty string"
    end

    return true
end

local function validateTransform(transform)
    if type(transform) ~= "table" then
        return false,
            "runtime initial transform must be a table"
    end

    if type(transform.x) ~= "number"
        or type(transform.y) ~= "number"
    then
        return false,
            "runtime initial transform x/y must be numbers"
    end

    return true
end

function LObject.new(runtimeId, initialState)
    if not isPositiveInteger(runtimeId) then
        return nil,
            "runtimeId must be a positive integer"
    end

    if type(initialState) ~= "table" then
        return nil,
            "runtime initial lobject must be a table"
    end

    local validDefinitionReference, definitionReferenceError =
        validateDefinitionReference(
            initialState.definitionReference
        )

    if not validDefinitionReference then
        return nil, definitionReferenceError
    end

    local validTransform, transformError =
        validateTransform(initialState.transform)

    if not validTransform then
        return nil, transformError
    end

    local self =
        setmetatable({}, LObject)

    self.runtimeId = runtimeId

    -- 현재는 Definition 자체를 resolve하지 않고 identity만 보존한다.
    -- 이후 Project Loader/registry가 이 reference를 Project Lua Definition으로
    -- 연결하는 책임을 맡는다.
    self.definitionReference =
        initialState.definitionReference

    -- Runtime mutable state는 authoring/serialized data와 table reference를
    -- 공유하지 않도록 Runtime LObject가 자기 Transform을 소유한다.
    self.transform = {
        x = initialState.transform.x,
        y = initialState.transform.y
    }

    return self
end

function LObject:update(dt)
    -- 현재는 Runtime LObject 자체 behavior가 아직 없다.
    -- 이후 LObject Definition / Project Lua behavior가 연결될 lifecycle 경계다.
end

return LObject
