local bit = require("bit")
local Zip = {}
local function little(value, count)
    local result = {}
    for i = 1, count do result[i] = string.char(value % 256); value = math.floor(value / 256) end
    return table.concat(result)
end
local crcTable = {}
for i = 0, 255 do
    local value = i
    for _ = 1, 8 do value = bit.bxor(bit.rshift(value, 1), bit.band(value, 1) ~= 0 and 0xEDB88320 or 0) end
    crcTable[i] = value
end
local function crc32(bytes)
    local value = -1
    for i = 1, #bytes do value = bit.bxor(bit.rshift(value, 8), crcTable[bit.band(bit.bxor(value, bytes:byte(i)), 255)]) end
    local unsigned = bit.bnot(value)
    return unsigned < 0 and unsigned + 4294967296 or unsigned
end

-- 의존 도구 없이 ZIP32 저장 방식으로 UTF-8 경로와 바이너리 에셋을 묶는다.
function Zip.encode(entries)
    assert(#entries < 65535, "Too many ZIP entries")
    local chunks, central, offset, names = {}, {}, 0, {}
    for _, entry in ipairs(entries) do
        local name, bytes = entry.name, entry.bytes
        assert(not names[name] and #name < 65536, "Duplicate or oversized ZIP name")
        names[name] = true
        assert(#bytes < 4294967296 and offset < 4294967296, "ZIP32 size limit exceeded")
        local size, crc = little(#bytes, 4), little(crc32(bytes), 4)
        local common = little(2048, 2) .. little(0, 2) .. little(0, 2) .. little(33, 2) .. crc .. size .. size .. little(#name, 2)
        local header = "PK\3\4" .. little(20, 2) .. common .. little(0, 2) .. name
        chunks[#chunks + 1], chunks[#chunks + 2] = header, bytes
        central[#central + 1] = "PK\1\2" .. little(20, 2) .. little(20, 2) .. common .. little(0, 2)
            .. little(0, 2) .. little(0, 2) .. little(0, 2) .. little(0, 4) .. little(offset, 4) .. name
        offset = offset + #header + #bytes
    end
    local directory = table.concat(central)
    assert(offset + #directory < 4294967296, "ZIP32 size limit exceeded")
    chunks[#chunks + 1] = directory
    chunks[#chunks + 1] = "PK\5\6" .. little(0, 2) .. little(0, 2) .. little(#entries, 2) .. little(#entries, 2)
        .. little(#directory, 4) .. little(offset, 4) .. little(0, 2)
    return table.concat(chunks)
end
return Zip
