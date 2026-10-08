local ffi = require("ffi")
local bit = require("bit")
local Unicode = require("editor.windows_unicode")

ffi.cdef[[
typedef struct { uint32_t a; uint16_t b, c; uint8_t d[8]; } LaboGuid;
int32_t __stdcall CoInitializeEx(void *reserved, uint32_t flags);
void __stdcall CoUninitialize(void);
int32_t __stdcall CoCreateInstance(const LaboGuid *classId, void *outer,
    uint32_t context, const LaboGuid *interfaceId, void **object);
void __stdcall CoTaskMemFree(void *memory);
int32_t __stdcall SHCreateItemFromParsingName(const uint16_t *path, void *context,
    const LaboGuid *interfaceId, void **item);
void * __stdcall GetActiveWindow(void);
]]

local ole, shell, user = ffi.load("ole32"), ffi.load("shell32"), ffi.load("user32")
local FolderDialog = {}
local classId = ffi.new("LaboGuid", { 0xDC1C5A9C, 0xE88A, 0x4DDE, {0xA5, 0xA1, 0x60, 0xF8, 0x2A, 0x20, 0xAE, 0xF7} })
local dialogId = ffi.new("LaboGuid", { 0xD57C7288, 0xD4AD, 0x4768, {0xBE, 0x02, 0x9D, 0x96, 0x95, 0x32, 0xD9, 0x60} })
local itemId = ffi.new("LaboGuid", { 0x43826D1E, 0xE718, 0x42EE, {0xBC, 0x55, 0xA1, 0xE2, 0x61, 0xC3, 0x7B, 0xFE} })
local cancelled = -2147023673 -- HRESULT_FROM_WIN32(ERROR_CANCELLED)

-- SDK의 IFileOpenDialog/IShellItem ABI 순서다. 상속된 IUnknown 슬롯도 포함한다.
local slots = { release = 2, show = 3, setOptions = 9, getOptions = 10,
    setFolder = 12, setTitle = 17, getResult = 20, getDisplayName = 5 }
local function method(object, name, signature)
    local vtable = ffi.cast("void ***", object)[0]
    return ffi.cast(signature, vtable[slots[name]])
end

local function release(object)
    if object ~= nil then method(object, "release", "uint32_t (__stdcall *)(void *)")(object) end
end

local function check(result, operation)
    if result < 0 then
        error(operation .. " failed (HRESULT " .. string.format("0x%08X", tonumber(ffi.cast("uint32_t", result))) .. ")", 0)
    end
end

function FolderDialog.selectFolder(initialPath, title)
    local initialized = ole.CoInitializeEx(nil, 2)
    if initialized < 0 then
        return nil, "Cannot initialize Windows folder dialog (HRESULT " .. tostring(tonumber(initialized)) .. ")"
    end
    local dialog, initialItem, resultItem, displayName
    local ok, pathOrError = pcall(function()
        local output = ffi.new("void *[1]")
        check(ole.CoCreateInstance(classId, nil, 1, dialogId, output), "Create folder dialog")
        dialog = output[0]
        local options = ffi.new("uint32_t[1]")
        check(method(dialog, "getOptions", "int32_t (__stdcall *)(void *, uint32_t *)")(dialog, options), "Read dialog options")
        -- 폴더만 선택하고 실제 파일시스템 경로를 반환하며 현재 작업 폴더는 유지한다.
        check(method(dialog, "setOptions", "int32_t (__stdcall *)(void *, uint32_t)")(
            dialog, bit.bor(options[0], 0x20, 0x40, 0x800, 0x8)), "Set folder dialog options")
        check(method(dialog, "setTitle", "int32_t (__stdcall *)(void *, const uint16_t *)")(
            dialog, Unicode.wide(title or "Select project folder")), "Set folder dialog title")
        if type(initialPath) == "string" and initialPath ~= "" then
            local valid, widePath = pcall(Unicode.wide, initialPath:gsub("/", "\\"))
            if valid and shell.SHCreateItemFromParsingName(widePath, nil, itemId, output) >= 0 then
                initialItem = output[0]
                -- 잘못된 초기 경로는 Windows 기본 위치로 대체한다.
                method(dialog, "setFolder", "int32_t (__stdcall *)(void *, void *)")(dialog, initialItem)
            end
        end
        local shown = method(dialog, "show", "int32_t (__stdcall *)(void *, void *)")(dialog, user.GetActiveWindow())
        if shown == cancelled then return nil end
        check(shown, "Show folder dialog")
        check(method(dialog, "getResult", "int32_t (__stdcall *)(void *, void **)")(dialog, output), "Read selected folder")
        resultItem = output[0]
        local text = ffi.new("uint16_t *[1]")
        -- SIGDN_FILESYSPATH는 표시 이름 대신 실제 파일시스템 경로를 반환한다.
        check(method(resultItem, "getDisplayName", "int32_t (__stdcall *)(void *, uint32_t, uint16_t **)")(
            resultItem, 0x80058000, text), "Read selected folder path")
        displayName = text[0]
        return Unicode.utf8(displayName):gsub("\\", "/")
    end)
    if displayName ~= nil then ole.CoTaskMemFree(displayName) end
    release(resultItem)
    release(initialItem)
    release(dialog)
    -- 이미 STA로 초기화되어 S_FALSE를 받은 경우에도 호출 횟수를 맞춘다.
    ole.CoUninitialize()
    if not ok then return nil, tostring(pathOrError) end
    return pathOrError
end

return FolderDialog
