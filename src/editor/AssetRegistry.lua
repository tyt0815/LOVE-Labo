local Fs = require("editor.HostFileSystem")
local Json = require("editor.Json")
local Id = require("editor.AssetId")
local Registry = {}

function Registry.isInternal(name)
    name = name:lower()
    return name:match("%.meta$") or name:match("%.tmp$") or name:match("%.bak$") or name:find(".tmp-", 1, true)
end

local function headerKind(text)
    text = text:gsub("^\239\187\191", "")
    local line = text:match("^([^\r\n]*)") or ""
    local kind = line:match("^%s*%-%-%s*labo%-script:%s*([%w_-]+)%s*$")
    if kind == "lobject" or kind == "component" then return "script" end
    if kind == "level" or kind == "script" then return kind end
    if line:find("labo-script:", 1, true) then return nil, "Invalid script type marker" end
    return "script"
end

function Registry.metaText(scriptKind, id)
    id = id or Id.new()
    return assert(Json.encode({version = 1, id = id, scriptKind = scriptKind}, true)) .. "\n", id
end

function Registry.recoverMove(project)
    local journalPath = Fs.join(project.rootPath, "asset-move.json")
    local journalInfo, infoError = Fs.info(journalPath)
    if infoError then return false, infoError end
    if not journalInfo then return true end
    if journalInfo.isLink or journalInfo.type ~= "file" then return false, "Invalid asset move journal" end
    local bytes, readError = Fs.read(journalPath)
    if not bytes then return false, readError end
    local journal = Json.decode(bytes)
    if type(journal) ~= "table" or journal.version ~= 1 or not Id.isValid(journal.id)
        or type(journal.source) ~= "string" or type(journal.destination) ~= "string"
        or journal.source:lower() == journal.destination:lower() then return false, "Invalid asset move journal" end
    if journal.source:match("^[^/]+") ~= journal.destination:match("^[^/]+")
        or (journal.source:match("%.[^./]+$") or "") ~= (journal.destination:match("%.[^./]+$") or "")
        or Registry.isInternal(journal.source) or Registry.isInternal(journal.destination) then
        return false, "Invalid asset move journal paths"
    end
    local paths = {}
    for _, reference in ipairs({journal.source, journal.destination}) do
        if not reference:match("^Assets/") then return false, "Invalid move path" end
        local parent, parentInfo = project:checkedEntry(reference:match("^(.*)/[^/]+$"))
        if not parent or parentInfo.type ~= "directory" then return false, "Move parent is missing" end
        local path, err = project:resolvePath(reference)
        if not path then return false, err end
        paths[#paths + 1] = path
    end
    local function regular(path)
        local info, err = Fs.info(path)
        if err then return nil, err end
        if info and (info.isLink or info.type ~= "file") then return nil, "Move entry is not a regular file" end
        return info ~= nil
    end
    local source, target = paths[1], paths[2]
    local states = {}
    for _, path in ipairs({source, source .. ".meta", target, target .. ".meta"}) do
        local exists, err = regular(path)
        if exists == nil then return false, err end
        states[#states + 1] = exists
    end
    local metaPath = states[2] and source .. ".meta" or states[4] and target .. ".meta"
    local meta = metaPath and Json.decode(Fs.read(metaPath) or "")
    if type(meta) ~= "table" or meta.id ~= journal.id then return false, "Move metadata does not match its journal" end
    if states[1] and states[2] and not states[3] and not states[4] then
        -- 첫 rename 이전에 종료됐다면 원래 위치를 유지한다.
    elseif not states[1] and states[2] and states[3] and not states[4] then
        local moved, err = Fs.rename(source .. ".meta", target .. ".meta")
        if not moved then return false, err end
    elseif not states[1] and not states[2] and states[3] and states[4] then
        -- 원본과 메타가 이미 함께 이동됐다.
    else return false, "Ambiguous asset move; keep both files for recovery" end
    return Fs.removeFile(journalPath)
end

function Registry.rebuild(project)
    local Catalog = require("editor.AssetCatalog")
    local paths, ids, metadata, missing, untracked, cleanups = {}, {}, {}, {}, {}, {}
    for _, owner in ipairs(Catalog.owners(project)) do
        local data, err = Catalog.read(owner); if not data then return false, err end
        local legacy, legacyError = Catalog.importLegacy(owner, data); if not legacy then return false, legacyError end
        local found = {}
        local function visit(folder)
            local entries, listError = require("editor.AssetFolders").list(project, folder)
            if not entries then return false, listError end
            for _, entry in ipairs(entries) do
                if not entry.isLink and not entry.missing and not Registry.isInternal(entry.name) then
                    if entry.type == "directory" then
                        local ok, childError = visit(entry.reference); if not ok then return false, childError end
                    else
                        local path, pathError = project:checkedEntry(entry.reference); if not path then return false, pathError end
                        local localPath = owner.prefix == "" and entry.reference or "Assets" .. entry.reference:sub(#owner.prefix + 1)
                        found[localPath] = {path = path, reference = entry.reference}

                    end
                end
            end
            return true
        end
        local ok, scanError = visit(owner.prefix == "" and "Assets" or owner.prefix)
        if not ok then return false, scanError end
        local hasMissing = false
        for path in pairs(data.assets) do if not found[path] then hasMissing = true end end
        for path, file in pairs(found) do
            local bytes, readError = Fs.read(file.path)
            if not bytes then return false, readError or "Cannot read asset: " .. file.reference end
            local meta = data.assets[path]
            if not meta and not hasMissing then meta = {version = 1, id = Id.new()}; data.assets[path] = meta end
            if not meta then untracked[#untracked + 1] = {reference = file.reference, hash = Catalog.hash(bytes)}
            else
                if meta.scriptKind == "component" or meta.scriptKind == "lobject" then meta.scriptKind = "script" end
                if path:match("%.lua$") and not meta.scriptKind then
                    local kind, kindError = headerKind(bytes)
                    if not kind then return false, kindError end
                    meta.scriptKind = kind
                end
                if path:match("%.lua$") and meta.scriptKind ~= "level" and meta.scriptKind ~= "script" then return false, "Invalid script metadata" end
                meta.hash = Catalog.hash(bytes)
                if owner.plugin then
                    for name, source in pairs(owner.plugin.scripts) do
                        local public = require("project.PluginRegistry").publicMetadata(data.assets, name, source)
                        if public == meta then meta.scriptName = name end
                    end
                end
            end
        end
        for path, meta in pairs(data.assets) do
            local reference = Catalog.reference(owner, path)
            if paths[meta.id] then return false, "Duplicate asset ID: " .. reference end
            paths[meta.id], ids[reference], metadata[reference] = reference, meta.id, meta
            if not found[path] then missing[#missing + 1] = {reference = reference, id = meta.id, hash = meta.hash, readOnly = owner.readOnly} end
        end
        if owner.plugin then owner.plugin.assets = data.assets end
        if not owner.readOnly then
            local bytes = assert(Json.encode(data, true)) .. "\n"
            if Fs.read(owner.path) ~= bytes then
                local saved, saveError = Fs.writeAtomic(owner.path, bytes); if not saved then return false, saveError end
            end
            for _, path in ipairs(legacy) do cleanups[#cleanups + 1] = path end
            if owner.plugin and owner.plugin.scriptIds then
                local manifestPath = Fs.join(owner.root, "plugin.json")
                local manifest = assert(Json.decode(assert(Fs.read(manifestPath))))
                manifest.scriptIds = nil
                local saved, saveError = Fs.writeAtomic(manifestPath, assert(Json.encode(manifest, true)))
                if not saved then return false, saveError end
            end
        end
    end
    for _, path in ipairs(cleanups) do local ok, err = Fs.removeFile(path); if not ok then return false, err end end
    project.assetPaths, project.assetIds, project.assetMetadata = paths, ids, metadata
    project.missingAssets, project.untrackedAssets = missing, untracked
    project.assetRevision = (project.assetRevision or 0) + 1
    if project.plugins then
        project.plugins.loaded, project.plugins.moduleRequire = {}, nil
        for name, script in pairs(project.plugins.scripts) do
            if script.id and paths[script.id] then project.plugins.assetScripts[paths[script.id]] = name end
        end
    end
    project.assetIdsByLower = {}
    for reference, id in pairs(ids) do project.assetIdsByLower[reference:lower()] = id end
    project.assetIndexError = nil
    if Fs.info(Fs.join(project.rootPath, "asset-index.json")) then Fs.removeFile(Fs.join(project.rootPath, "asset-index.json")) end
    return true
end

function Registry.migrate(project, projectData)
    local function convert(reference)
        return project:getAssetId(reference) or reference
    end
    for _, reference in pairs(project.assetPaths) do
        if not project:isReadOnly(reference) and project:checkedEntry(reference) and (reference:match("%.level$") or reference:match("%.prefab$")) then
            local path = assert(project:resolvePath(reference))
            local text, readError = Fs.read(path)
            if not text then return false, readError end
            local data = Json.decode(text)
            if type(data) == "table" and (data.formatVersion == 1 or data.formatVersion == 2) then
                local changed = false
                local function change(target, key)
                    if type(target[key]) == "string" then
                        local id = convert(target[key])
                        if id ~= target[key] then target[key], changed = id, true end
                    end
                end
                if reference:match("%.level$") then
                    change(data, "scriptReference")
                    if type(data.lobjects) == "table" then
                        for _, object in ipairs(data.lobjects) do
                            if type(object) == "table" then change(object, "definitionReference") end
                        end
                    end
                else change(data, "definitionReference") end
                if changed then
                    data.formatVersion = 2
                    local wrote, err = Fs.writeAtomic(path, assert(Json.encode(data, true)) .. "\n")
                    if not wrote then return false, err end
                end
            end
        end
    end
    if projectData and type(projectData.defaultLevelReference) == "string" then
        local id = convert(projectData.defaultLevelReference)
        if id ~= projectData.defaultLevelReference then
            projectData.defaultLevelReference = id
            projectData.version = 2
            local wrote, err = Fs.writeAtomic(Fs.join(project.rootPath, "project.labo"), assert(Json.encode(projectData, true)) .. "\n")
            if not wrote then return false, err end
        end
        project.defaultLevelReference = id
    end
    return true
end

return Registry
