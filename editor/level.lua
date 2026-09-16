local Level = {}
Level.__index = Level

function Level.new()
    local self = setmetatable({}, Level)

    -- Level이 배치된 LObject Instance의 authoring data를 소유한다.
    self.lobjects = {}

    -- authoringId는 현재 Level 안에서만 유일한 증가 숫자로 시작한다.
    -- 삭제된 ID는 재사용하지 않아 같은 편집 세션에서 identity가 흔들리지 않게 한다.
    self.nextAuthoringId = 1

    return self
end

function Level:addLObject(x, y)
    -- 현재는 Transform의 위치 정보만 가진다.
    -- rotation, scale, Definition/Prefab source 등은
    -- 실제 필요가 생기는 단계에서 추가한다.
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

return Level
