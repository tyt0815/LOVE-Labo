local Json = require("editor.json")
local Settings = {}
local units = {translate = 32, rotate = 15, scale = 0.1}
Settings.FILE = "viewport-settings.json"
function Settings.validUnit(value)
    return type(value) == "number" and value > 0 and value < math.huge
end
function Settings.copy(values)
    local result = {}
    for mode, unit in pairs(units) do
        local value = type(values) == "table" and values[mode]
        result[mode] = {enabled = type(value) == "table" and value.enabled == true or false,
            unit = type(value) == "table" and Settings.validUnit(value.unit) and value.unit or unit}
    end
    return result
end
function Settings.load(read)
    read = read or function() return love.filesystem.read(Settings.FILE) end
    local ok, bytes = pcall(read, Settings.FILE)
    local data = ok and type(bytes) == "string" and Json.decode(bytes)
    return Settings.copy(type(data) == "table" and data.version == 1 and data.snaps or nil)
end
function Settings.save(values, write)
    local bytes, err = Json.encode({version = 1, snaps = Settings.copy(values)}, true)
    if not bytes then return false, err end
    write = write or function(_, text)
        local FS = require("editor.host_filesystem")
        local directory = love.filesystem.getSaveDirectory()
        local info, infoError = FS.info(directory)
        if infoError then return false, infoError end
        if not info then
            local created, createError = FS.mkdir(directory)
            if not created then return false, createError end
        end
        return FS.writeAtomic(directory .. "/" .. Settings.FILE, text)
    end
    return write(Settings.FILE, bytes .. "\n")
end
return Settings
