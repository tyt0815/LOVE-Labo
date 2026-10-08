local FS = require("editor.host_filesystem")
local Json = require("editor.json")
local Id = require("editor.asset_id")
local Registry = {}

function Registry.isInternal(name)
    name = name:lower()
    return name:match("%.meta$") or name:match("%.tmp$") or name:match("%.bak$") or name:find(".tmp-", 1, true)
end

local function headerKind(text)
    text = text:gsub("^\239\187\191", "")
    local line = text:match("^([^\r\n]*)") or ""
    local kind = line:match("^%s*%-%-%s*labo%-script:%s*([%w_-]+)%s*$")
    if kind == "level" or kind == "lobject" or kind == "component" then return kind end
    if line:find("labo-script:", 1, true) then return nil, "Invalid script type marker" end
    return "level"
end

function Registry.metaText(scriptKind, id)
    id = id or Id.new()
    return assert(Json.encode({version = 1, id = id, scriptKind = scriptKind}, true)) .. "\n", id
end

function Registry.recoverMove(project)
    local journalPath = FS.join(project.rootPath, "asset-move.json")
    local journalInfo, infoError = FS.info(journalPath)
    if infoError then return false, infoError end
    if not journalInfo then return true end
    if journalInfo.isLink or journalInfo.type ~= "file" then return false, "Invalid asset move journal" end
    local bytes, readError = FS.read(journalPath)
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
        if not reference:match("^Assets/") and not reference:match("^Sources/") then return false, "Invalid move path" end
        local parent, parentInfo = project:checkedEntry(reference:match("^(.*)/[^/]+$"))
        if not parent or parentInfo.type ~= "directory" then return false, "Move parent is missing" end
        local path, err = project:resolvePath(reference)
        if not path then return false, err end
        paths[#paths + 1] = path
    end
    local function regular(path)
        local info, err = FS.info(path)
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
    local meta = metaPath and Json.decode(FS.read(metaPath) or "")
    if type(meta) ~= "table" or meta.id ~= journal.id then return false, "Move metadata does not match its journal" end
    if states[1] and states[2] and not states[3] and not states[4] then
        -- 첫 rename 이전에 종료됐다면 원래 위치를 유지한다.
    elseif not states[1] and states[2] and states[3] and not states[4] then
        local moved, err = FS.rename(source .. ".meta", target .. ".meta")
        if not moved then return false, err end
    elseif not states[1] and not states[2] and states[3] and states[4] then
        -- 원본과 메타가 이미 함께 이동됐다.
    else return false, "Ambiguous asset move; keep both files for recovery" end
    return FS.removeFile(journalPath)
end

function Registry.rebuild(project)
    local paths, ids, metadata, missing = {}, {}, {}, {}
    local function visit(folder)
        local entries, err = project:listDirectory(folder)
        if not entries then return false, err end
        for _, entry in ipairs(entries) do
            if not entry.isLink and not Registry.isInternal(entry.name) then
                if entry.type == "directory" then
                    local ok, childError = visit(entry.reference)
                    if not ok then return false, childError end
                else
                    local path, pathError = project:checkedEntry(entry.reference)
                    if not path then return false, pathError end
                    local metaPath = path .. ".meta"
                    local info, infoError = FS.info(metaPath)
                    if infoError then return false, infoError end
                    local meta
                    if info then
                        if info.isLink or info.type ~= "file" then return false, "Invalid metadata: " .. entry.reference end
                        local bytes, readError = FS.read(metaPath)
                        if not bytes then return false, readError end
                        meta = Json.decode(bytes)
                        if type(meta) ~= "table" or meta.version ~= 1 or not Id.isValid(meta.id) then
                            return false, "Invalid metadata: " .. entry.reference
                        end
                    else
                        meta = {version = 1, id = Id.new()}
                    end
                    if entry.reference:match("^Sources/.+%.lua$") then
                        if not info then
                            local text, readError = FS.read(path)
                            if not text then return false, readError end
                            local kind, kindError = headerKind(text)
                            if not kind then return false, kindError end
                            meta.scriptKind = kind
                        end
                        if meta.scriptKind ~= "level" and meta.scriptKind ~= "lobject" and meta.scriptKind ~= "component" then
                            return false, "Invalid script metadata: " .. entry.reference
                        end
                    end
                    if paths[meta.id] then return false, "Duplicate asset ID: " .. paths[meta.id] .. " / " .. entry.reference end
                    paths[meta.id], ids[entry.reference], metadata[entry.reference] = entry.reference, meta.id, meta
                    if not info then missing[#missing + 1] = {path = metaPath, meta = meta} end
                end
            end
        end
        return true
    end
    -- 기존 메타데이터 전체를 먼저 검증한다. 중복 ID를 임의로 새 ID로 바꾸지 않는다.
    for _, folder in ipairs({"Assets", "Sources"}) do
        local ok, err = visit(folder)
        if not ok then return false, err end
    end
    for _, entry in ipairs(missing) do
        local wrote, err = FS.createFile(entry.path, assert(Json.encode(entry.meta, true)) .. "\n")
        if not wrote then return false, err end
    end
    project.assetPaths, project.assetIds, project.assetMetadata = paths, ids, metadata
    project.assetIdsByLower = {}
    for reference, id in pairs(ids) do project.assetIdsByLower[reference:lower()] = id end
    local text = assert(Json.encode({version = 1, paths = paths}, true)) .. "\n"
    -- 캐시 쓰기 실패도 메모리에서 복원한 ID 목록의 사용을 막지는 않는다.
    local saved, cacheError = FS.writeAtomic(FS.join(project.rootPath, "asset-index.json"), text)
    project.assetIndexError = not saved and cacheError or nil
    return true
end

function Registry.migrate(project, projectData)
    local function convert(reference)
        return project:getAssetId(reference) or reference
    end
    for _, reference in pairs(project.assetPaths) do
        if reference:match("%.level$") or reference:match("%.prefab$") then
            local path = assert(project:resolvePath(reference))
            local text, readError = FS.read(path)
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
                    local wrote, err = FS.writeAtomic(path, assert(Json.encode(data, true)) .. "\n")
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
            local wrote, err = FS.writeAtomic(FS.join(project.rootPath, "project.labo"), assert(Json.encode(projectData, true)) .. "\n")
            if not wrote then return false, err end
        end
        project.defaultLevelReference = id
    end
    return true
end

return Registry
