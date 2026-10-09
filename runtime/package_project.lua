local Package = {}
Package.__index = Package
function Package.new(manifest)
    local self = setmetatable({assetMetadata = manifest.metadata, assetPaths = {}, assetIds = {}}, Package)
    for reference, meta in pairs(manifest.metadata or {}) do
        self.assetIds[reference], self.assetPaths[meta.id] = meta.id, reference
    end
    return self
end
function Package:getAssetReference(reference)
    if require("project.asset_id").isValid(reference) then
        return self.assetPaths[reference], "Asset ID is missing: " .. reference
    end
    return reference
end
function Package:getAssetId(reference) return self.assetIds[reference] end
function Package:resolve(reference, root)
    local path, err = self:getAssetReference(reference)
    if not path then return nil, err end
    if not self.assetMetadata[path] or path:sub(1, #root + 1) ~= root .. "/" then return nil, "Invalid packaged reference: " .. tostring(path) end
    local packed = "project/" .. path
    if not love.filesystem.getInfo(packed, "file") then return nil, "Missing packaged file: " .. path end
    return packed
end
function Package:resolveSourceFile(reference) return self:resolve(reference, "Sources") end
function Package:resolveAssetFile(reference) return self:resolve(reference, "Assets") end
function Package:readSource(reference)
    local path, err = self:resolveSourceFile(reference)
    if not path then return nil, err end
    return love.filesystem.read(path)
end
function Package:readAsset(reference)
    local path, err = self:resolveAssetFile(reference)
    if not path then return nil, err end
    return love.filesystem.read(path)
end
function Package:getScriptKind(reference)
    local path, err = self:getAssetReference(reference)
    local meta = path and self.assetMetadata[path]
    return meta and meta.scriptKind, err or "Script kind is missing"
end
return Package
