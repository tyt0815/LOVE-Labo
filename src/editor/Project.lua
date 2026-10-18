local Project = {}
Project.__index = Project

local function normalizeRootPath(path)
    -- Editor host의 실제 filesystem path는 OS에서 들어올 수 있으므로
    -- 내부에서는 separator만 '/'로 통일한다.
    local normalized = path:gsub("\\", "/")

    -- 일반 directory의 마지막 slash는 제거하되
    -- Unix root('/')와 Windows drive root('C:/')는 보존한다.
    while #normalized > 1
        and normalized:sub(-1) == "/"
        and not normalized:match("^%a:/$")
    do
        normalized = normalized:sub(1, -2)
    end

    return normalized
end

local function isAbsoluteRootPath(path)
    return path:sub(1, 1) == "/"
        or path:match("^%a:/") ~= nil
end

local function validateReference(reference)
    if type(reference) ~= "string" or reference == "" then
        return false, "project reference must be a non-empty string"
    end

    -- serialized reference는 플랫폼 독립적으로 '/'만 사용한다.
    if reference:find("\\", 1, true) then
        return false, "project reference must use '/' separators"
    end

    if reference:find('[%z\1-\31:*?"<>|]') then
        return false, "project reference contains invalid path characters"
    end

    -- reference는 Project root 기준이어야 하며 실제 OS absolute path를
    -- authoring data 안에 저장하지 않는다.
    if reference:sub(1, 1) == "/"
        or reference:match("^%a:")
    then
        return false, "project reference must be relative"
    end

    -- 연속 slash나 마지막 slash는 empty segment를 만들므로 canonical하지 않다.
    if reference:find("//", 1, true)
        or reference:sub(-1) == "/"
    then
        return false, "project reference contains an empty path segment"
    end

    -- '.', '..' segment를 허용하지 않아 하나의 canonical 표현만 유지하고
    -- Project root 밖으로 탈출하는 경로도 차단한다.
    for segment in reference:gmatch("[^/]+") do
        if segment == "." or segment == ".." then
            return false, "project reference contains a non-canonical path segment"
        end
        if segment:match("[ .]$") then
            return false, "project reference contains a non-canonical path segment"
        end
    end

    return true
end

Project.FILE_NAME = "project.labo"

local function filesystem()
    return require("editor.HostFileSystem")
end

function Project.isValidName(name)
    if type(name) ~= "string" or name == "" or name:match("^%s")
        or name:match("[ .]$") or name:find('[%z\1-\31/\\:*?"<>|]') then
        return false, "Enter a valid project folder name"
    end
    local base = name:match("^[^.]+") or name
    base = base:upper()
    if base == "CON" or base == "PRN" or base == "AUX" or base == "NUL"
        or base:match("^COM[1-9]$") or base:match("^LPT[1-9]$") then
        return false, "This folder name is reserved by Windows"
    end
    return true
end

function Project.create(parentPath, name)
    local valid, nameError = Project.isValidName(name)
    if not valid then return nil, nameError end
    local parent, pathError = Project.new(parentPath)
    if not parent then return nil, pathError end
    local fs = filesystem()
    local info, infoError = fs.info(parent.rootPath)
    if not info or info.type ~= "directory" then
        return nil, infoError or "Parent folder does not exist"
    end
    local root = fs.join(parent.rootPath, name)
    local existing, existingError = fs.info(root)
    if existing then return nil, "Project folder already exists" end
    if existingError then return nil, existingError end
    local Json = require("editor.Json")
    local text = assert(Json.encode({ version = 2, name = name, id = require("project.AssetId").new() }, true)) .. "\n"
    local createdDirectories, createdFiles = {}, {}
    local function rollback(err)
        -- 이번 생성에서 성공한 파일·빈 폴더만 역순으로 정리한다.
        -- 다른 프로세스가 추가한 데이터는 재귀 삭제하지 않는다.
        for i = #createdFiles, 1, -1 do fs.removeFile(createdFiles[i]) end
        for i = #createdDirectories, 1, -1 do fs.removeDirectory(createdDirectories[i]) end
        return nil, err
    end
    for _, directory in ipairs({ root, fs.join(root, "Assets"), fs.join(root, "Docs"), fs.join(root, "Tools") }) do
        local created, err = fs.mkdir(directory)
        if not created then return rollback(err) end
        createdDirectories[#createdDirectories + 1] = directory
    end
    local files = {{path = fs.join(root, "conf.lua"), text = require("editor.GameConfig").template(name)},
        {path = fs.join(root, "Tools/Build.lua"), text = require("editor.BuildTemplate").text},
        {path = fs.join(root, Project.FILE_NAME), text = text},
        {path = fs.join(root, "plugins.json"), text = assert(Json.encode({version = 1, enabled = Json.array({})}, true))}}
    for _, file in ipairs(require("editor.ProjectInstructions").files()) do
        files[#files + 1] = {path = fs.join(root, file.name), text = file.text}
    end
    for _, file in ipairs(files) do
        local created, err = fs.createFile(file.path, file.text)
        if not created then return rollback(err) end
        createdFiles[#createdFiles + 1] = file.path
    end
    return Project.open(root)
end

function Project.open(rootPath)
    local project, err = Project.new(rootPath)
    if not project then return nil, err end
    local fs = filesystem()
    local info, infoError = fs.info(project.rootPath)
    if not info or info.type ~= "directory" then return nil, infoError or "Project folder does not exist" end
    local text, readError = fs.read(fs.join(project.rootPath, Project.FILE_NAME))
    if not text then return nil, "Cannot open " .. Project.FILE_NAME .. ": " .. tostring(readError) end
    local data, decodeError = require("editor.Json").decode(text)
    if type(data) ~= "table" or (data.version ~= 1 and data.version ~= 2) then
        return nil, decodeError or "Unsupported project format"
    end
    local valid, nameError = Project.isValidName(data.name)
    if not valid then return nil, nameError end
    if data.id ~= nil and not require("project.AssetId").isValid(data.id) then return nil, "Invalid project ID" end
    -- 필수 폴더의 누락만 복구한다. 파일·링크와 권한 오류는 덮어쓰지 않는다.
    local missingFolders = {}
    for _, name in ipairs({"Assets"}) do
        local path = fs.join(project.rootPath, name)
        local info, infoError = fs.info(path)
        if infoError then return nil, infoError end
        if info and (info.type ~= "directory" or info.isLink) then return nil, name .. " must be a regular folder" end
        if not info then missingFolders[#missingFolders + 1] = path end
    end
    if data.defaultLevelReference ~= nil then
        if type(data.defaultLevelReference) ~= "string" or (not require("editor.AssetId").isValid(data.defaultLevelReference)
            and not data.defaultLevelReference:match("^Assets/.+%.level$")) then
            return nil, "defaultLevelReference must refer to an Assets/*.level file"
        end
        if not require("editor.AssetId").isValid(data.defaultLevelReference) then
            local validReference, referenceError = validateReference(data.defaultLevelReference)
            if not validReference then return nil, referenceError end
        end
    end
    for _, path in ipairs(missingFolders) do
        local made, makeError = fs.mkdir(path)
        if not made then return nil, makeError end
    end
    local layoutReady, layoutError = require("editor.ProjectLayout").migrateSources(project.rootPath)
    if not layoutReady then return nil, layoutError end
    project.defaultLevelReference = data.defaultLevelReference
    project.name = data.name
    local scoped, scopeError = require("project.ScopedScripts").validate(data)
    if not scoped then return nil, scopeError end
    project.scripts, project.scriptOverrides = scoped.scripts, scoped.scriptOverrides
    local pluginsOk, plugins = pcall(require("project.PluginRegistry").new, project)
    if not pluginsOk then return nil, tostring(plugins) end
    project.plugins = plugins
    local recovered, recoverError = require("editor.AssetRegistry").recoverMove(project)
    if not recovered then return nil, recoverError end
    local rebuilt, rebuildError = project:rebuildAssetIndex()
    if not rebuilt then return nil, rebuildError end
    local migrated, migrateError = require("editor.AssetRegistry").migrate(project, data)
    if not migrated then return nil, migrateError end
    -- 레거시 프로젝트는 한 번만 ID를 발급한다. 앞선 마이그레이션 결과를 다시 읽어 보존한다.
    if not data.id then
        local path = fs.join(project.rootPath, Project.FILE_NAME)
        local current = assert(require("project.Json").decode(assert(fs.read(path))))
        current.id = current.id or require("project.AssetId").new()
        local saved, saveError = fs.writeAtomic(path, assert(require("project.Json").encode(current, true)) .. "\n")
        if not saved then return nil, saveError end
        data.id = current.id
    end
    project.id, project.saveIdentity = data.id, "labo-" .. data.id
    return project
end

function Project:resetSaveIdentity()
    local fs, Json = filesystem(), require("project.Json")
    local path = fs.join(self.rootPath, Project.FILE_NAME)
    local data = assert(Json.decode(assert(fs.read(path))))
    local id = require("project.AssetId").new()
    data.id = id
    local ok, err = fs.writeAtomic(path, assert(Json.encode(data, true)) .. "\n")
    if not ok then return false, err end
    self.id, self.saveIdentity = id, "labo-" .. id
    return true
end

function Project:saveScripts()
    local fs, Json = filesystem(), require("project.Json")
    local path = fs.join(self.rootPath, Project.FILE_NAME)
    local bytes, readError = fs.read(path)
    if not bytes then return false, readError end
    local data, err = Json.decode(bytes)
    if not data then return false, err end
    local scoped, scopeError = require("project.ScopedScripts").validate(self)
    if not scoped then return false, scopeError end
    data.scripts, data.scriptOverrides = Json.array(scoped.scripts), scoped.scriptOverrides
    return fs.writeAtomic(path, assert(Json.encode(data, true)) .. "\n")
end

function Project:rebuildAssetIndex(skipRecovery, skipMigration)
    if self.plugins then self.pluginAssets = require("editor.PluginAssets").new(self) end
    if not skipRecovery then
        local recovered, err = require("editor.AssetRegistry").recoverMove(self)
        if not recovered then return false, err end
    end
    local Registry = require("editor.AssetRegistry")
    local rebuilt, err = Registry.rebuild(self)
    if not rebuilt then return false, err end
    if skipMigration then return true end
    return Registry.migrate(self)
end

function Project:getAssetId(reference)
    if type(reference) ~= "string" then return nil end
    reference = reference:gsub("^Sources/", "Assets/Scripts/")
    return self.assetIds and self.assetIds[reference]
        or self.assetIdsByLower and self.assetIdsByLower[reference:lower()]
end

function Project:readSource(reference)
    local path, err = self:resolveSourceFile(reference)
    if not path then return nil, err end
    return filesystem().read(path)
end

function Project:readAsset(reference)
    local path, err = self:resolveAssetFile(reference)
    if not path then return nil, err end
    local id = self:getAssetId(self:getAssetReference(reference))
    local draft = self.draftAssets and self.draftAssets[id]
    if draft and draft:isDirty() then return require("editor.Prefab").encodeData(draft.data) end
    local levelDraft = self.draftLevelAssets and self.draftLevelAssets[id]
    if levelDraft and levelDraft:isDirty() then return require("editor.LevelFile").encode(levelDraft.level) end
    return filesystem().read(path)
end

function Project:getAssetReference(reference)
    if require("editor.AssetId").isValid(reference) then
        local path = self.assetPaths and self.assetPaths[reference]
        if not path then return nil, "Asset ID is missing: " .. reference end
        return path
    end
    reference = type(reference) == "string" and reference:gsub("^Sources/", "Assets/Scripts/") or reference
    return require("project.PluginCompatibility").reference(reference)
end

function Project:referenceForPath(path)
    if type(path) ~= "string" then return nil end
    local normalized = path:gsub("\\", "/")
    if self.pluginAssets then for prefix, mount in pairs(self.pluginAssets.mounts) do
        if normalized:lower():sub(1, #mount.path + 1) == mount.path:lower() .. "/" then return prefix .. normalized:sub(#mount.path + 1) end
    end end
    local prefix = self.rootPath:gsub("/+$", "") .. "/"
    if normalized:lower():sub(1, #prefix) ~= prefix:lower() then return nil end
    local reference = normalized:sub(#prefix + 1)
    if reference:match("^Assets/") then return reference end
end

function Project:listAssets(reference)
    reference = reference or "Assets"
    if reference ~= "Assets" and reference:sub(1, 7) ~= "Assets/" then
        return nil, "Asset folder must be inside Assets"
    end
    return self:listDirectory(reference)
end

function Project:listDirectory(reference)
    if type(reference) ~= "string" or (reference ~= "Assets" and reference:sub(1, 7) ~= "Assets/") then
        return nil, "Folder must be inside Assets"
    end
    local valid, validationError = validateReference(reference)
    if not valid then return nil, validationError end
    if self.pluginAssets and (self.pluginAssets.groups[reference] or self.pluginAssets:mount(reference)) then
        return self.pluginAssets:list(reference)
    end
    local path, err = self:resolvePath(reference)
    if not path then return nil, err end
    local fs = filesystem()
    local current = self.rootPath
    -- 각 segment를 검사하여 junction/symlink를 통한 프로젝트 밖 탐색을 막는다.
    for segment in reference:gmatch("[^/]+") do
        current = fs.join(current, segment)
        local info, infoError = fs.info(current)
        if not info and not infoError and reference == "Assets" then return {} end
        if not info or info.type ~= "directory" or info.isLink then
            return nil, infoError or "Project folder is missing or is a filesystem link"
        end
    end
    local entries, listError = fs.list(path)
    if not entries then return nil, listError end
    local visible = {}
    for _, entry in ipairs(entries) do
        if not require("editor.AssetRegistry").isInternal(entry.name) then
            entry.reference = reference .. "/" .. entry.name
            visible[#visible + 1] = entry
        end
    end
    if reference == "Assets" and self.pluginAssets then
        for _, entry in ipairs(self.pluginAssets:list(reference)) do
            for _, physical in ipairs(visible) do if physical.name == entry.name then return nil, "Reserved plugin mount folder: " .. entry.name end end
            visible[#visible + 1] = entry
        end
    end
    return visible
end

function Project:resolveAssetFile(reference)
    reference = self:getAssetReference(reference)
    if type(reference) ~= "string" or reference:sub(1, 7) ~= "Assets/" then
        return nil, "Asset file must be inside Assets"
    end
    return self:resolveProjectFile(reference)
end

function Project:resolveSourceFile(reference)
    reference = self:getAssetReference(reference)
    local valid, err = require("editor.Level").isValidScriptReference(reference)
    if reference == nil or not valid then return nil, err or "Source reference is required" end
    return self:resolveProjectFile(reference)
end

function Project:resolveProjectFile(reference)
    if type(reference) ~= "string" or (reference:sub(1, 7) ~= "Assets/") then
        return nil, "File must be inside Assets"
    end
    local valid, validationError = validateReference(reference)
    if not valid then return nil, validationError end
    if self.pluginAssets and self.pluginAssets:mount(reference) then
        local path, info = self.pluginAssets:info(reference)
        if not path then return nil, info end
        if info.type ~= "file" then return nil, "Expected a plugin asset file" end
        return path
    end
    local path, err = self:resolvePath(reference)
    if not path then return nil, err end
    local fs, current = filesystem(), self.rootPath
    for segment in reference:gmatch("[^/]+") do
        current = fs.join(current, segment)
        local info, infoError = fs.info(current)
        if not info or info.isLink then return nil, infoError or "Asset is missing or is a filesystem link" end
        if current ~= path and info.type ~= "directory" then return nil, "Asset parent is not a folder" end
        if current == path and info.type ~= "file" then return nil, "Asset is not a file" end
    end
    return path
end

-- 쓰기 작업도 탐색과 동일하게 루트 경계와 모든 부모의 링크 여부를 검사한다.
function Project:checkedEntry(reference)
    if type(reference) ~= "string" or (reference ~= "Assets" and reference:sub(1, 7) ~= "Assets/") then
        return nil, "Entry must be inside Assets"
    end
    local valid, validationError = validateReference(reference)
    if not valid then return nil, validationError end
    if self.pluginAssets and (self.pluginAssets.groups[reference] or self.pluginAssets:mount(reference)) then return self.pluginAssets:info(reference) end
    local path, err = self:resolvePath(reference)
    if not path then return nil, err end
    local fs, current, last = filesystem(), self.rootPath, nil
    for segment in reference:gmatch("[^/]+") do
        current = fs.join(current, segment)
        local info, infoError = fs.info(current)
        if not info or info.isLink then return nil, infoError or "Entry is missing or is a filesystem link" end
        if current ~= path and info.type ~= "directory" then return nil, "Parent is not a folder" end
        last = info
    end
    return path, last
end

function Project:getScriptKind(reference)
    reference = self:getAssetReference(reference)
    local id = self:getAssetId(reference)
    if id then reference = self.assetPaths[id] end
    local meta = self.assetMetadata and self.assetMetadata[reference]
    if meta and meta.scriptKind then
        local path, err = self:resolveSourceFile(reference)
        if not path then return nil, err end
        return meta.scriptKind
    end
    local path, err = self:resolveSourceFile(reference)
    if not path then return nil, err end
    local text, readError = filesystem().read(path)
    if not text then return nil, readError end
    text = text:gsub("^\239\187\191", "")
    local firstLine = text:match("^([^\r\n]*)") or ""
    local kind = firstLine:match("^%s*%-%-%s*labo%-script:%s*([%w_-]+)%s*$")
    if kind == "level" or kind == "script" then return kind end
    if firstLine:find("labo-script:", 1, true) then return nil, "Invalid script type marker" end
    -- 종류 표식 도입 전에 작성한 프로젝트 코드는 기존 Level 동작을 유지한다.
    return "script"
end

function Project:listScripts(kind)
    if kind ~= "level" and kind ~= "script" then return nil, "Unknown script type" end
    local scripts = {}
    local function visit(folder)
        local entries, err = self:listDirectory(folder)
        if not entries then return false, err end
        for _, entry in ipairs(entries) do
            if not entry.isLink then
                if entry.type == "directory" then
                    local ok, childError = visit(entry.reference)
                    if not ok then return false, childError end
                elseif entry.name:match("%.lua$") then
                    local scriptKind, kindError = self:getScriptKind(entry.reference)
                    if not scriptKind then return false, entry.reference .. ": " .. tostring(kindError) end
                    if scriptKind == kind then scripts[#scripts + 1] = entry.reference end
                end
            end
        end
        return true
    end
    local ok, err = visit("Assets")
    if not ok then return nil, err end
    table.sort(scripts)
    return scripts
end

function Project:createEntry(folder, kind, name, options)
    options = options or {}
    if self:isReadOnly(folder) then return false, "Labo plugins and plugin mount folders are read-only" end
    local valid, err = Project.isValidName(name)
    if not valid then return false, err end
    if kind == "lua" then name = require("editor.ClassName").fromModule(name, "LuaScript") end
    if require("editor.AssetRegistry").isInternal(name:lower()) then return false, "Metadata and temporary names are reserved" end
    if kind ~= "folder" and kind ~= "level" and kind ~= "prefab" and kind ~= "lua" then return false, "Unknown entry type" end
    if (kind == "level" or kind == "prefab") and not folder:match("^Assets/?") then return false, "Level and Prefab assets belong in Assets" end
    if kind == "lua" and not folder:match("^Assets/?") then return false, "Lua scripts belong in Assets" end
    local entries, listError = self:listDirectory(folder)
    if not entries then return false, listError end
    if kind == "lua" and options.scriptKind ~= "level" and options.scriptKind ~= "script" then
        return false, "Choose a Level, LObject or Script parent"
    end
    if (kind == "level" or kind == "prefab") and options.scriptReference ~= nil then
        local rebuilt, rebuildError = self:rebuildAssetIndex()
        if not rebuilt then return false, rebuildError end
        if kind == "prefab" then
            local definition, parentError = require("project.ObjectDefinition").resolve(self, options.scriptReference)
            if not definition then return false, parentError end
        else
            local actual, scriptError = self:getScriptKind(options.scriptReference)
            if not actual then return false, scriptError end
            if actual ~= "level" then return false, "Choose a level script" end
        end
    end
    local parentId
    if kind == "lua" and options.parentReference then
        local parent, err = require("project.LuaScript").load(self, options.parentReference, options.scriptKind)
        if not parent then return false, err end
        if options.parentReference ~= "Script" then
            local pluginSource = self.plugins and self.plugins.scripts[options.parentReference]
            parentId = pluginSource and pluginSource.id or self:getAssetId(self:getAssetReference(options.parentReference))
            if not require("project.AssetId").isValid(parentId) then return false, "Parent script has no asset ID" end
        end
    end
    local fs, createdDirectories, createdFiles, createdReferences = filesystem(), {}, {}, {}
    local function rollback(errorText)
        for _, reference in ipairs(createdReferences) do require("editor.AssetCatalog").remove(self, reference) end
        for i = #createdFiles, 1, -1 do fs.removeFile(createdFiles[i]) end
        for i = #createdDirectories, 1, -1 do fs.removeDirectory(createdDirectories[i]) end
        return false, errorText
    end
    local function ensureFolder(reference)
        local current = ""
        for segment in reference:gmatch("[^/]+") do
            current = current == "" and segment or current .. "/" .. segment
            if not (self.pluginAssets and self.pluginAssets.groups[current]) then
                local path, pathError = self:resolvePath(current)
                if not path then return false, pathError end
                local info, infoError = fs.info(path)
                if infoError then return false, infoError end
                if info then
                    if info.type ~= "directory" or info.isLink then return false, "Parent is not a regular folder" end
                else
                    local ok, createError = fs.mkdir(path)
                    if not ok then return false, createError end
                    createdDirectories[#createdDirectories + 1] = path
                end
            end
        end
        return true
    end
    local function writeNew(reference, text, scriptKind)
        local parent = reference:match("^(.*)/[^/]+$")
        local ok, parentError = ensureFolder(parent)
        if not ok then return false, parentError end
        local path, pathError = self:resolvePath(reference)
        if not path then return false, pathError end
        local wrote, writeError = fs.createFile(path, text)
        if not wrote then return false, writeError end
        createdFiles[#createdFiles + 1] = path
        local id = require("project.AssetId").new()
        local saved, metaError = require("editor.AssetCatalog").update(self, {[reference] = {version = 1, id = id,
            scriptKind = scriptKind or kind == "lua" and options.scriptKind or nil}})
        if saved then createdReferences[#createdReferences + 1] = reference end
        return saved, metaError, id
    end
    local suffix = kind == "level" and ".level" or kind == "prefab" and ".prefab" or kind == "lua" and ".lua" or ""
    if suffix ~= "" then
        if name:sub(-#suffix):lower() == suffix then name = name:sub(1, -#suffix - 1) end
        if name == "" then return false, "Enter a file name" end
        name = name .. suffix
    end
    local reference = folder .. "/" .. name
    local available, registrationError = require("editor.AssetCatalog").checkDestination(self, reference)
    if not available then return false, registrationError end
    local ok, createError
    if kind == "folder" then
        ok, createError = ensureFolder(folder)
        if ok then
            local directory = assert(self:resolvePath(reference))
            ok, createError = fs.mkdir(directory)
            if ok then createdDirectories[#createdDirectories + 1] = directory end
        end
    elseif kind == "lua" then
        ok, createError = writeNew(reference, require(options.scriptKind == "level"
            and "editor.LevelScriptTemplate" or "editor.ScriptTemplate")(name, parentId))
    elseif kind == "level" then
        if fs.info(assert(self:resolvePath(reference))) then return false, "Level file already exists" end
        local level = options.level or require("editor.Level").new()
        assert(level:setScriptReference(self:getAssetId(options.scriptReference) or options.scriptReference))
        local text, encodeError = require("editor.LevelFile").encode(level)
        if not text then return rollback(encodeError) end
        ok, createError = writeNew(reference, text)
    else
        local text, encodeError
        if options.prefabData then text, encodeError = require("editor.Prefab").encodeData(options.prefabData)
        else text, encodeError = require("editor.Prefab").encode(self:getAssetId(options.scriptReference) or options.scriptReference) end
        if not text then return rollback(encodeError) end
        ok, createError = writeNew(reference, text)
    end
    if not ok then return rollback(createError) end
    local rebuilt, rebuildError = self:rebuildAssetIndex(false, true)
    if not rebuilt then return rollback(rebuildError) end
    return true, reference, createdReferences
end

function Project:deletionEntries(reference)
    if self:isReadOnly(reference) then return false, "Plugin entry is read-only" end
    if self.pluginAssets and self.pluginAssets.mounts[reference] then return false, "Plugin root cannot be deleted; disable it in Plugins" end
    if type(reference) == "string" and require("editor.AssetRegistry").isInternal(reference) then
        return false, "Metadata cannot be deleted separately"
    end
    local path, info = self:checkedEntry(reference)
    if not path then
        local missing
        for _, entry in ipairs(self.missingAssets or {}) do if entry.reference == reference then missing = entry end end
        if not missing then return false, info end
        local resolved, resolveError = self:resolvePath(reference)
        if not resolved then return false, resolveError end
        local actual, actualError = filesystem().info(resolved)
        if actual or actualError then return false, actualError or "Entry changed during deletion" end
        local usages, usageError = require("editor.AssetRepair").usage(self, missing.id)
        if not usages then return false, usageError end
        if #usages > 0 then return false, "Asset is referenced by: " .. table.concat(usages, ", ") end
        return {}
    end
    if reference == "Assets" then return false, "Project roots cannot be deleted" end
    local default = self:getAssetReference(self.defaultLevelReference)
    -- 현재 호스트는 Windows이므로 대소문자만 다른 참조도 같은 파일로 보호한다.
    local compared = reference:lower()
    default = default and default:lower()
    if default and (default == compared or default:sub(1, #compared + 1) == compared .. "/") then
        return false, "This entry contains the project's default level"
    end
    local fs, removals, visited = filesystem(), {}, {}
    local function collect(current)
        if visited[current] then return true end
        visited[current] = true
        local path, info = self:checkedEntry(current)
        if not path then return false, info end
        if info.type == "directory" then
            local children, err = fs.list(path)
            if not children then return false, err end
            for _, child in ipairs(children) do
                local ok, childError = collect(current .. "/" .. child.name)
                if not ok then return false, childError end
            end
        end
        removals[#removals + 1] = { reference = current, type = info.type }
        if info.type == "file" then
            local meta = fs.info(path .. ".meta")
            if meta then
                if meta.isLink or meta.type ~= "file" then return false, "Invalid metadata" end
                local ok, metaError = collect(current .. ".meta")
                if not ok then return false, metaError end
            end
        end
        return true
    end
    -- 먼저 전체를 검사해 링크가 섞인 폴더를 일부만 삭제하지 않는다.
    local ok, err = collect(reference)
    if not ok then return false, err end
    return removals
end

function Project:deleteEntry(reference)
    local removals, err = self:deletionEntries(reference)
    if not removals then return false, err end
    local catalog = require("editor.AssetCatalog")
    local metadata = catalog.capture(self, reference)
    local removed, removeError = catalog.remove(self, reference)
    if not removed then return false, removeError end
    local fs = filesystem()
    for _, entry in ipairs(removals) do
        local path, info = self:checkedEntry(entry.reference)
        if not path then catalog.update(self, metadata); return false, info end
        if info.type ~= entry.type then catalog.update(self, metadata); return false, "Entry changed during deletion" end
        local removed, removeError
        if info.type == "directory" then removed, removeError = fs.removeDirectory(path)
        else removed, removeError = fs.removeFile(path) end
        if not removed then catalog.update(self, metadata); return false, removeError end
    end
    return self:rebuildAssetIndex()
end

function Project:moveEntry(source, destination)
    if self:isReadOnly(source) or self:isReadOnly(destination) then return false, "Plugin entry is read-only" end
    if self.pluginAssets and self.pluginAssets.mounts[source] then return false, "Plugin root cannot be moved" end
    if source == "Assets" then return false, "Project roots cannot be moved" end
    if type(destination) ~= "string" then return false, "Enter a destination path" end
    if source:match("^[^/]+") ~= destination:match("^[^/]+") then return false, "Keep the entry in its Assets root" end
    local rebuilt, rebuildError = self:rebuildAssetIndex()
    if not rebuilt then return false, rebuildError end
    local path, info = self:checkedEntry(source)
    if not path then return false, info end
    if require("editor.AssetRegistry").isInternal(source:lower())
        or require("editor.AssetRegistry").isInternal(destination:lower()) then return false, "Metadata cannot be moved separately" end
    local target, targetError = self:resolvePath(destination)
    if not target then return false, targetError end
    local parent = destination:match("^(.*)/[^/]+$")
    local parentPath, parentInfo = self:checkedEntry(parent)
    if not parentPath or parentInfo.type ~= "directory" then return false, "Destination parent must be an existing regular folder" end
    if destination:lower() == source:lower() or destination:lower():sub(1, #source + 1) == source:lower() .. "/" then
        return false, "Choose a different location outside this folder"
    end
    if info.type == "file" and (source:match("%.[^./]+$") or "") ~= (destination:match("%.[^./]+$") or "") then
        return false, "Keep the original file extension"
    end
    local fs = filesystem()
    local available, registrationError = require("editor.AssetCatalog").checkDestination(self, destination)
    if not available then return false, registrationError end
    for _, candidate in ipairs({target, target .. ".meta"}) do
        local existing, existingError = fs.info(candidate)
        if existing or existingError then return false, existingError or "Destination already exists" end
    end
    local moved, moveError = fs.rename(path, target)
    if not moved then return false, moveError end
    local catalog = require("editor.AssetCatalog")
    local old = catalog.capture(self, source)
    local indexed, indexError = catalog.move(self, source, destination)
    if indexed then indexed, indexError = self:rebuildAssetIndex(true, true) end
    if not indexed then
        fs.rename(target, path)
        local restore = {}
        for ref, meta in pairs(old) do restore[ref] = meta; restore[destination .. ref:sub(#source + 1)] = false end
        catalog.update(self, restore); self:rebuildAssetIndex()
        return false, indexError
    end
    return true
end

function Project.new(rootPath)
    if type(rootPath) ~= "string" or rootPath == "" then
        return nil, "project root path must be a non-empty string"
    end

    if rootPath:find("\0", 1, true) then
        return nil, "project root path contains a null character"
    end

    local normalized = normalizeRootPath(rootPath)

    if not isAbsoluteRootPath(normalized) then
        return nil, "project root path must be absolute"
    end

    local self = setmetatable({}, Project)
    self.rootPath = normalized

    return self
end

function Project:isValidReference(reference)
    return validateReference(reference)
end

function Project:resolvePath(reference)
    local resolved, idError = self:getAssetReference(reference)
    if not resolved then return nil, idError end
    reference = resolved
    local valid, err = validateReference(reference)

    if not valid then
        return nil, err
    end
    if self.pluginAssets then
        local mounted = self.pluginAssets:path(reference)
        if mounted then return mounted end
    end

    if self.rootPath:sub(-1) == "/" then
        return self.rootPath .. reference
    end

    return self.rootPath .. "/" .. reference
end

function Project:isReadOnly(reference)
    reference = self:getAssetReference(reference)
    if type(reference) ~= "string" then return false end
    if self.pluginAssets then
        return self.pluginAssets:readOnly(reference)
    end
    return false
end

return Project
