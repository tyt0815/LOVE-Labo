local Examples = {}
local SOURCES = {
    HudControls = [=[
local Controls = {properties = {drawOrder = {type = "number", default = 1000}}}
function Controls:update(dt)
    local t, speed = self.owner.transform, 240 * dt
    if love.keyboard.isDown("a", "left") then t.x = t.x - speed end
    if love.keyboard.isDown("d", "right") then t.x = t.x + speed end
    if love.keyboard.isDown("w", "up") then t.y = t.y - speed end
    if love.keyboard.isDown("s", "down") then t.y = t.y + speed end
end
function Controls:keypressed(key)
    local camera = self.owner:getScriptByName("camera")
    if key == "=" then camera.zoom = math.min(8, camera.zoom * 2)
    elseif key == "-" then camera.zoom = math.max(0.25, camera.zoom / 2) end
end
function Controls:draw(context)
    context:withScreen(function()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("WASD: camera | = / -: zoom | click the anchored buttons", 0, context.viewport.height / 2 + 44, context.viewport.width, "center")
    end)
end
return Controls
]=],
    PublicCamera = [=[
local Engine = require("Engine")
local Camera = {extends = "__CONTROLS__", properties = {
    width = {type = "number", default = 1280}, height = {type = "number", default = 720},
    zoom = {type = "number", default = 1}
}}
function Camera:getProjection()
    return {transform = self.owner:getWorldTransform(), width = self.width / self.zoom, height = self.height / self.zoom}
end
function Camera:load(world)
    self.view = Engine.Rendering.createView(world, {owner = self, projection = function() return self:getProjection() end})
end
function Camera:unload() self.view:release() end
return Camera
]=],
    PublicCanvas = [=[
local Engine = require("Engine")
local Canvas = {properties = {width = {type = "number", default = 1280}, height = {type = "number", default = 720}}}
function Canvas:scale()
    local camera = self.owner.parent and self.owner.parent:getScriptByName("camera")
    return camera and 1 / camera.zoom or 1
end
function Canvas:configure()
    Engine.Bounds.bind(self, function() return -self.width / 2, -self.height / 2, self.width, self.height end, {primary = true})
    Engine.Transform.bindLocal(self.owner, {owner = self,
        resolve = function(value)
            local t, scale = assert(Engine.Transform.copy(value)), self:scale()
            t.x, t.y, t.scaleX, t.scaleY = t.x * scale, t.y * scale, t.scaleX * scale, t.scaleY * scale
            return t
        end,
        unresolve = function(value)
            local t = assert(Engine.Transform.copy(self.owner.transform))
            t.x, t.y = value.x / self:scale(), value.y / self:scale(); return t
        end})
end
return Canvas
]=],
    PublicLayout = [=[
local Engine = require("Engine")
local OPTIONS = {"topLeft", "top", "topRight", "left", "center", "right", "bottomLeft", "bottom", "bottomRight"}
local POINTS = {topLeft = {0, 0}, top = {0.5, 0}, topRight = {1, 0}, left = {0, 0.5}, center = {0.5, 0.5},
    right = {1, 0.5}, bottomLeft = {0, 1}, bottom = {0.5, 1}, bottomRight = {1, 1}}
local Layout = {properties = {
    width = {type = "number", default = 176}, height = {type = "number", default = 44},
    anchor = {type = "string", default = "center", options = OPTIONS}, pivot = {type = "string", default = "center", options = OPTIONS}
}}
function Layout:offset(context)
    local x, y, w, h, source = Engine.Bounds.parent(self.owner, context)
    if not source then return 0, 0 end
    local anchor = POINTS[self.anchor]
    x, y = x + w * anchor[1], y + h * anchor[2]
    if source ~= self.owner.parent then
        x, y = Engine.Transform.point(source:getWorldTransform(context), x, y)
        x, y = Engine.Transform.inversePoint(self.owner.parent:getWorldTransform(context), x, y)
        assert(x, "Layout parent Transform cannot be inverted")
    end
    return x, y
end
function Layout:configure()
    Engine.Bounds.bind(self, function()
        local pivot = POINTS[self.pivot]; return -pivot[1] * self.width, -pivot[2] * self.height, self.width, self.height
    end, {primary = true})
    Engine.Transform.bindLocal(self.owner, {owner = self,
        resolve = function(value, context)
            local t = assert(Engine.Transform.copy(value)); local x, y = self:offset(context)
            t.x, t.y = t.x + x, t.y + y; return t
        end,
        unresolve = function(value, context)
            local t = assert(Engine.Transform.copy(self.owner.transform)); local x, y = self:offset(context)
            t.x, t.y = value.x - x, value.y - y; return t
        end})
end
function Layout:drawEditor(context) context:bounds(self) end
return Layout
]=],
    PublicButton = [=[
local Engine = require("Engine")
local Button = {properties = {
    caption = {type = "string", default = "Button"}, clicks = {type = "number", default = 0},
    drawOrder = {type = "number", default = 200}
}}
function Button:configure() Engine.Bounds.bind(self, function(context) return Engine.Bounds.of(self.owner, context) end) end
function Button:load(world)
    Engine.Input.registerRegion(world, {owner = self,
        hitTest = function(context, x, y) return self:hitTest(context, x, y) end,
        onDown = function() self.clicks = self.clicks + 1; return true end})
end
function Button:draw(context)
    local x, y, w, h = self:getBounds(context); if not x then return false end
    love.graphics.setColor(self.clicks > 0 and 0.2 or 0.16, self.clicks > 0 and 0.6 or 0.38, 0.62, 1)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    love.graphics.setColor(1, 1, 1, 1); love.graphics.printf(self.caption .. " : " .. self.clicks, x, y + 14, w, "center")
end
return Button
]=],
    PublicWorld = [=[
local World = {}
function World:draw()
    love.graphics.setColor(0.2, 0.22, 0.24, 1)
    for position = -2560, 2560, 80 do
        love.graphics.line(position, -2560, position, 2560); love.graphics.line(-2560, position, 2560, position)
    end
    love.graphics.setColor(0.9, 0.35, 0.2, 1); love.graphics.circle("fill", 0, 0, 36)
end
return World
]=],
}
function Examples.create(project, publicOnly)
    local Fs, Json, Id = require("editor.HostFileSystem"), require("project.Json"), require("project.AssetId")
    local folder = "Assets/Examples"
    local names = {"HudControls", "PublicCamera", "PublicCanvas", "PublicLayout", "PublicButton", "PublicWorld"}
    local paths = {}
    for _, name in ipairs(names) do paths[#paths + 1] = folder .. "/" .. name .. ".lua" end
    for _, name in ipairs({"PF_PublicHud.prefab", "L_PublicApiHud.level"}) do paths[#paths + 1] = folder .. "/" .. name end
    if not publicOnly then for _, name in ipairs({"PF_AnchoredHud.prefab", "L_AnchoredHud.level"}) do paths[#paths + 1] = folder .. "/" .. name end end
    for _, path in ipairs(paths) do assert(not project:getAssetId(path) and not Fs.info(assert(project:resolvePath(path))), "UI example already exists: " .. path) end
    if not publicOnly then assert(require("editor.PluginOperations").apply(project, "LaboEssentials", true, true)) end
    if not Fs.info(assert(project:resolvePath(folder))) then assert(project:createEntry("Assets", "folder", "Examples")) end
    for _, name in ipairs(names) do assert(project:createEntry(folder, "lua", name, {scriptKind = "script"})) end
    local ids = {}; for _, name in ipairs(names) do ids[name] = assert(project:getAssetId(folder .. "/" .. name .. ".lua")) end
    for _, name in ipairs(names) do
        local source = SOURCES[name]:gsub("__CONTROLS__", ids.HudControls)
        assert(Fs.writeAtomic(assert(project:resolveSourceFile(folder .. "/" .. name .. ".lua")), source))
    end
    assert(project:rebuildAssetIndex())
    local anchors = {"topLeft", "top", "topRight", "left", "center", "right", "bottomLeft", "bottom", "bottomRight"}
    local function prefab(name, canvasSource, layoutSource)
        local data = {formatVersion = 4, name = name, scripts = {{id = Id.new(), name = "canvas", source = canvasSource}}, overrides = {scripts = {}}, children = {}}
        for index, anchor in ipairs(anchors) do
            local layoutId, buttonId = Id.new(), Id.new()
            local col, row = (index - 1) % 3, math.floor((index - 1) / 3)
            data.children[#data.children + 1] = {id = Id.new(), name = anchor,
                transform = {x = col == 0 and 20 or col == 2 and -20 or 0, y = row == 0 and 20 or row == 2 and -20 or 0},
                scripts = {{id = layoutId, name = "layout", source = layoutSource}, {id = buttonId, name = "button", source = ids.PublicButton}},
                overrides = {scripts = {[layoutId] = {width = 176, height = 44, anchor = anchor, pivot = anchor}, [buttonId] = {caption = anchor}}}}
        end
        assert(project:createEntry(folder, "prefab", name, {prefabData = data}))
        return assert(project:getAssetId(folder .. "/" .. name .. ".prefab"))
    end
    local anchored = not publicOnly and prefab("PF_AnchoredHud", project.plugins.scripts.Canvas.id, project.plugins.scripts.RectLayout.id)
    local pure = prefab("PF_PublicHud", ids.PublicCanvas, ids.PublicLayout)
    local levels = {{name = "L_PublicApiHud", prefab = pure, pure = true}}
    if anchored then levels[#levels + 1] = {name = "L_AnchoredHud", prefab = anchored} end
    for _, item in ipairs(levels) do
        local level = require("editor.Level").new()
        local camera = level:addLObject(0, 0, nil, "Camera")
        local cameraId = Id.new()
        camera.scripts = {{id = cameraId, name = "camera", source = item.pure and ids.PublicCamera or project.plugins.scripts.Camera.id}}
        if not item.pure then
            local viewId = Id.new()
            camera.scripts[#camera.scripts + 1] = {id = viewId, name = "view", source = project.plugins.scripts.View.id}
            camera.scripts[#camera.scripts + 1] = {id = Id.new(), name = "controls", source = ids.HudControls}
            camera.scriptOverrides = {[viewId] = {cameraSource = {authoringId = camera.authoringId, script = cameraId}}}
        end
        local scene = level:addLObject(0, 0, nil, "World grid")
        scene.scripts = {{id = Id.new(), name = "world", source = ids.PublicWorld}}
        local hud = level:addLObject(0, 0, item.prefab, "HUD Prefab")
        hud.parentAuthoringId = camera.authoringId
        assert(require("project.PrefabHierarchy").expandAuthoring(project, level, hud))
        assert(project:createEntry(folder, "level", item.name, {level = level}))
    end
    assert(project:rebuildAssetIndex())
    return {level = folder .. (publicOnly and "/L_PublicApiHud.level" or "/L_AnchoredHud.level"), publicLevel = folder .. "/L_PublicApiHud.level", prefab = folder .. "/PF_AnchoredHud.prefab"}
end
return Examples
