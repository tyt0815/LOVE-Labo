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
    end

    return true
end

function Project.new(rootPath)
    if type(rootPath) ~= "string" or rootPath == "" then
        return nil, "project root path must be a non-empty string"
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
