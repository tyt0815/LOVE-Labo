local Fs = require("editor.HostFileSystem")
local Assets = {}
Assets.__index = Assets
local function ensure(path)
    if Fs.info(path) then return true end
    assert(ensure(Fs.parent(path)))
    return assert(Fs.mkdir(path))
end
function Assets.new(project)
    local self = setmetatable({mounts = {}, groups = {}, project = project}, Assets)
    project.plugins.assetScripts = {}
    for _, name in ipairs(project.plugins:names()) do if project.plugins.enabled[name] then
        local plugin = project.plugins.plugins[name]
        local category = plugin.origin == "labo" and "Labo Plugins" or "User Plugins"
        local reference = "Assets/" .. category .. "/" .. name
        local path = plugin.origin == "labo" and Fs.join(project.rootPath, ".labo/PluginCache/" .. name)
            or Fs.join(project.rootPath, "Plugins/" .. name .. "/Assets")
        if plugin.origin == "labo" then
            ensure(path)
            local function copy(source, destination)
                for _, file in ipairs(love.filesystem.getDirectoryItems(source)) do
                    local info = love.filesystem.getInfo(source .. "/" .. file)
                    if info.type == "directory" then ensure(Fs.join(destination, file)); copy(source .. "/" .. file, Fs.join(destination, file))
                    else
                        local bytes = assert(love.filesystem.read(source .. "/" .. file))
                        local target = Fs.join(destination, file)
                        if Fs.read(target) ~= bytes then assert(Fs.writeAtomic(target, bytes)) end
                    end
                end
            end
            copy("plugins/" .. name .. "/Assets", path)
        elseif not Fs.info(path) then ensure(path) end
        self.mounts[reference] = {path = path, plugin = name, readOnly = plugin.origin == "labo"}
        self.groups["Assets/" .. category] = true
        for script, file in pairs(plugin.scripts) do
            project.plugins.assetScripts[reference .. "/" .. file:gsub("^Assets/", "")] = script
        end
    end end
    return self
end
function Assets:mount(reference)
    for prefix, mount in pairs(self.mounts) do
        if reference == prefix or reference:sub(1, #prefix + 1) == prefix .. "/" then return mount, prefix end
    end
end
function Assets:path(reference)
    local mount, prefix = self:mount(reference)
    if mount then return mount.path .. reference:sub(#prefix + 1), mount end
end
function Assets:info(reference)
    if self.groups[reference] then return reference, {type = "directory", isLink = false} end
    local path, mount = self:path(reference)
    if not path then return nil end
    local current = mount.path
    local rootInfo = Fs.info(current)
    if not rootInfo or rootInfo.isLink then return false, "Plugin asset root is missing or a link" end
    for segment in path:sub(#current + 2):gmatch("[^/]+") do
        current = Fs.join(current, segment)
        local info, err = Fs.info(current)
        if not info or info.isLink then return false, err or "Plugin asset is missing or a link" end
        if current ~= path and info.type ~= "directory" then return false, "Plugin asset parent is not a directory" end
    end
    return path, Fs.info(path)
end
function Assets:list(reference)
    local entries = {}
    if reference == "Assets" then
        for group in pairs(self.groups) do entries[#entries + 1] = {name = group:match("([^/]+)$"), reference = group, type = "directory", isLink = false} end
        return entries
    end
    if self.groups[reference] then
        for prefix in pairs(self.mounts) do if prefix:match("^(.*)/[^/]+$") == reference then
            entries[#entries + 1] = {name = prefix:match("([^/]+)$"), reference = prefix, type = "directory", isLink = false}
        end end
    else
        local path, info = self:info(reference)
        if not path then return nil, info end
        for _, entry in ipairs(assert(Fs.list(path))) do
            if not require("editor.AssetRegistry").isInternal(entry.name) then
                entry.reference = reference .. "/" .. entry.name; entries[#entries + 1] = entry
            end
        end
    end
    table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)
    return entries
end
function Assets:readOnly(reference)
    if self.groups[reference] then return true end
    local mount = self:mount(reference)
    return mount and mount.readOnly or false
end
return Assets
