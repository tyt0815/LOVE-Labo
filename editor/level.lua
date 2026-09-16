local Level = {}
Level.__index = Level

local FORMAT_VERSION = 1

local function isPositiveInteger(value)
    return type(value) == "number"
        and value >= 1
        and value % 1 == 0
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

    if type(data.transform) ~= "table" then
        return nil, "lobject transform must be a table"
    end

    if type(data.transform.x) ~= "number"
        or type(data.transform.y) ~= "number"
    then
        return nil, "lobject transform x/y must be numbers"
    end

    usedAuthoringIds[data.authoringId] = true

    -- 입력 data table을 그대로 Level에 넣지 않는다.
    -- serialized/authoring data 사이에 mutable table reference가 공유되지 않게
    -- 필요한 값만 새 table로 복사한다.
    return {
        authoringId = data.authoringId,
        transform = {
            x = data.transform.x,
            y = data.transform.y
        }
    }
end

function Level.new()
    local self = setmetatable({}, Level)

    -- Level이 배치된 LObject Instance의 authoring data를 소유한다.
    self.lobjects = {}

    -- authoringId는 현재 Level 안에서만 유일한 증가 숫자로 시작한다.
    -- 삭제된 ID는 재사용하지 않는다.
    self.nextAuthoringId = 1

    return self
end

function Level:addLObject(x, y)
    local instance = {
        authoringId = self.nextAuthoringId,
        transform = {
            x = x,
            y = y
        }
    }

    self.nextAuthoringId = self.nextAuthoringId + 1
    self.lobjects[#self.lobjects + 1] = instance

    return instance
end

function Level:duplicateLObject(target, x, y)
    -- 복제본은 원본과 다른 stable authoring identity를 가져야 한다.
    -- mutable Transform도 addLObject를 통해 새 table로 만든다.
    for _, lobject in ipairs(self.lobjects) do
        if lobject == target then
            local transform = lobject.transform
            local duplicateX = x or transform.x
            local duplicateY = y or transform.y

            return self:addLObject(duplicateX, duplicateY)
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
            transform = {
                x = lobject.transform.x,
                y = lobject.transform.y
            }
        }
    end

    return {
        formatVersion = FORMAT_VERSION,
        lobjects = lobjects
    }
end

function Level.fromData(data)
    if type(data) ~= "table" then
        return nil, "level data must be a table"
    end

    if data.formatVersion ~= FORMAT_VERSION then
        return nil, "unsupported level format version"
    end

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
            validateLObjectData(lobjectData, usedAuthoringIds)

        if not lobject then
            return nil, "invalid lobject " .. i .. ": " .. err
        end

        validatedLObjects[i] = lobject

        if lobject.authoringId > maxAuthoringId then
            maxAuthoringId = lobject.authoringId
        end
    end

    local level = Level.new()
    level.lobjects = validatedLObjects

    -- 저장 시 nextAuthoringId 자체를 직렬화하지 않고,
    -- 가장 큰 stable ID 다음 값으로 복원한다.
    -- 따라서 삭제된 ID를 load 뒤에도 재사용하지 않는다.
    level.nextAuthoringId = maxAuthoringId + 1

    return level
end

return Level
