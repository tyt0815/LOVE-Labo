local Json = require("editor.Json")
local RecentProjects = {FILE = "recent-projects.json", LIMIT = 30}

function RecentProjects.load(read)
    local ok, bytes = pcall(read or love.filesystem.read, RecentProjects.FILE)
    local data = ok and type(bytes) == "string" and Json.decode(bytes)
    local entries, seen = {}, {}
    for _, entry in ipairs(type(data) == "table" and data.version == 1 and type(data.projects) == "table" and data.projects or {}) do
        if type(entry) == "table" and type(entry.path) == "string" and type(entry.name) == "string" then
            local path = entry.path:gsub("\\", "/")
            if path ~= "" and not seen[path:lower()] and #entries < RecentProjects.LIMIT then
                entries[#entries + 1] = {path = path, name = entry.name}
                seen[path:lower()] = true
            end
        end
    end
    return entries
end

function RecentProjects.remember(entries, project)
    local result = {{path = project.rootPath:gsub("\\", "/"), name = project.name}}
    for _, entry in ipairs(entries) do
        if entry.path:lower() ~= result[1].path:lower() and #result < RecentProjects.LIMIT then
            result[#result + 1] = entry
        end
    end
    return result
end

function RecentProjects.save(entries, write)
    local bytes = assert(Json.encode({version = 1, projects = entries}, true))
    return (write or love.filesystem.write)(RecentProjects.FILE, bytes)
end

return RecentProjects
