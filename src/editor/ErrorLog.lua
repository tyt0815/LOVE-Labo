local ErrorLog = {}
local watched = setmetatable({}, {__mode = "k"})

function ErrorLog.watch(target, field, session)
    if not target then return end
    local fields = watched[target]
    if fields and fields[field] then return end
    fields = fields or {}; watched[target] = fields
    local value = target[field]
    local previous = getmetatable(target) or {}
    local meta = {}; for key, item in pairs(previous) do meta[key] = item end
    local function report(err)
        if err then session:log("Error: " .. tostring(err), {color = {255, 80, 80}}) end
    end
    fields[field] = function(nextValue) value = nextValue end
    -- 기존 error 대입을 발생 이벤트로 처리하여 표시 프레임과 분리한다.
    rawset(target, field, nil)
    meta.__index = function(self, key)
        if key == field then return value end
        if type(previous.__index) == "function" then return previous.__index(self, key) end
        return previous.__index and previous.__index[key]
    end
    meta.__newindex = function(self, key, nextValue)
        if key == field then value = nextValue; report(nextValue)
        elseif type(previous.__newindex) == "function" then previous.__newindex(self, key, nextValue)
        elseif previous.__newindex then previous.__newindex[key] = nextValue
        else rawset(self, key, nextValue) end
    end
    setmetatable(target, meta)
    report(value)
end

-- 이미 기록된 오류의 표시 상태만 복원하며 새 발생으로 기록하지 않는다.
function ErrorLog.restore(target, field, value)
    local fields = watched[target]
    if fields and fields[field] then fields[field](value)
    else target[field] = value end
end

return ErrorLog
