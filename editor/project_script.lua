local FS = require("editor.host_filesystem")
local ProjectScript = {}

function ProjectScript.load(project, reference)
    local path, pathError = project:resolveSourceFile(reference)
    if not path then return nil, pathError end
    local text, readError = FS.read(path)
    if not text then return nil, readError end
    local chunk, compileError = loadstring(text, "@" .. reference)
    if not chunk then return nil, compileError end
    -- Play마다 모듈과 전역 쓰기 영역을 새로 만든다. 보안용 VM 샌드박스는 아니다.
    setfenv(chunk, setmetatable({}, { __index = _G }))
    local ok, script = pcall(chunk)
    if not ok then return nil, tostring(script) end
    if type(script) ~= "table" then return nil, "Level script must return a table" end
    for _, name in ipairs({ "load", "update" }) do
        if script[name] ~= nil and type(script[name]) ~= "function" then
            return nil, "Level script " .. name .. " must be a function"
        end
    end
    return script
end

return ProjectScript
