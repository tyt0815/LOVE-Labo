return function(moduleName, parent)
    local name = require("editor.ClassName").fromModule(moduleName, "NewScript")
    local extends = parent and parent ~= "Script" and string.format("extends = %q, ", parent) or ""
    return string.format([[-- labo-script: script
local %s = {%sproperties = {}}

-- 필요한 콜백만 선언한다. self.owner는 소유 LObject다.
return %s
]], name, extends, name)
end
