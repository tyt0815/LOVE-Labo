local FS = require("editor.host_filesystem")
local Thumbnail = {}
Thumbnail.__index = Thumbnail
local supported = { png = true, jpg = true, jpeg = true, bmp = true, tga = true, gif = true }
local SIZE = 88

function Thumbnail.new(project)
    return setmetatable({ project = project, entries = {}, clock = 0, budget = 0 }, Thumbnail)
end

function Thumbnail:clear()
    for _, item in pairs(self.entries) do if item.image then item.image:release() end end
    self.entries = {}
end

function Thumbnail:beginFrame()
    self.budget = 2
end

function Thumbnail:get(entry)
    if entry.type ~= "file" or entry.isLink then return nil end
    local extension = entry.name:match("%.([^%.]+)$")
    if not extension or not supported[extension:lower()] or (entry.size or 0) > 16 * 1024 * 1024 then return nil end
    self.clock = self.clock + 1
    local cached = self.entries[entry.reference]
    if cached then cached.used = self.clock; return cached.image end
    if self.budget <= 0 then return nil end
    self.budget = self.budget - 1
    local canvasBefore = love.graphics.getCanvas()
    local source, canvas, data
    love.graphics.push("all")
    local ok, result = pcall(function()
        local path = assert(self.project:resolveAssetFile(entry.reference))
        local bytes = assert(FS.read(path))
        assert(#bytes <= 16 * 1024 * 1024, "Thumbnail source is too large")
        source = love.graphics.newImage(love.filesystem.newFileData(bytes, entry.name))
        canvas = love.graphics.newCanvas(SIZE, SIZE)
        love.graphics.setCanvas(canvas)
        love.graphics.origin()
        love.graphics.setScissor()
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
        local width, height = source:getDimensions()
        local scale = math.min(SIZE / width, SIZE / height)
        love.graphics.draw(source, (SIZE - width * scale) / 2, (SIZE - height * scale) / 2, 0, scale, scale)
        love.graphics.setCanvas(canvasBefore)
        data = canvas:newImageData()
        return love.graphics.newImage(data)
    end)
    love.graphics.setCanvas(canvasBefore)
    love.graphics.pop()
    if source then source:release() end
    if canvas then canvas:release() end
    if data then data:release() end
    -- 손상되거나 지원하지 않는 이미지는 아이콘으로 표시하며 Refresh 전까지 재시도하지 않는다.
    self.entries[entry.reference] = { image = ok and result or nil, used = self.clock }
    local count, oldestKey, oldest = 0, nil, math.huge
    for key, item in pairs(self.entries) do
        count = count + 1
        if item.used < oldest then oldestKey, oldest = key, item.used end
    end
    if count > 96 then
        local item = self.entries[oldestKey]
        if item.image then item.image:release() end
        self.entries[oldestKey] = nil
    end
    return ok and result or nil
end

return Thumbnail
