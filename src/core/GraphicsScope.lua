local Scope = {}

-- 사용자 콜백이 남긴 중첩 push도 회수하고 오류와 반환값은 호출자에게 전달한다.
function Scope.call(callback, ...)
    local depth = love.graphics.getStackDepth()
    love.graphics.push("all")
    local ok, result, err = pcall(callback, ...)
    while love.graphics.getStackDepth() > depth do love.graphics.pop() end
    return ok, result, err
end

return Scope
