local Prefab = require("editor.Prefab")
local Fs = require("editor.HostFileSystem")
local PrefabDocument = {}
PrefabDocument.__index = PrefabDocument

function PrefabDocument.load(project, reference)
    local path, err = project:resolveAssetFile(reference)
    if not path then return nil, err end
    local text, readError = Fs.read(path)
    if not text then return nil, readError end
    local data, decodeError = Prefab.decode(text)
    if not data then return nil, decodeError end
    local id = project:getAssetId(project:getAssetReference(reference))
    if not id then return nil, "Prefab is not registered" end
    return setmetatable({data = data, assetId = id,
        savedSnapshot = assert(Prefab.encodeData(data))}, PrefabDocument)
end

function PrefabDocument:isDirty()
    return Prefab.encodeData(self.data) ~= self.savedSnapshot
end

function PrefabDocument:save(project)
    -- 이동 후에도 ID로 현재 파일 위치를 찾는다.
    local path, err = project:resolveAssetFile(self.assetId)
    if not path then return false, err end
    local text, encodeError = Prefab.encodeData(self.data)
    if not text then return false, encodeError end
    local saved, saveError = Fs.writeAtomic(path, text)
    if not saved then return false, saveError end
    self.savedSnapshot = text
    return true
end

return PrefabDocument
