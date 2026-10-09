return function(name, parent)
    local class = require("editor.ClassName").fromModule(name, "Component")
    return "-- labo-script: component\nlocal " .. class .. " = {}\n" .. class .. ".extends = "
        .. string.format("%q", parent or "LObjectComponent") .. "\n" .. class .. ".properties = {}\n\n"
        .. "-- 부모의 beginPlay/Update는 생략하면 그대로 상속한다.\nreturn " .. class .. "\n"
end
