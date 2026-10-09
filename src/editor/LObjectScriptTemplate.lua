local TEMPLATE = [[-- labo-script: lobject
local __CLASS__ = {}
-- 다른 LObject 클래스를 상속하려면 .lua.meta의 ID를 지정한다.
-- __CLASS__.extends = "부모 클래스 ID"
__CLASS__.properties = {}

-- 에디터에서도 실행되는 구성 선언이다. beginPlay/update의 동작은 여기에 넣지 않는다.
function __CLASS__.build(self)
    -- local Engine = require("Engine")
    -- self:addComponent("sprite", Engine.SpriteComponent)
end

-- Runtime LObject가 생성될 때 초기화하는 동작을 작성한다.
function __CLASS__.beginPlay(self, world)
end

-- Runtime LObject의 매 프레임 동작을 작성한다. dt는 초 단위다.
function __CLASS__.update(self, dt)
end

return __CLASS__
]]
return function(name, parentId)
    local className = require("editor.ClassName").fromModule(name, "LObject")
    if parentId then
        -- 함수가 없는 자식은 부모의 구성·생명주기를 그대로 상속한다.
        return "-- labo-script: lobject\nlocal " .. className .. " = {}\n" .. className .. ".extends = "
            .. string.format("%q", parentId) .. "\n" .. className .. ".properties = {}\n\nreturn " .. className .. "\n"
    end
    return (TEMPLATE:gsub("__CLASS__", className))
end
