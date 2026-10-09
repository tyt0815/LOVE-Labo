local Assert = {}

-- 값이 Lua의 truthy 값인지 검증한다.
-- Lua에서는 false와 nil만 false로 취급되고,
-- 0이나 빈 문자열("")은 true로 취급된다는 점이 C++과 다르다.
function Assert.truthy(value, message)
    if not value then
        error(message or "expected truthy value", 2)
    end
end

-- 두 값이 Lua의 == 연산 기준으로 같은지 검증한다.
function Assert.equal(expected, actual, message)
    if expected ~= actual then
        error(message or string.format(
            "expected %s, got %s",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

return Assert