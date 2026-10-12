local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local Cache = {}
local function hash(bytes) return love.data.encode("string", "hex", love.data.hash("sha256", bytes)) end
function Cache.paths(project, reference)
    local id = project:getAssetId(project:getAssetReference(reference))
    if not id then return nil end
    local directory = Fs.join(project.rootPath, ".labo/Thumbnails")
    return Fs.join(directory, id .. ".png"), Fs.join(directory, id .. ".json"), directory
end
function Cache.save(project, reference, notify)
    local png, receipt, directory = Cache.paths(project, reference)
    if not png then return false, "Asset is not registered" end
    local dependencies = {}
    local snapshot = setmetatable({}, {__index = project})
    local function read(_, source)
        local canonical = assert(project:getAssetReference(source))
        local bytes = assert(Fs.read(assert(project:resolveAssetFile(canonical))))
        dependencies[project:getAssetId(canonical) or canonical] = hash(bytes)
        return bytes
    end
    snapshot.readAsset, snapshot.readSource, snapshot.draftAssets = read, read, {}
    snapshot.plugins = project.plugins:forProject(snapshot)
    local model
    local ok, result = pcall(function()
        model = require("editor.Preview").new(snapshot, {reference = reference})
        for _, object in ipairs(model.objects or {}) do for _, script in pairs(object.scripts) do
            local source = script.source
            local plugin = project.plugins.scripts[source]
            if plugin then source = plugin.id end
            if source and source ~= "Script" then read(snapshot, source) end
            local class = getmetatable(script)
            while class do
                local inheritedPlugin = project.plugins.scripts[class.scriptType]
                if inheritedPlugin and inheritedPlugin.id then read(snapshot, inheritedPlugin.id) end
                class = class.super
            end
        end end
        local root = Fs.join(project.rootPath, ".labo")
        if not Fs.info(root) then assert(Fs.mkdir(root)) end
        if not Fs.info(directory) then assert(Fs.mkdir(directory)) end
        local drawn, err = model:png(png, 256)
        assert(drawn, err)
        assert(Fs.writeAtomic(receipt, assert(Json.encode({version = 1, dependencies = dependencies}, true))))
    end)
    if model then model:release() end
    if notify ~= false then project.thumbnailRevision = (project.thumbnailRevision or 0) + 1 end
    if not ok then return false, tostring(result) end
    return true
end
function Cache.read(project, reference)
    local png, receipt = Cache.paths(project, reference)
    if not png then return nil end
    local bytes = Fs.read(receipt)
    local record = bytes and Json.decode(bytes)
    if not record or record.version ~= 1 then return nil end
    for source, expected in pairs(record.dependencies or {}) do
        local path = project:resolveAssetFile(source)
        local current = path and Fs.read(path)
        if not current or hash(current) ~= expected then return nil end
    end
    return Fs.read(png)
end
function Cache.ensure(project, reference)
    local canonical, referenceError = project:getAssetReference(reference)
    if not canonical or not canonical:lower():match("%.prefab$") then return nil, referenceError or "Thumbnail requires a Prefab", false end
    local bytes = Cache.read(project, reference)
    if bytes then return bytes, nil, false end
    -- 브라우저의 지연 생성은 다른 셀의 캐시를 초기화하지 않는다.
    local ok, err = Cache.save(project, reference, false)
    if not ok then return nil, err, false end
    bytes = Cache.read(project, reference)
    return bytes, not bytes and "Thumbnail cache could not be read" or nil, true
end
return Cache
