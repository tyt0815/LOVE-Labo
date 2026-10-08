local Startup = {}

function Startup.openRequestedProject(args, projectStart, workingDirectory)
    local requestedPath
    for index, argument in ipairs(args or {}) do
        if argument == "--project" then
            projectStart.mode, projectStart.activeField = "open", "path"
            local path = args[index + 1]
            if requestedPath then
                projectStart.error = "Specify --project only once"
                return false, projectStart.error
            end
            if not path or path == "" or path:sub(1, 2) == "--" then
                projectStart.error = "--project requires a project folder path"
                return false, projectStart.error
            end
            requestedPath = path
        end
    end
    if not requestedPath then return false end

    local path = requestedPath:gsub("\\", "/")
    -- 상대 경로는 실행 명령의 작업 디렉터리를 기준으로 하여 IDE/스크립트에서도 동일하게 해석한다.
    if path:sub(1, 1) ~= "/" and not path:match("^%a:/") then
        path = require("editor.host_filesystem").join(workingDirectory, path)
    end
    projectStart.mode, projectStart.path = "open", path
    projectStart.activeField, projectStart.replace = "path", true
    -- 시작 화면의 검증과 오류 처리를 재사용해 수동 열기와 같은 동작을 보장한다.
    return projectStart:submit()
end

return Startup
