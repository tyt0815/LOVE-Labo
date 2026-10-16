local ffi = require("ffi")
ffi.cdef[[
int __stdcall MultiByteToWideChar(uint32_t cp, uint32_t flags, const char *text,
    int length, uint16_t *output, int capacity);
int __stdcall WideCharToMultiByte(uint32_t cp, uint32_t flags, const uint16_t *text,
    int length, char *output, int capacity, const char *defaultChar, int *usedDefault);
]]
local win = ffi.load("kernel32")
local Unicode = {}

function Unicode.wide(text)
    assert(type(text) == "string" and not text:find("\0", 1, true), "invalid Windows text")
    local length = win.MultiByteToWideChar(65001, 8, text, #text, nil, 0)
    assert(length > 0, "invalid UTF-8 Windows text")
    local result = ffi.new("uint16_t[?]", length + 1)
    win.MultiByteToWideChar(65001, 8, text, #text, result, length)
    return result
end

function Unicode.utf8(text)
    local length = win.WideCharToMultiByte(65001, 0, text, -1, nil, 0, nil, nil)
    assert(length > 0, "invalid UTF-16 Windows text")
    local result = ffi.new("char[?]", length)
    win.WideCharToMultiByte(65001, 0, text, -1, result, length, nil, nil)
    return ffi.string(result)
end

return Unicode
