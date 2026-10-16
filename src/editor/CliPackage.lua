local Fs = require("editor.HostFileSystem")
local CliPackage = {}

function CliPackage.runtimeDirectory()
    -- 배포된 에디터는 원본 console launcher도 보관한다. 이미 fuse된 Labo-cli.exe를 재결합하지 않는다.
    local directory = love.filesystem.isFused() and love.filesystem.getSourceBaseDirectory()
        or Fs.parent(love.filesystem.getExecutablePath())
    assert(Fs.info(Fs.join(directory, "lovec.exe")), "Missing raw LÖVE console runtime: " .. directory .. "/lovec.exe")
    return directory
end

function CliPackage.write(project, level, output, entry)
    assert(project:resolveSourceFile(entry))
    local definition = require("runtime.CliHost").definition(project, entry)
    require("project.GameCommands").describe(definition)
    local runtime = CliPackage.runtimeDirectory()
    local temporary = output .. "." .. require("project.AssetId").new() .. ".love"
    local ok, result = require("editor.GamePackage").write(project, level, temporary, {cliEntry = entry})
    assert(ok, result)
    local called, err = pcall(function()
        local bytes = assert(Fs.read(Fs.join(runtime, "lovec.exe"))) .. assert(Fs.read(temporary))
        assert(Fs.writeAtomic(output, bytes))
        for _, file in ipairs(assert(Fs.list(runtime))) do
            if file.type == "file" and file.name:lower():match("%.dll$") then
                assert(Fs.writeAtomic(Fs.join(Fs.parent(output), file.name), assert(Fs.read(Fs.join(runtime, file.name)))))
            end
        end
        local license = Fs.info(Fs.join(runtime, "license-love.txt")) and "license-love.txt" or "license.txt"
        assert(Fs.writeAtomic(Fs.join(Fs.parent(output), "license-love.txt"), assert(Fs.read(Fs.join(runtime, license)))))
        result.output, result.bytes = output, #bytes
    end)
    local removed, removeError = Fs.removeFile(temporary)
    assert(removed, removeError); assert(called, err)
    return result
end
return CliPackage
