local Array = {}

-- Lua의 #와 ipairs는 구멍이나 문자열 키가 있는 목록의 전체 항목을 보장하지 않는다.
function Array.isDense(value)
    if type(value) ~= "table" then return false end
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count, maximum = count + 1, math.max(maximum, key)
    end
    return count == maximum
end

return Array
