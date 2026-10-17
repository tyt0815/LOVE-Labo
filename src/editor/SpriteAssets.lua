local Assets = {}
Assets.__index = Assets
function Assets.new(project)
    return setmetatable({project = project, images = {}, layout = require("project.AuthoringLayout").new(project)}, Assets)
end
function Assets:clear()
    self.layout:clear()
    for _, cache in pairs(self.scopePreviews or {}) do
        if cache.host then require("core.ScriptHost").unload(cache.host) end
    end
    for _, image in pairs(self.images) do if image then image:release() end end
    self.images, self.error, self.scopePreviews = {}, nil, nil
end
function Assets:scopePreview(data, scope)
    local signature = assert(require("project.Json").encode({scripts = data.scripts, scriptOverrides = data.scriptOverrides}))
    self.scopePreviews = self.scopePreviews or {}
    local cache = self.scopePreviews[scope]
    if cache and cache.signature == signature then return cache.host end
    if cache and cache.host then require("core.ScriptHost").unload(cache.host) end
    self.scopePreviews[scope] = nil
    local host = require("core.ScriptHost").new(scope)
    host.isPreview = true
    local ok, err = require("project.ScopedScripts").configure(host, data, require("project.LuaScript").loader(self.project))
    if not ok then require("core.ScriptHost").unload(host) end
    self.scopePreviews[scope] = {signature = signature, host = ok and host or nil}
    if not ok then self.error = err end
    return ok and host or nil
end
function Assets:image(reference)
    if not reference then return nil end
    if self.images[reference] ~= nil then return self.images[reference] or nil end
    local ok, image = pcall(function()
        local path = assert(self.project:resolveAssetFile(reference))
        local bytes = assert(require("editor.HostFileSystem").read(path))
        return love.graphics.newImage(love.filesystem.newFileData(bytes, path))
    end)
    self.images[reference] = ok and image or false
    if not ok then self.error = tostring(image) end
    return ok and image or nil
end
function Assets:setLevel(level)
    if self.layout.level ~= level then self.layout:clear() end
    self.level, self.layout.level = level, level
    if level then level.layout = self.layout end
end
function Assets:preview(data)
    local preview = self.layout:preview(data)
    if self.layout.error then self.error = self.layout.error end
    return preview
end
function Assets:draw(object, view, zoom)
    return require("core.Renderer").draw(object, function(reference) return self:image(reference) end,
        function(x, y) return view:worldToScreen(x, y) end, zoom)
end
return Assets
