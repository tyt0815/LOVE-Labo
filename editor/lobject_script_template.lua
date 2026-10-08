return [[-- labo-script: lobject
local LObject = {}
-- 다른 LObject 클래스를 상속하려면 .lua.meta의 ID를 지정한다.
-- LObject.extends = "부모 클래스 ID"
LObject.properties = {}

-- Runtime LObject가 생성될 때 초기화하는 동작을 작성한다.
function LObject.load(self, world)
end

-- Runtime LObject의 매 프레임 동작을 작성한다. dt는 초 단위다.
function LObject.update(self, dt)
end

return LObject
]]
