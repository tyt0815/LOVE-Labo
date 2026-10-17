local Output = {}
function Output.check(project, path)
    local prefix = project.rootPath:gsub("\\", "/"):gsub("/+$", ""):lower() .. "/"
    local normalized = require("project.Workspace").absolute(path):gsub("\\", "/"):lower()
    if normalized:sub(1, #prefix) == prefix then
        local reference = normalized:sub(#prefix + 1)
        local first = reference:match("^[^/]+")
        if first == "assets" or first == "tools" or first == "docs" or first == ".labo" or first == "plugins"
            or reference == "project.labo" or reference == "assets.json" or reference == "plugins.json"
            or reference == "agents.md" or reference == "conf.lua" then
            return false, "Build output overlaps project sources: " .. path
        end
    end
    return true
end
return Output
