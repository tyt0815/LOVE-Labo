local ClassName = {}
local reserved = {}
for name in ("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch("%S+") do reserved[name] = true end
function ClassName.fromModule(name, fallback)
    local identifier = (name or fallback):gsub("\\", "/"):match("([^/]+)$"):gsub("%.[Ll][Uu][Aa]$", "")
    -- 파일명은 한글·공백을 허용하지만 Lua 식별자는 별도로 보정한다.
    identifier = identifier:gsub("[^%w_]", "_")
    if not identifier:find("[%w]") then return fallback end
    if identifier:match("^%d") or reserved[identifier] then identifier = "Class_" .. identifier end
    return identifier
end
return ClassName
