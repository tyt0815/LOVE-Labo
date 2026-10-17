local Fs = require("editor.HostFileSystem")
local WindowsPackage = {}

function WindowsPackage.runtimeDirectory(launcher)
    -- 이미 fuse된 Labo.exe/Labo-cli.exe 대신 배포본에 보관한 원본 런처를 사용한다.
    local directory = love.filesystem.isFused() and love.filesystem.getSourceBaseDirectory()
        or Fs.parent(love.filesystem.getExecutablePath())
    local info = Fs.info(Fs.join(directory, launcher))
    assert(info and info.type == "file" and not info.isLink, "Missing raw LÖVE runtime: " .. directory .. "/" .. launcher)
    return directory
end

function WindowsPackage.write(project, level, output, options)
    options = options or {}
    assert(type(output) == "string" and output:lower():match("%.exe$"), "Windows output must be an .exe file")
    output = require("project.Workspace").absolute(output)
    local launcher = options.cliEntry and "lovec.exe" or "love.exe"
    local runtime = WindowsPackage.runtimeDirectory(launcher)
    assert(Fs.parent(output):lower() ~= runtime:lower(), "Output folder must differ from the LÖVE runtime folder")
    local temporary = output .. "." .. require("project.AssetId").new() .. ".love"
    local ok, result = require("editor.GamePackage").write(project, level, temporary, options)
    assert(ok, result)
    local called, err = pcall(function()
        local bytes = assert(Fs.read(Fs.join(runtime, launcher))) .. assert(Fs.read(temporary))
        assert(Fs.writeAtomic(output, bytes))
        local dependencies = {}
        for _, file in ipairs(assert(Fs.list(runtime))) do
            if file.type == "file" and not file.isLink and file.name:lower():match("%.dll$") then
                local path = Fs.join(Fs.parent(output), file.name)
                assert(Fs.writeAtomic(path, assert(Fs.read(Fs.join(runtime, file.name)))))
                dependencies[#dependencies + 1] = path
            end
        end
        local license = Fs.info(Fs.join(runtime, "license-love.txt")) and "license-love.txt" or "license.txt"
        local path = Fs.join(Fs.parent(output), "license-love.txt")
        assert(Fs.writeAtomic(path, assert(Fs.read(Fs.join(runtime, license)))))
        dependencies[#dependencies + 1] = path
        result.output, result.bytes, result.platform, result.dependencies = output, #bytes, "windows", dependencies
    end)
    local removed, removeError = Fs.removeFile(temporary)
    assert(removed, removeError); assert(called, err)
    return result
end
return WindowsPackage
