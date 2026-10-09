-- 기존 호출 경로는 유지하고 클래스 로더에 위임한다.
local ProjectScript = {}
function ProjectScript.load(project, reference)
    return require("editor.LuaClass").load(project, reference, "level")
end
return ProjectScript