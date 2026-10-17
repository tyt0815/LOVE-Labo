local Json = require("project.Json")
local Registry = {}
Registry.__index = Registry
local BUILTINS = {"LaboEssentials"}
local LEGACY = {Camera = true, Sprite = true, Pointer = true, Rect = true, Canvas = true}

function Registry.publicMetadata(assets, name, file)
    local metadata, path
    for reference, item in pairs(assets) do
        if item.scriptName == name then
            assert(not metadata, "Duplicate public script alias: " .. name)
            metadata, path = item, reference
        end
    end
    return metadata or assets[file], path or file
end

function Registry.new(project, packaged)
    local self = setmetatable({project = project, plugins = {}, scripts = {}, enabled = {}, loaded = {}, assetScripts = {}}, Registry)
    local function register(manifest, origin, read)
        assert(type(manifest) == "table" and manifest.version == 1 and type(manifest.name) == "string"
            and manifest.name:match("^[%a][%w_]*$"), "Invalid plugin manifest")
        assert(not self.plugins[manifest.name], "Duplicate plugin: " .. manifest.name)
        manifest.dependencies = manifest.dependencies or {}
        manifest.scripts = manifest.scripts or {}
        for _, dependency in ipairs(manifest.dependencies) do assert(type(dependency) == "string", "Invalid plugin dependency") end
        manifest.origin, manifest.read = origin, read
        self.plugins[manifest.name] = manifest
        local catalog = manifest.assets
        if not catalog then
            local bytes = read("assets.json")
            if bytes then catalog = assert(Json.decode(bytes)).assets end
        end
        manifest.assets = catalog or {}
        for name, file in pairs(manifest.scripts) do
            assert(type(name) == "string" and name:match("^[%a][%w_]*$") and type(file) == "string"
                and file:match("^Assets/[%w_]+%.lua$") and name ~= "Script" and not self.scripts[name], "Invalid or duplicate plugin script")
            local metadata, source = Registry.publicMetadata(manifest.assets, name, file)
            self.scripts[name] = {plugin = manifest.name, file = source, id = metadata and metadata.id or manifest.scriptIds and manifest.scriptIds[name]}
        end
    end
    if packaged then
        self.assetScripts = packaged.assetScripts or {}
        for _, manifest in ipairs(packaged.manifests or {}) do
            local name = manifest.name
            register(manifest, "package", function(file) return love.filesystem.read("plugins/" .. name .. "/" .. file) end)
        end
        for _, name in ipairs(packaged.enabled or {}) do self.enabled[name] = true end
    else
        for _, name in ipairs(BUILTINS) do
            local path = "plugins/" .. name
            register(assert(Json.decode(assert(love.filesystem.read(path .. "/plugin.json")))), "labo",
                function(file) return love.filesystem.read(path .. "/" .. file) end)
        end
        local Fs = require("editor.HostFileSystem")
        local folder = Fs.join(project.rootPath, "Plugins")
        if Fs.info(folder) then
            for _, entry in ipairs(assert(Fs.list(folder))) do
                if entry.type == "directory" and not entry.isLink then
                    local path = Fs.join(folder, entry.name)
                    local bytes = Fs.read(Fs.join(path, "plugin.json"))
                    if bytes then
                        local manifest = assert(Json.decode(bytes))
                        local Catalog = require("editor.AssetCatalog")
                        local owner = {root = path, path = Fs.join(path, "assets.json")}
                        local data = assert(Catalog.read(owner)); local legacy = assert(Catalog.importLegacy(owner, data))
                        for script, file in pairs(manifest.scripts or {}) do
                            local metadata = Registry.publicMetadata(data.assets, script, file)
                            local oldId = manifest.scriptIds and manifest.scriptIds[script]
                            if not metadata and oldId then metadata = {id = oldId, scriptKind = "script"}; data.assets[file] = metadata end
                            if metadata then metadata.scriptName = script end
                        end
                        local catalogBytes = assert(Json.encode(data, true)) .. "\n"
                        if Fs.read(owner.path) ~= catalogBytes then assert(Catalog.write(owner, data)) end
                        for _, file in ipairs(legacy) do assert(Fs.removeFile(file)) end
                        if manifest.scriptIds then manifest.scriptIds = nil; assert(Fs.writeAtomic(Fs.join(path, "plugin.json"), assert(Json.encode(manifest, true)))) end
                        register(manifest, "user", function(file) return Fs.read(Fs.join(path, file)) end)
                    end
                end
            end
        end
        local bytes = Fs.read(Fs.join(project.rootPath, "plugins.json"))
        if bytes then
            local settings = assert(Json.decode(bytes))
            assert(settings.version == 1 and type(settings.enabled) == "table", "Invalid plugin settings")
            for _, name in ipairs(settings.enabled) do self.enabled[LEGACY[name] and not self.plugins[name] and "LaboEssentials" or name] = true end
        else
            -- 이전 프로젝트의 편의 스크립트 참조는 설정 파일을 만들 때까지 유지한다.
            for _, name in ipairs(BUILTINS) do self.enabled[name] = true end
        end
    end
    if self.scripts.RectBounds then self.scripts.Rect = self.scripts.RectBounds end
    -- 기존 사용자 플러그인의 선행 플러그인 이름도 새 묶음으로 해석한다.
    for _, plugin in pairs(self.plugins) do
        local dependencies, seen = {}, {}
        for _, name in ipairs(plugin.dependencies) do
            name = LEGACY[name] and not self.plugins[name] and "LaboEssentials" or name
            if not seen[name] then dependencies[#dependencies + 1], seen[name] = name, true end
        end
        plugin.dependencies = dependencies
    end
    local valid, err = self:validate(self.enabled)
    self.error = not valid and err or nil
    return self
end

function Registry:forProject(project)
    return setmetatable({project = project, plugins = self.plugins, scripts = self.scripts,
        enabled = self.enabled, assetScripts = self.assetScripts, loaded = {}}, Registry)
end

function Registry:planEnable(name)
    local result, visiting, visited = {}, {}, {}
    local function visit(id)
        if visiting[id] then return false, "Plugin dependency cycle: " .. id end
        if visited[id] then return true end
        local plugin = self.plugins[id]
        if not plugin then return false, "Missing plugin: " .. id end
        for name, declared in pairs(plugin.scripts) do
            local source = self.scripts[name]
            local file = source and source.plugin == id and source.file or declared
            local ok, bytes = pcall(plugin.read, file)
            if not ok or not bytes then
                local found = false
                if source and source.plugin == id and source.id then
                    local reference = self.project:getAssetReference(source.id)
                    if reference then
                        local readable, content = pcall(self.project.readSource, self.project, reference)
                        found = readable and content ~= nil
                    end
                end
                if not found then return false, "Missing plugin script: " .. id .. "/" .. file end
            end
        end
        visiting[id] = true
        for _, dependency in ipairs(plugin.dependencies) do
            local ok, err = visit(dependency); if not ok then return false, err end
        end
        visiting[id], visited[id] = nil, true
        if not self.enabled[id] then result[#result + 1] = id end
        return true
    end
    local ok, err = visit(name)
    return ok and result or nil, err
end
function Registry:planDisable(name)
    local removed = {[name] = true}
    local changed = true
    while changed do
        changed = false
        for id, plugin in pairs(self.plugins) do
            if self.enabled[id] and not removed[id] then
                for _, dependency in ipairs(plugin.dependencies) do
                    if removed[dependency] then removed[id], changed = true, true; break end
                end
            end
        end
    end
    local result = {}; for id in pairs(removed) do if self.enabled[id] then result[#result + 1] = id end end
    table.sort(result); return result
end
function Registry:validate(enabled)
    for name in pairs(enabled) do
        if not self.plugins[name] then return false, "Missing enabled plugin: " .. name end
        local plan, err = self:planEnable(name); if not plan then return false, err end
        for _, dependency in ipairs(self.plugins[name].dependencies) do
            if not enabled[dependency] then return false, "Disabled dependency: " .. dependency end
        end
    end
    return true
end
function Registry:names()
    local names = {}; for name in pairs(self.plugins) do names[#names + 1] = name end
    table.sort(names); return names
end
function Registry:scriptNames()
    local names = {"Script"}
    for name, source in pairs(self.scripts) do if self.enabled[source.plugin] and not (name == "Rect" and self.scripts.RectBounds) then names[#names + 1] = name end end
    table.sort(names); return names
end
function Registry:loadScript(name)
    if name == "Rect" and self.scripts.RectBounds then name = "RectBounds" end
    if name == "Script" then return require("core.Script") end
    local source = self.scripts[name]
    if not source then return nil, "Unknown plugin script: " .. tostring(name) end
    if not self.enabled[source.plugin] then return nil, "Plugin is disabled: " .. source.plugin end
    local valid, dependencyError = self:validate(self.enabled)
    if not valid then return nil, dependencyError end
    if self.loaded[name] then return self.loaded[name] end
    self.loading = self.loading or {}
    if self.loading[name] then return nil, "Plugin script inheritance cycle: " .. name end
    self.loading[name] = true
    local reference
    local readOk, bytes = pcall(function()
        reference = source.id and self.project:getAssetReference(source.id)
        if reference then return assert(self.project:readSource(reference)) end
        return assert(self.plugins[source.plugin].read(source.file))
    end)
    if not readOk then self.loading[name] = nil; return nil, tostring(bytes) end
    local ok, class = pcall(function()
        local definition
        if self.loadModule then
            definition = self.loadModule(reference or "plugin/" .. source.plugin .. "/" .. source.file, bytes)
        else
            local chunk = assert(loadstring(bytes, "@plugin/" .. source.plugin .. "/" .. source.file))
            self.moduleRequire = self.moduleRequire or require("project.LuaScript").moduleLoader(self.project, self)
            setfenv(chunk, setmetatable({require = self.moduleRequire, love = self.moduleRequire("love")}, {__index = _G}))
            definition = chunk()
        end
        assert(type(definition) == "table", "Plugin script must return a table")
        local parent
        if not getmetatable(definition) then
            parent = require("core.Script")
            if definition.extends then
                parent = self.scripts[definition.extends] and assert(self:loadScript(definition.extends))
                    or assert((self.classLoader or require("project.LuaScript").loader(self.project))(definition.extends, "script"))
                local source = self.scripts[definition.extends]
                if source then definition.extends = source.id end
            end
        end
        return require("project.LuaScript").scriptClass(definition, name, parent)
    end)
    self.loading[name] = nil
    if not ok then return nil, tostring(class) end
    self.loaded[name] = class
    return class
end
function Registry:engine()
    return setmetatable({}, {__index = function(_, name)
        if self.scripts[name] then return assert(self:loadScript(name)) end
        return require("Engine")[name]
    end})
end
function Registry:export()
    local manifests, enabled = {}, {}
    for _, name in ipairs(self:names()) do if self.enabled[name] then
        local plugin = self.plugins[name]
        manifests[#manifests + 1] = {version = 1, name = name, dependencies = plugin.dependencies, scripts = plugin.scripts, assets = plugin.assets}
        enabled[#enabled + 1] = name
    end end
    return {manifests = manifests, enabled = enabled, assetScripts = self.assetScripts}
end
return Registry
