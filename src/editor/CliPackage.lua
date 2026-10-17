local CliPackage = {}
function CliPackage.runtimeDirectory()
    return require("editor.WindowsPackage").runtimeDirectory("lovec.exe")
end
function CliPackage.write(project, level, output, entry)
    assert(project:resolveSourceFile(entry))
    require("project.GameCommands").describe(require("runtime.CliHost").definition(project, entry))
    return require("editor.WindowsPackage").write(project, level, output, {cliEntry = entry})
end
return CliPackage
