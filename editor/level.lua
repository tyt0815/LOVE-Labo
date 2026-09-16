local Level = {}
Level.__index = Level

function Level.new()
    local self = setmetatable({}, Level)

    -- Level이 배치된 LObject Instance의 authoring data를 소유한다.
    self.lobjects = {}

    return self
end

function Level:addLObject(x, y)
    -- 현재는 Transform의 위치 정보만 가진다.
    -- rotation, scale, Definition/Prefab source 등은
    -- 실제 필요가 생기는 단계에서 추가한다.
    local instance = {
        transform = {
            x = x,
            y = y
        }
    }

    self.lobjects[#self.lobjects + 1] = instance

    return instance
end

function Level:duplicateLObject(target, x, y)
    -- 현재 authoring data 중 실제로 존재하는 Transform만 복제한다.
    -- nested table을 그대로 재사용하지 않고 addLObject를 통해 새 table을 만들어
    -- 원본과 복제본이 mutable Transform reference를 공유하지 않게 한다.
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
    for i, lobject in ipairs(self.lobjects) do
        if lobject == target then
            table.remove(self.lobjects, i)
            return true
        end
    end

    return false
end

return Level
