local template = [[-- labo-script: lobject
local __CLASS__ = {}
-- 다른 LObject 클래스를 상속하려면 .lua.meta의 ID를 지정한다.
-- __CLASS__.extends = "부모 클래스 ID"
__CLASS__.properties = {}

-- 에디터에서도 실행되는 구성 선언이다. BeginPlay/Update의 동작은 여기에 넣지 않는다.
function __CLASS__.build(self)
    -- local Engine = require("engine")
    -- self:addComponent("sprite", Engine.SpriteComponent)
end

-- Runtime LObject가 생성될 때 초기화하는 동작을 작성한다.
function __CLASS__.BeginPlay(self, world)
end

-- Runtime LObject의 매 프레임 동작을 작성한다. dt는 초 단위다.
function __CLASS__.update(self, dt)
end

return __CLASS__
]]
return function(name) return (template:gsub("__CLASS__", require("editor.class_name").fromModule(name, "LObject"))) end
