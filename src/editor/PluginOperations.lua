local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local Operations = {}
function Operations.plan(project, name, enabled)
    if not project.plugins.plugins[name] then return nil, "Unknown plugin: " .. tostring(name) end
    if enabled then return project.plugins:planEnable(name) end
    return project.plugins:planDisable(name)
end
function Operations.apply(project, name, enabled, confirm, level)
    local previousEnabled, previousLoaded = project.plugins.enabled, project.plugins.loaded
    local settingsPath = Fs.join(project.rootPath, "plugins.json")
    local previousSettings = Fs.read(settingsPath)
    local plan, err = Operations.plan(project, name, enabled)
    if not plan then return false, err end
    if #plan > 1 and not confirm then return false, "Confirm dependent plugins: " .. table.concat(plan, ", ") end
    local nextEnabled = {}
    for id, value in pairs(project.plugins.enabled) do nextEnabled[id] = value end
    for _, id in ipairs(plan) do nextEnabled[id] = enabled and true or nil end
    local valid, validationError = project.plugins:validate(nextEnabled)
    if not valid then return false, validationError end
    if not enabled then
        local view = setmetatable({assetMetadata = {}, assetPaths = {}, assetIds = {}, assetIdsByLower = {}}, {__index = project})
        view.plugins = project.plugins:forProject(view)
        view.plugins.enabled = nextEnabled
        view.pluginAssets = setmetatable({project = view, mounts = {}, groups = {}}, getmetatable(project.pluginAssets))
        for prefix, mount in pairs(project.pluginAssets.mounts) do
            if nextEnabled[mount.plugin] then
                view.pluginAssets.mounts[prefix] = mount
                view.pluginAssets.groups[prefix:match("^(.*)/[^/]+$")] = true
            end
        end
        for reference, value in pairs(project.assetMetadata) do
            local mount = project.pluginAssets and project.pluginAssets:mount(reference)
            if not mount or nextEnabled[mount.plugin] then
                view.assetMetadata[reference], view.assetPaths[value.id] = value, reference
                view.assetIds[reference], view.assetIdsByLower[reference:lower()] = value.id, value.id
            end
        end
        local ok, usageError = pcall(function()
            local result = require("editor.CliAssets").execute(view, {command = "project.validate"})
            assert(result.valid, result.errors[1] and result.errors[1].reference .. ": " .. result.errors[1].error)
            if level then assert(require("runtime.WorldLoader").validate(view, level:toData())) end
        end)
        if not ok then return false, "Plugin is used by the project: " .. tostring(usageError) end
    end
    local names = {}; for id in pairs(nextEnabled) do names[#names + 1] = id end; table.sort(names)
    local written, writeError = Fs.writeAtomic(settingsPath, assert(Json.encode({version = 1, enabled = Json.array(names)}, true)))
    if not written then return false, writeError end
    project.plugins.enabled, project.plugins.loaded = nextEnabled, {}
    project.draftRevision = (project.draftRevision or 0) + 1
    local indexOk, indexed, indexError = pcall(project.rebuildAssetIndex, project)
    if not indexOk or not indexed then
        if previousSettings then Fs.writeAtomic(settingsPath, previousSettings) else Fs.removeFile(settingsPath) end
        project.plugins.enabled, project.plugins.loaded = previousEnabled, previousLoaded
        pcall(project.rebuildAssetIndex, project)
        return false, tostring(indexOk and indexError or indexed)
    end
    return true, plan
end
function Operations.create(project, name, dependencies)
    if not name or not name:match("^[%a][%w_]*$") then return false, "Use a PascalCase plugin name" end
    if project.plugins.plugins[name] then return false, "Plugin already exists" end
    local root = Fs.join(project.rootPath, "Plugins")
    if not Fs.info(root) then local ok, err = Fs.mkdir(root); if not ok then return false, err end end
    local folder = Fs.join(root, name)
    if Fs.info(folder) then return false, "Plugin folder already exists" end
    local made, err = Fs.mkdir(folder); if not made then return false, err end
    assert(Fs.mkdir(Fs.join(folder, "Assets")))
    local scriptId = require("project.AssetId").new()
    local manifest = {version = 1, name = name, dependencies = Json.array(dependencies or {}),
        scripts = {[name] = "Assets/" .. name .. ".lua"}}
    local ok, writeError = Fs.createFile(Fs.join(folder, "plugin.json"), assert(Json.encode(manifest, true)))
    if ok then ok, writeError = Fs.createFile(Fs.join(folder, "Assets/" .. name .. ".lua"), "local " .. name .. " = {properties = {}}\nreturn " .. name .. "\n") end
    if ok then ok, writeError = Fs.createFile(Fs.join(folder, "assets.json"), assert(Json.encode({version = 1, assets = {["Assets/" .. name .. ".lua"] = {id = scriptId, scriptKind = "script", scriptName = name}}}, true))) end
    if not ok then
        Fs.removeFile(Fs.join(folder, "Assets/" .. name .. ".lua")); Fs.removeFile(Fs.join(folder, "assets.json"))
        Fs.removeFile(Fs.join(folder, "plugin.json")); Fs.removeDirectory(Fs.join(folder, "Assets")); Fs.removeDirectory(folder)
        return false, writeError
    end
    project.plugins = require("project.PluginRegistry").new(project)
    local indexed, indexError = project:rebuildAssetIndex()
    if not indexed then return false, indexError end
    return true, {name = name, folder = folder}
end
return Operations
