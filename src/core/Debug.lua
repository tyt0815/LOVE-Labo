-- 배포 게임에서는 에디터 서비스가 주입되지 않으므로 같은 호출을 안전하게 무시한다.
local Debug = {}
for _, name in ipairs({"log", "screenLog", "point", "line", "circle", "rect", "polygon"}) do
    Debug[name] = function() return false end
end
return Debug
