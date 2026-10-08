local AssetId = {}

function AssetId.isValid(value)
    return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
        and value == value:lower()
end

function AssetId.new()
    local ffi = require("ffi")
    if not AssetId.win then
        ffi.cdef[[
            typedef struct { uint32_t a; uint16_t b, c; uint8_t d[8]; } LaboAssetGuid;
            int32_t __stdcall CoCreateGuid(LaboAssetGuid *guid);
        ]]
        AssetId.win = ffi.load("ole32")
    end
    local guid = ffi.new("LaboAssetGuid[1]")
    assert(AssetId.win.CoCreateGuid(guid) == 0, "Cannot generate asset UUID")
    local g = guid[0]
    return string.format("%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x", tonumber(g.a),
        tonumber(g.b), tonumber(g.c), g.d[0], g.d[1], g.d[2], g.d[3], g.d[4], g.d[5], g.d[6], g.d[7])
end

return AssetId
