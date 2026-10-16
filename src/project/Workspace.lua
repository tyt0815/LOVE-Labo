local Fs = require("project.NativeFileSystem")
local Workspace = {}
Workspace.__index = Workspace

function Workspace.absolute(path)
    assert(type(path) == "string" and path ~= "", "Specify a path")
    path = path:gsub("\\", "/")
    if not path:match("^%a:/$") then path = path:gsub("/+$", "") end
    assert(path:match("^%a:/"), "Expected an absolute Windows path")
    assert(not path:sub(4):find('[%z\1-\31:*?"<>|]'), "Invalid path")
    for part in path:sub(4):gmatch("[^/]+") do
        local base = (part:match("^[^.]+") or part):upper()
        assert(part ~= "." and part ~= ".." and not part:match("[ .]$")
            and base ~= "CON" and base ~= "PRN" and base ~= "AUX" and base ~= "NUL"
            and not base:match("^COM[1-9]$") and not base:match("^LPT[1-9]$"), "Invalid path segment")
    end
    assert(not path:sub(4):find("//", 1, true), "Invalid path separator")
    return path:match("^%a:$") and path .. "/" or path
end

-- 모든 부모를 확인하므로 junction을 통해 작업 폴더 밖으로 쓰지 않는다.
function Workspace.ensureDirectory(path)
    path = Workspace.absolute(path)
    local current = path:sub(1, 3)
    for part in path:sub(4):gmatch("[^/]+") do
        current = Fs.join(current, part)
        local info, err = Fs.info(current)
        assert(not err, err)
        if not info then assert(Fs.mkdir(current))
        else assert(info.type == "directory" and not info.isLink, "Expected a regular folder: " .. current) end
    end
    return path
end

function Workspace.new(root)
    root = Workspace.absolute(root)
    local info = assert(Fs.info(root), "Workspace folder does not exist")
    assert(info.type == "directory" and not info.isLink, "Expected a regular workspace folder")
    -- 존재하는 부모도 같은 규칙으로 확인한다.
    Workspace.ensureDirectory(root)
    return setmetatable({root = root}, Workspace)
end

function Workspace:path(reference)
    assert(type(reference) == "string" and reference ~= "" and not reference:find("\\", 1, true)
        and reference:sub(1, 1) ~= "/" and not reference:find(":", 1, true)
        and reference:sub(-1) ~= "/", "Expected a relative workspace path")
    local path = Workspace.absolute(Fs.join(self.root, reference))
    local current = self.root
    for part in reference:gmatch("[^/]+") do
        current = Fs.join(current, part)
        local info, err = Fs.info(current)
        assert(not err, err)
        assert(not info or not info.isLink and (current == path or info.type == "directory"), "Invalid workspace entry")
    end
    return path
end

function Workspace.revision(bytes)
    return love.data.encode("string", "hex", love.data.hash("sha256", bytes))
end

function Workspace:read(reference)
    local bytes = assert(Fs.read(self:path(reference)))
    return bytes, Workspace.revision(bytes)
end

-- expected=false는 새 파일 전용, 문자열은 읽었던 revision과의 일치를 요구한다.
function Workspace:write(reference, bytes, expected)
    assert(type(bytes) == "string", "Expected file bytes")
    local path = self:path(reference)
    local info = Fs.info(path)
    if expected ~= nil then
        local previous = info and assert(Fs.read(path))
        assert(expected == false and not info or type(expected) == "string" and previous
            and Workspace.revision(previous) == expected, "Revision conflict: " .. reference)
    end
    Workspace.ensureDirectory(Fs.parent(path))
    assert(Fs.writeAtomic(path, bytes))
    return Workspace.revision(bytes)
end

function Workspace:readJson(reference)
    local bytes, revision = self:read(reference)
    local data, err = require("project.Json").decode(bytes)
    assert(data ~= nil, err)
    return data, revision
end

function Workspace:writeJson(reference, data, expected)
    return self:write(reference, assert(require("project.Json").encode(data, true)) .. "\n", expected)
end

function Workspace:withLock(fn)
    local path = self:path(".labo-content.lock")
    local acquired, err = Fs.createFile(path, "Content operation in progress\n")
    assert(acquired, "Workspace is busy or inaccessible: " .. tostring(err))
    local ok, result = pcall(fn)
    local removed, removeError = Fs.removeFile(path)
    assert(removed, removeError)
    assert(ok, result)
    return result
end
return Workspace
