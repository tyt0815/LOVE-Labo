local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local Id = require("project.AssetId")
local Catalog = {}
function Catalog.hash(bytes) return love.data.encode("string", "hex", love.data.hash("sha256", bytes)) end
function Catalog.owners(project)
    local result = {{prefix = "", root = project.rootPath, path = Fs.join(project.rootPath, "assets.json")}}
    for prefix, mount in pairs(project.pluginAssets and project.pluginAssets.mounts or {}) do
        local plugin = project.plugins.plugins[mount.plugin]
        result[#result + 1] = {prefix = prefix, root = Fs.parent(mount.path), plugin = plugin, readOnly = mount.readOnly,
            path = Fs.join(Fs.parent(mount.path), "assets.json")}
    end
    return result
end
function Catalog.owner(project, reference)
    for _, owner in ipairs(Catalog.owners(project)) do
        if owner.prefix ~= "" and reference:sub(1, #owner.prefix + 1) == owner.prefix .. "/" then
            return owner, "Assets" .. reference:sub(#owner.prefix + 1)
        end
    end
    return Catalog.owners(project)[1], reference
end
function Catalog.reference(owner, path)
    return owner.prefix == "" and path or owner.prefix .. path:sub(7)
end
function Catalog.read(owner)
    local bytes, readError
    if owner.readOnly then
        bytes, readError = owner.plugin.read("assets.json")
    else
        local info, infoError = Fs.info(owner.path)
        if infoError then return nil, infoError end
        if not info then return {version = 1, assets = {}} end
        bytes, readError = Fs.read(owner.path)
    end
    if not bytes then return nil, readError or "Cannot read assets.json" end
    local data, err = Json.decode(bytes)
    if type(data) ~= "table" or data.version ~= 1 or type(data.assets) ~= "table" then return nil, err or "Invalid assets.json" end
    local lower = {}
    for path, meta in pairs(data.assets) do
        if type(path) ~= "string" or not path:match("^Assets/") or path:find("\\", 1, true)
            or path:find("//", 1, true) or path:find("/%..-/") or path:find("%c")
            or type(meta) ~= "table" or not Id.isValid(meta.id) or lower[path:lower()] then return nil, "Invalid asset catalog entry" end
        lower[path:lower()] = true
        for part in path:gmatch("[^/]+") do if part == "." or part == ".." or part:match("[ .]$") then return nil, "Invalid catalog path" end end
    end
    return data
end
function Catalog.write(owner, data)
    if owner.readOnly then return false, "Labo assets are read-only" end
    return Fs.writeAtomic(owner.path, assert(Json.encode(data, true)) .. "\n")
end
function Catalog.importLegacy(owner, data)
    local legacy = {}
    if owner.readOnly then return legacy end
    local folder = Fs.join(owner.root, "Assets")
    local info, err = Fs.info(folder)
    if err then return nil, err end
    if not info then return legacy end
    local function visit(path)
        local info = Fs.info(path)
        if not info or info.isLink then return false, "Legacy metadata migration does not follow links" end
        local entries, listError = Fs.list(path); if not entries then return false, listError end
        for _, entry in ipairs(entries) do
            local file = Fs.join(path, entry.name)
            if entry.isLink then return false, "Legacy metadata migration does not follow links"
            elseif entry.type == "directory" then local ok, childError = visit(file); if not ok then return false, childError end
            elseif entry.name:match("%.meta$") then
                local metadata = Json.decode(Fs.read(file) or "")
                if type(metadata) ~= "table" or metadata.version ~= 1 or not Id.isValid(metadata.id) then return false, "Invalid legacy metadata: " .. file end
                local reference = file:sub(#owner.root + 2, -6)
                if data.assets[reference] and data.assets[reference].id ~= metadata.id then return false, "Conflicting legacy asset ID" end
                data.assets[reference] = data.assets[reference] or metadata
                legacy[#legacy + 1] = file
            end
        end
        return true
    end
    local ok, scanError = visit(folder); if not ok then return nil, scanError end
    return legacy
end
function Catalog.update(project, changes)
    local groups = {}
    for reference, meta in pairs(changes) do
        if type(reference) ~= "string" or not reference:match("^Assets/") or not project:isValidReference(reference)
            or meta ~= false and (type(meta) ~= "table" or not Id.isValid(meta.id)) then return false, "Invalid catalog update" end
        local owner, path = Catalog.owner(project, reference)
        if owner.readOnly then return false, "Labo assets are read-only" end
        local group = groups[owner.path]
        if not group then
            local data, err = Catalog.read(owner); if not data then return false, err end
            group = {owner = owner, data = data, before = Fs.read(owner.path)}; groups[owner.path] = group
        end
        if meta ~= false then
            for existingPath, existing in pairs(group.data.assets) do
                if existingPath:lower() == path:lower() and existing.id ~= meta.id then
                    return false, "Asset registration already exists: " .. reference
                end
            end
        end
        group.data.assets[path] = meta ~= false and meta or nil
    end
    local written = {}
    local function rollback()
        for _, old in ipairs(written) do
            if old.before then Fs.writeAtomic(old.owner.path, old.before) else Fs.removeFile(old.owner.path) end
        end
    end
    for _, group in pairs(groups) do
        if Fs.read(group.owner.path) ~= group.before then rollback(); return false, "Asset catalog revision conflict" end
        local ok, err = Catalog.write(group.owner, group.data)
        if not ok then
            rollback()
            return false, err
        end
        written[#written + 1] = group
    end
    return true
end
function Catalog.capture(project, reference)
    local result = {}
    local compared = reference:lower()
    for _, owner in ipairs(Catalog.owners(project)) do
        for path, meta in pairs(assert(Catalog.read(owner)).assets) do
            local full = Catalog.reference(owner, path)
            local lower = full:lower()
            if lower == compared or lower:sub(1, #compared + 1) == compared .. "/" then result[full] = meta end
        end
    end
    return result
end
function Catalog.checkDestination(project, reference)
    local compared = reference:lower()
    for _, owner in ipairs(Catalog.owners(project)) do
        local data, err = Catalog.read(owner)
        if not data then return false, err end
        for path in pairs(data.assets) do
            local full = Catalog.reference(owner, path):lower()
            if full == compared or full:sub(1, #compared + 1) == compared .. "/"
                or compared:sub(1, #full + 1) == full .. "/" then
                return false, "Destination has an existing asset registration; repair or remove it first: " .. reference
            end
        end
    end
    return true
end
function Catalog.remove(project, reference)
    local changes = {}; for path in pairs(Catalog.capture(project, reference)) do changes[path] = false end
    return Catalog.update(project, changes)
end
function Catalog.move(project, source, destination)
    local changes = {}
    for path, meta in pairs(Catalog.capture(project, source)) do
        changes[path], changes[destination .. path:sub(#source + 1)] = false, meta
    end
    return Catalog.update(project, changes)
end
return Catalog
