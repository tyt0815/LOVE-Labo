local template = [[-- labo-script: level
local __CLASS__ = {}
-- 다른 Level 클래스를 상속하려면 .lua.meta의 ID를 지정한다.
-- __CLASS__.extends = "부모 클래스 ID"
__CLASS__.properties = {}

-- Play 시작 시 새 Runtime World를 초기화한다.
function __CLASS__.BeginPlay(world)
end

-- 매 프레임 호출된다. dt는 초 단위다.
function __CLASS__.update(world, dt)
end

return __CLASS__
]]
return function(name, parentId)
    local className = require("editor.class_name").fromModule(name, "Level")
    if parentId then
        return "-- labo-script: level\nlocal " .. className .. " = {}\n" .. className .. ".extends = "
            .. string.format("%q", parentId) .. "\n" .. className .. ".properties = {}\n\nreturn " .. className .. "\n"
    end
    return (template:gsub("__CLASS__", className))
end
