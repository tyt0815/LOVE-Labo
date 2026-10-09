local Assets = {}
Assets.__index = Assets
function Assets.new(project)
    return setmetatable({project = project, images = {}, previews = setmetatable({}, {__mode = "k"})}, Assets)
end
function Assets:clear()
    for _, image in pairs(self.images) do if image then image:release() end end
    self.images, self.previews, self.error = {}, setmetatable({}, {__mode = "k"}), nil
end
function Assets:image(reference)
    if not reference then return nil end
    if self.images[reference] ~= nil then return self.images[reference] or nil end
    local ok, image = pcall(function()
        local path = assert(self.project:resolveAssetFile(reference))
        local bytes = assert(require("editor.host_filesystem").read(path))
        return love.graphics.newImage(love.filesystem.newFileData(bytes, path))
    end)
    self.images[reference] = ok and image or false
    if not ok then self.error = tostring(image) end
    return ok and image or nil
end
function Assets:preview(data)
    local signature = require("editor.json").encode(data)
    local cache = self.previews[data]
    if cache and cache.signature == signature then return cache.object end
    local Definition = require("editor.object_definition")
    local definition, err = Definition.resolve(self.project, data.definitionReference)
    local object = assert(require("core.lobject").new(1, data))
    local ok, configureError
    if definition then ok, configureError = Definition.configure(object, definition, data.propertyOverrides, data.componentOverrides) end
    self.previews[data] = {signature = signature, object = ok and object or nil}
    if not ok then self.error = err or configureError end
    return ok and object or nil
end
function Assets:draw(object, view, zoom)
    return require("core.renderer").draw(object, function(reference) return self:image(reference) end,
        function(x, y) return view:worldToScreen(x, y) end, zoom)
end
return Assets
