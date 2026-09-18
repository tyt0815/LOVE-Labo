local World = {}
World.__index = World

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

local function copyRuntimeInitialState(lobjectData)
    if type(lobjectData) ~= "table" then
        return nil, "runtime initial lobject must be a table"
    end

    local validTransform, transformError =
        validateTransform(lobjectData.transform)

    if not validTransform then
        return nil, transformError
    end

    -- Runtime mutable state가 Level/serialization data와 table reference를
    -- 공유하지 않도록 현재 필요한 Transform 값을 새 table로 복사한다.
    return {
        transform = {
            x = lobjectData.transform.x,
            y = lobjectData.transform.y
        }
    }
end

function World.new()
    local self = setmetatable({}, World)

    self.lobjects = {}
    self.nextRuntimeId = 1

    return self
end

function World:addLObject(initialState)
    local copiedState, copyError =
        copyRuntimeInitialState(initialState)

    if not copiedState then
        return nil, copyError
    end

    local lobject = {
        runtimeId = self.nextRuntimeId,
        transform = copiedState.transform
    }

    self.nextRuntimeId = self.nextRuntimeId + 1
    self.lobjects[#self.lobjects + 1] = lobject

    return lobject
end

function World.fromLevelData(levelData)
    if type(levelData) ~= "table" then
        return nil, "level runtime data must be a table"
    end

    if type(levelData.lobjects) ~= "table" then
        return nil, "level runtime lobjects must be a table"
    end

    -- 먼저 모든 runtime initial state를 검증/복사한다.
    -- 중간 실패 시 반쯤 만들어진 World를 외부에 노출하지 않는다.
    local copiedStates = {}

    for i, lobjectData in ipairs(levelData.lobjects) do
        local copiedState, copyError =
            copyRuntimeInitialState(lobjectData)

        if not copiedState then
            return nil,
                "invalid runtime lobject "
                .. i
                .. ": "
                .. copyError
        end

        copiedStates[i] = copiedState
    end

    local world = World.new()

    for _, copiedState in ipairs(copiedStates) do
        local lobject = {
            runtimeId = world.nextRuntimeId,
            transform = copiedState.transform
        }

        world.nextRuntimeId = world.nextRuntimeId + 1
        world.lobjects[#world.lobjects + 1] = lobject
    end

    return world
end

return World
