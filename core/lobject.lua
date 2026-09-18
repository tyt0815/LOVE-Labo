local LObject = {}
LObject.__index = LObject

local function isPositiveInteger(value)
    return type(value) == "number"
        and value >= 1
        and value % 1 == 0
end

local function validateTransform(transform)
    if type(transform) ~= "table" then
        return false, "runtime initial transform must be a table"
    end

    if type(transform.x) ~= "number"
        or type(transform.y) ~= "number"
    then
        return false, "runtime initial transform x/y must be numbers"
    end

    return true
end

function LObject.new(runtimeId, initialState)
    if not isPositiveInteger(runtimeId) then
        return nil, "runtimeId must be a positive integer"
    end

    if type(initialState) ~= "table" then
        return nil, "runtime initial lobject must be a table"
    end

    local validTransform, transformError =
        validateTransform(initialState.transform)

    if not validTransform then
        return nil, transformError
    end

    local self = setmetatable({}, LObject)

    self.runtimeId = runtimeId

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
