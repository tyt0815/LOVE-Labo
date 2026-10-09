local ffi = require("ffi")
local bit = require("bit")

local FileSystem = {}

-- 외부 프로젝트는 LÖVE의 source/save 가상 파일시스템과 별도로 접근한다.
-- 현재 개발 호스트인 Windows의 Unicode API를 사용하여 한글 경로도 보존한다.
if ffi.os ~= "Windows" then
    error("External project filesystem currently requires Windows")
end

ffi.cdef[[
typedef struct { uint32_t low; uint32_t high; } LaboFileTime;
typedef struct {
    uint32_t attributes;
    LaboFileTime creation, access, write;
    uint32_t sizeHigh, sizeLow, reserved0, reserved1;
    uint16_t name[260];
    uint16_t alternate[14];
} LaboFindData;
uint32_t __stdcall GetFileAttributesW(const uint16_t *path);
int __stdcall CreateDirectoryW(const uint16_t *path, void *security);
int __stdcall RemoveDirectoryW(const uint16_t *path);
int __stdcall DeleteFileW(const uint16_t *path);
int __stdcall MoveFileW(const uint16_t *source, const uint16_t *target);
int __stdcall MoveFileExW(const uint16_t *source, const uint16_t *target, uint32_t flags);
void * __stdcall FindFirstFileW(const uint16_t *path, LaboFindData *data);
int __stdcall FindNextFileW(void *handle, LaboFindData *data);
int __stdcall FindClose(void *handle);
uint32_t __stdcall GetLastError(void);
void * __stdcall CreateFileW(const uint16_t *path, uint32_t access, uint32_t sharing,
    void *security, uint32_t disposition, uint32_t flags, void *templateFile);
int __stdcall ReadFile(void *handle, void *buffer, uint32_t size, uint32_t *read, void *overlapped);
int __stdcall WriteFile(void *handle, const void *buffer, uint32_t size, uint32_t *written, void *overlapped);
int __stdcall CloseHandle(void *handle);
]]

local win = ffi.load("kernel32")
local INVALID_HANDLE = ffi.cast("void *", -1)

local function failure(operation, code)
    return operation .. " failed (Windows error " .. tonumber(code or win.GetLastError()) .. ")"
end

local Unicode = require("editor.WindowsUnicode")
local wide, utf8 = Unicode.wide, Unicode.utf8

function FileSystem.join(path, name)
    return path:gsub("[/\\]+$", "") .. "/" .. name
end

function FileSystem.parent(path)
    path = path:gsub("\\", "/"):gsub("/+$", "")
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == "" then return path .. "/" end
    if parent:match("^%a:$") then parent = parent .. "/" end
    return parent
end

function FileSystem.info(path)
    local attributes = win.GetFileAttributesW(wide(path))
    if attributes == 4294967295 then
        local code = win.GetLastError()
        if code == 2 or code == 3 then return nil end
        return nil, failure("Read file attributes", code)
    end
    return {
        type = bit.band(attributes, 16) ~= 0 and "directory" or "file",
        isLink = bit.band(attributes, 1024) ~= 0
    }
end

function FileSystem.list(path)
    local info, err = FileSystem.info(path)
    if not info or info.type ~= "directory" then
        return nil, err or "Folder does not exist"
    end
    local data = ffi.new("LaboFindData[1]")
    local handle = win.FindFirstFileW(wide(FileSystem.join(path, "*")), data)
    if handle == INVALID_HANDLE then
        local code = win.GetLastError()
        if code == 2 then return {} end
        return nil, failure("Read folder", code)
    end
    local entries = {}
    repeat
        local name = utf8(data[0].name)
        if name ~= "." and name ~= ".." then
            entries[#entries + 1] = {
                name = name,
                size = tonumber(data[0].sizeHigh) * 4294967296 + tonumber(data[0].sizeLow),
                type = bit.band(data[0].attributes, 16) ~= 0 and "directory" or "file",
                isLink = bit.band(data[0].attributes, 1024) ~= 0
            }
        end
    until win.FindNextFileW(handle, data) == 0
    local code = win.GetLastError()
    win.FindClose(handle)
    if code ~= 18 then return nil, failure("Read folder", code) end
    table.sort(entries, function(a, b)
        if a.type ~= b.type then return a.type == "directory" end
        if a.name:lower() == b.name:lower() then return a.name < b.name end
        return a.name:lower() < b.name:lower()
    end)
    return entries
end

function FileSystem.mkdir(path)
    if win.CreateDirectoryW(wide(path), nil) == 0 then
        return false, failure("Create folder")
    end
    return true
end

function FileSystem.removeFile(path)
    if win.DeleteFileW(wide(path)) == 0 then return false, failure("Remove file") end
    return true
end

function FileSystem.rename(source, target)
    if win.MoveFileW(wide(source), wide(target)) == 0 then return false, failure("Move file") end
    return true
end

function FileSystem.removeDirectory(path)
    if win.RemoveDirectoryW(wide(path)) == 0 then return false, failure("Remove empty folder") end
    return true
end

function FileSystem.read(path)
    local handle = win.CreateFileW(wide(path), 2147483648, 7, nil, 3, 128, nil)
    if handle == INVALID_HANDLE then return nil, failure("Open file") end
    local chunks, buffer, count = {}, ffi.new("char[65536]"), ffi.new("uint32_t[1]")
    while true do
        if win.ReadFile(handle, buffer, 65536, count, nil) == 0 then
            local err = failure("Read file")
            win.CloseHandle(handle)
            return nil, err
        end
        if count[0] == 0 then break end
        chunks[#chunks + 1] = ffi.string(buffer, count[0])
    end
    win.CloseHandle(handle)
    return table.concat(chunks)
end

function FileSystem.createFile(path, text)
    -- CREATE_NEW는 이미 존재하는 파일을 덮어쓰지 않는다.
    local handle = win.CreateFileW(wide(path), 1073741824, 0, nil, 1, 128, nil)
    if handle == INVALID_HANDLE then return false, failure("Create file") end
    local count = ffi.new("uint32_t[1]")
    local wrote = win.WriteFile(handle, text, #text, count, nil) ~= 0 and count[0] == #text
    local err = not wrote and failure("Write file") or nil
    local closed = win.CloseHandle(handle) ~= 0
    if not wrote or not closed then
        FileSystem.removeFile(path)
        return false, err or failure("Close file")
    end
    return true
end

function FileSystem.writeAtomic(path, text)
    local info, err = FileSystem.info(path)
    if err then return false, err end
    if info and (info.isLink or info.type ~= "file") then return false, "Target is not a regular file" end
    local temporary = path .. ".tmp-" .. require("editor.AssetId").new()
    local created, createError = FileSystem.createFile(temporary, text)
    if not created then return false, createError end
    -- 같은 디렉터리의 새 파일로 교체하여 실패 시 기존 정상 파일을 보존한다.
    if win.MoveFileExW(wide(temporary), wide(path), 9) == 0 then
        local moveError = failure("Replace file")
        FileSystem.removeFile(temporary)
        return false, moveError
    end
    return true
end

return FileSystem
