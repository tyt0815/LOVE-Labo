local Fs = require("editor.HostFileSystem")
local Workspace = require("project.Workspace")
local Build = {}
Build.SCRIPT = "Tools/Build.lua"

function Build.ensureScript(project)
    local workspace = Workspace.new(project.rootPath)
    local path = workspace:path(Build.SCRIPT)
    local info, err = Fs.info(path)
    assert(not err, err)
    if info then assert(info.type == "file" and not info.isLink, "Build script must be a regular file")
    else
        Workspace.ensureDirectory(Fs.parent(path))
        assert(Fs.createFile(path, require("editor.BuildTemplate").text))
    end
    return path
end

function Build.run(project, level, output, options)
    options = options or {}
    local logs, artifacts = {}, {}
    local folder
    local ok, result = xpcall(function()
        assert(options.platform == nil or options.platform == "windows", "Unsupported platform: " .. tostring(options.platform))
        assert(type(output) == "string" and (output:lower():match("%.love$") or output:lower():match("%.exe$")), "Output must be an .exe or .love file")
        output = output:gsub("\\", "/")
        if not output:match("^%a:/") then output = Fs.join(project.rootPath, output) end
        output = Workspace.absolute(output)
        local script = Build.ensureScript(project)
        require("editor.GameConfig").ensure(project)
        local source = Workspace.new(project.rootPath)
        folder = Fs.parent(output)
        -- 배포 파일로 프로젝트 소스나 빌드 스크립트를 덮어쓰지 않는다.
        local function checkOutput(path)
            local prefix = project.rootPath:gsub("/+$", ""):lower() .. "/"
            if path:lower():sub(1, #prefix) == prefix then
                local reference = path:sub(#prefix + 1):lower()
                local first = reference:match("^[^/]+")
                assert(first ~= "assets" and first ~= "tools" and first ~= "docs" and first ~= ".labo"
                    and reference ~= "project.labo" and reference ~= "assets.json" and reference ~= "plugins.json"
                    and reference ~= "agents.md" and reference ~= "conf.lua", "Build output overlaps project sources: " .. path)
            end
            return path
        end
        checkOutput(output)
        Workspace.ensureDirectory(folder)
        local destination = Workspace.new(folder)
        local builder = {output = output, outputDirectory = folder, projectDirectory = project.rootPath, platform = "windows"}
        function builder:log(message) logs[#logs + 1] = tostring(message) end
        function builder:packageGame(name)
            local path = checkOutput(destination:path(name or output:match("[^/]+$")))
            Workspace.ensureDirectory(Fs.parent(path))
            local info
            if path:lower():match("%.exe$") then info = require("editor.WindowsPackage").write(project, level, path)
            else
                local written
                written, info = require("editor.GamePackage").write(project, level, path)
                assert(written, info)
            end
            artifacts[#artifacts + 1] = info
            self:log("Game: " .. path)
            return info
        end
        function builder:packageCli(name, options)
            assert(type(name) == "string" and name:lower():match("%.exe$"), "CLI output must be an .exe file")
            assert(type(options) == "table" and type(options.entry) == "string", "Specify a CLI entry module")
            local path = checkOutput(destination:path(name))
            Workspace.ensureDirectory(Fs.parent(path))
            local info = require("editor.CliPackage").write(project, level, path, options.entry)
            artifacts[#artifacts + 1] = info; self:log("CLI: " .. path)
            return info
        end
        function builder:copy(reference, name)
            local bytes = source:read(reference)
            checkOutput(destination:path(name))
            destination:write(name, bytes)
            local info = {output = destination:path(name), bytes = #bytes}
            artifacts[#artifacts + 1] = info; self:log("Copy: " .. name)
            return info
        end
        local moduleRequire = require("project.LuaScript").moduleLoader(project, project.plugins)
        local chunk = assert(loadstring(assert(Fs.read(script)), "@" .. script))
        setfenv(chunk, setmetatable({require = moduleRequire}, {__index = _G}))
        local run = chunk()
        assert(type(run) == "function", "Tools/Build.lua must return function(builder)")
        builder:log("Build: " .. script)
        run(builder)
        assert(#artifacts > 0, "Build produced no artifacts")
        return {output = output, outputDirectory = folder, platform = "windows", script = script, artifacts = artifacts, logs = logs,
            files = artifacts[1].files, bytes = artifacts[1].bytes}
    end, debug.traceback)
    if not ok then logs[#logs + 1] = tostring(result) end
    local report = ok and result or {error = tostring(result), outputDirectory = folder, logs = logs, artifacts = artifacts}
    -- 실패 시에도 이미 만들어진 파일과 로그를 숨기지 않는다. 빌드는 전체 트랜잭션이 아니다.
    return ok, ok and report or report.error, report
end
return Build
