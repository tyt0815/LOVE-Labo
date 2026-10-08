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
Project.DEFAULT_LEVEL_REFERENCE = "Assets/Levels/Default.level"
Project.DEFAULT_SCRIPT_REFERENCE = "Sources/Levels/Default.lua"

local function filesystem()
    return require("editor.host_filesystem")
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
    local Json = require("editor.json")
    local text = assert(Json.encode({ version = 1, name = name,
        defaultLevelReference = Project.DEFAULT_LEVEL_REFERENCE }, true)) .. "\n"
    local level = require("editor.level").new()
    assert(level:setScriptReference(Project.DEFAULT_SCRIPT_REFERENCE))
    local levelText, encodeError = require("editor.level_file").encode(level)
    if not levelText then return nil, encodeError end
    local createdDirectories, createdFiles = {}, {}
    local function rollback(err)
        -- 이번 생성에서 성공한 파일·빈 폴더만 역순으로 정리한다.
        -- 다른 프로세스가 추가한 데이터는 재귀 삭제하지 않는다.
        for i = #createdFiles, 1, -1 do fs.removeFile(createdFiles[i]) end
        for i = #createdDirectories, 1, -1 do fs.removeDirectory(createdDirectories[i]) end
        return nil, err
    end
    for _, directory in ipairs({ root, fs.join(root, "Assets"), fs.join(root, "Assets/Levels"),
        fs.join(root, "Sources"), fs.join(root, "Sources/Levels") }) do
        local created, err = fs.mkdir(directory)
        if not created then return rollback(err) end
        createdDirectories[#createdDirectories + 1] = directory
    end
    for _, file in ipairs({
        { path = fs.join(root, Project.DEFAULT_SCRIPT_REFERENCE), text = require("editor.level_script_template") },
        { path = fs.join(root, Project.DEFAULT_LEVEL_REFERENCE), text = levelText },
        { path = fs.join(root, Project.FILE_NAME), text = text }
    }) do
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
    local data, decodeError = require("editor.json").decode(text)
    if type(data) ~= "table" or data.version ~= 1 then
        return nil, decodeError or "Unsupported project format"
    end
    local valid, nameError = Project.isValidName(data.name)
    if not valid then return nil, nameError end
    local assets, assetsError = fs.info(fs.join(project.rootPath, "Assets"))
    if not assets or assets.type ~= "directory" or assets.isLink then
        return nil, assetsError or "Project must contain a regular Assets folder"
    end
    local entries, listError = fs.list(fs.join(project.rootPath, "Assets"))
    if not entries then return nil, listError end
    local sources, sourcesError = fs.info(fs.join(project.rootPath, "Sources"))
    if sourcesError then return nil, sourcesError end
    if sources and (sources.type ~= "directory" or sources.isLink) then
        return nil, "Sources must be a regular folder"
    end
    if data.defaultLevelReference ~= nil then
        if type(data.defaultLevelReference) ~= "string" or not data.defaultLevelReference:match("^Assets/.+%.level$") then
            return nil, "defaultLevelReference must refer to an Assets/*.level file"
        end
        local validReference, referenceError = validateReference(data.defaultLevelReference)
        if not validReference then return nil, referenceError end
    end
    project.defaultLevelReference = data.defaultLevelReference
    project.name = data.name
    return project
end

function Project:listAssets(reference)
    reference = reference or "Assets"
    if reference ~= "Assets" and reference:sub(1, 7) ~= "Assets/" then
        return nil, "Asset folder must be inside Assets"
    end
    return self:listDirectory(reference)
end

function Project:listDirectory(reference)
    if type(reference) ~= "string" or (reference ~= "Assets" and reference:sub(1, 7) ~= "Assets/"
        and reference ~= "Sources" and reference:sub(1, 8) ~= "Sources/") then
        return nil, "Folder must be inside Assets or Sources"
    end
    local path, err = self:resolvePath(reference)
    if not path then return nil, err end
    local fs = filesystem()
    local current = self.rootPath
    -- 각 segment를 검사하여 junction/symlink를 통한 프로젝트 밖 탐색을 막는다.
    for segment in reference:gmatch("[^/]+") do
        current = fs.join(current, segment)
        local info, infoError = fs.info(current)
        if not info and not infoError and reference == "Sources" then return {} end
        if not info or info.type ~= "directory" or info.isLink then
            return nil, infoError or "Project folder is missing or is a filesystem link"
        end
    end
    local entries, listError = fs.list(path)
    if not entries then return nil, listError end
    for _, entry in ipairs(entries) do
        entry.reference = reference .. "/" .. entry.name
    end
    return entries
end

function Project:resolveAssetFile(reference)
    if type(reference) ~= "string" or reference:sub(1, 7) ~= "Assets/" then
        return nil, "Asset file must be inside Assets"
    end
    return self:resolveProjectFile(reference)
end

function Project:resolveSourceFile(reference)
    local valid, err = require("editor.level").isValidScriptReference(reference)
    if reference == nil or not valid then return nil, err or "Source reference is required" end
    return self:resolveProjectFile(reference)
end

function Project:resolveProjectFile(reference)
    if type(reference) ~= "string" or (reference:sub(1, 7) ~= "Assets/" and reference:sub(1, 8) ~= "Sources/") then
        return nil, "File must be inside Assets or Sources"
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
    local valid, err = validateReference(reference)

    if not valid then
        return nil, err
    end

    if self.rootPath:sub(-1) == "/" then
        return self.rootPath .. reference
    end

    return self.rootPath .. "/" .. reference
end

return Project
