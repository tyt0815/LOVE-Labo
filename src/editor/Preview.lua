local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local Transform = require("core.Transform")
local Color = require("editor.Color")
local Preview = {}
Preview.__index = Preview
function Preview.color(value)
    return Color.rgb(value or Color.default())
end
function Preview.new(project, descriptor)
    -- CLI는 창 없이 시작하므로 이미지·Canvas를 만들기 전에 컨텍스트를 준비한다.
    if not love.window.isOpen() then
        local opened, windowError = love.window.setMode(1, 1, {borderless = true, resizable = false, vsync = 0})
        assert(opened, windowError or "Could not create preview graphics context")
        love.window.minimize()
    end
    local self = setmetatable({project = project, images = {}, dependencies = {}, background = Color.default()}, Preview)
    local reference = descriptor.reference and project:getAssetReference(descriptor.reference)
    if reference and ({png = true, jpg = true, jpeg = true, bmp = true, tga = true, gif = true})[(reference:match("%.([^%.]+)$") or ""):lower()] then
        self.image = self:getImage(reference)
        return self
    end
    local data = descriptor.data
    if reference and reference:match("%.prefab$") then
        local bytes = assert(project:readAsset(reference))
        local prefab = assert(require("project.Prefab").decode(bytes))
        self.backgroundOverride = prefab.previewBackground
        self.background = assert(Preview.color(self.backgroundOverride))
        data = {lobjects = {{authoringId = 1, transform = {x = 0, y = 0}, definitionReference = project:getAssetId(reference)}}}
    elseif reference and reference:match("%.level$") then
        data = assert(require("editor.LevelFile").decode(assert(project:readAsset(reference)))):toData()
    end
    if not data then return self end
    self.world = assert(require("runtime.WorldLoader").prepare(project, data))
    self.objects = {}
    for _, object in ipairs(self.world.lobjects) do
        local included = not descriptor.instance
        local parent = object
        while parent do
            if parent.authoringId == descriptor.instance then included = true; break end
            parent = parent.parent
        end
        if included then self.objects[#self.objects + 1] = object end
    end
    return self
end
function Preview:getImage(reference)
    if self.images[reference] ~= nil then return self.images[reference] or nil end
    local bytes = assert(self.project:readAsset(reference))
    self.dependencies[reference] = love.data.encode("string", "hex", love.data.hash("sha256", bytes))
    local image = love.graphics.newImage(love.filesystem.newFileData(bytes, reference))
    self.images[reference] = image
    return image
end
function Preview:release()
    if self.world then self.world:dispose(); self.world = nil end
    for _, image in pairs(self.images) do if image then image:release() end end
    self.images = {}
end
function Preview:draw(rect, background)
    local color = assert(Preview.color(background or self.background))
    local ok, drawn = require("core.GraphicsScope").call(function()
        love.graphics.intersectScissor(rect.x, rect.y, rect.w, rect.h)
        love.graphics.setColor(color[1] / 255, color[2] / 255, color[3] / 255, 1)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        if self.image then
            local width, height = self.image:getDimensions()
            local scale = math.min(rect.w / width, rect.h / height) * 0.9
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(self.image, rect.x + (rect.w - width * scale) / 2, rect.y + (rect.h - height * scale) / 2, 0, scale, scale)
            return true
        end
        if not self.world then return false end
        local ctx = {preview = true, image = function(_, reference) return reference and reference ~= false and self:getImage(reference) or nil end,
            viewport = {width = 1280, height = 720}, transform = function(_, script) return require("core.CoordinateSpace").transform(script) end}
        local left, top, right, bottom
        for _, entry in ipairs(require("core.ScriptOrder").entries(self.objects, "draw")) do
            local script = entry.script
            if script.getBounds then
                local x, y, width, height = script:getBounds(ctx)
                if x then for _, point in ipairs({{x, y}, {x + width, y}, {x + width, y + height}, {x, y + height}}) do
                    local wx, wy = Transform.point(ctx:transform(script), point[1], point[2])
                    left, right = math.min(left or wx, wx), math.max(right or wx, wx)
                    top, bottom = math.min(top or wy, wy), math.max(bottom or wy, wy)
                end end
            end
        end
        local width, height = left and right - left or 100, top and bottom - top or 100
        local scale = math.min(rect.w / math.max(1, width), rect.h / math.max(1, height)) * 0.85
        local centerX, centerY = left and (left + right) / 2 or 0, top and (top + bottom) / 2 or 0
        return require("core.Renderer").drawObjects(self.objects, function(ref) return self:getImage(ref) end,
            function(x, y) return rect.x + rect.w / 2 + (x - centerX) * scale, rect.y + rect.h / 2 + (y - centerY) * scale end, scale, ctx)
    end)
    if not ok then return false, tostring(drawn) end
    return drawn
end
function Preview:png(path, size, background)
    local color, colorError = Preview.color(background or self.background)
    if not color then return false, colorError end
    size = size or 256
    local canvas = love.graphics.newCanvas(size, size)
    local ok, drawn, err = require("core.GraphicsScope").call(function()
        love.graphics.setCanvas(canvas); love.graphics.origin(); love.graphics.setScissor(); love.graphics.clear(0, 0, 0, 0)
        return self:draw({x = 0, y = 0, w = size, h = size}, color)
    end)
    if not ok then canvas:release(); return false, tostring(drawn) end
    if not drawn then canvas:release(); return false, err or "No visual content" end
    local data = canvas:newImageData(); local file = data:encode("png")
    local written, writeError = Fs.writeAtomic(path, file:getString())
    file:release(); data:release(); canvas:release()
    return written, writeError
end
return Preview
