return [[-- labo-script: level
local Level = {}
-- 다른 Level 클래스를 상속하려면 .lua.meta의 ID를 지정한다.
-- Level.extends = "부모 클래스 ID"
Level.properties = {}

-- Play 시작 시 새 Runtime World를 초기화한다.
function Level.load(world)
end

-- 매 프레임 호출된다. dt는 초 단위다.
function Level.update(world, dt)
end

return Level
]]
