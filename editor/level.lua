local Level = {}
Level.__index = Level

function Level.new()
    local self = setmetatable({}, Level)

    -- 현재 단계에서는 Level이 배치된 LObject Instance 목록만 소유한다.
    -- Definition, Prefab, ID, Component 구조는 아직 도입하지 않는다.
    self.lobjects = {}

    return self
end

function Level:addLObject(x, y)
    local instance = {
        x = x,
        y = y
    }

    self.lobjects[#self.lobjects + 1] = instance

    return instance
end

return Level