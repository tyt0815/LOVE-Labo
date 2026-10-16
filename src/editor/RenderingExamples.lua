local Examples = {}
local SOURCE = [[local Rendering = require("Engine.Rendering")
local Multiview = {properties = {
    mainCamera = {type = "script", default = false, group = "Views"},
    mapCamera = {type = "script", default = false, group = "Views"}
}}
function Multiview:load(world)
    self.mapTarget = Rendering.createTarget(world, {width = 256, height = 256})
    self.mapView = Rendering.createView(world, {projection = function() return self.mapCamera:getProjection() end, target = self.mapTarget,
        order = -10, input = false, owner = self})
    self.mainView = Rendering.createView(world, {projection = function() return self.mainCamera:getProjection() end, owner = self})
end
function Multiview:update(dt)
    local object = self.mainCamera.owner
    local speed = 160 * dt
    if love.keyboard.isDown("left", "a") then object.transform.x = object.transform.x - speed end
    if love.keyboard.isDown("right", "d") then object.transform.x = object.transform.x + speed end
    if love.keyboard.isDown("up", "w") then object.transform.y = object.transform.y - speed end
    if love.keyboard.isDown("down", "s") then object.transform.y = object.transform.y + speed end
end
function Multiview:keypressed(key)
    if key == "=" then self.mainCamera.zoom = math.min(8, self.mainCamera.zoom * 2)
    elseif key == "-" then self.mainCamera.zoom = math.max(0.25, self.mainCamera.zoom / 2)
    elseif key == "m" then self.mapView:setEnabled(not self.mapView.enabled) end
end
function Multiview:drawWorld(context)
    love.graphics.setColor(0.18, 0.25, 0.35, 1)
    for coordinate = -640, 640, 80 do
        love.graphics.line(-640, coordinate, 640, coordinate)
        love.graphics.line(coordinate, -640, coordinate, 640)
    end
    love.graphics.setColor(0.95, 0.4, 0.25, 1)
    love.graphics.rectangle("fill", -100, -60, 80, 80)
    love.graphics.setColor(0.2, 0.8, 0.6, 1)
    love.graphics.circle("fill", 220, 120, 40)
end
function Multiview:drawOverlay(context)
    local width = context.viewport.width
    if self.mapView.enabled then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setBlendMode("alpha", "premultiplied")
        love.graphics.draw(self.mapTarget:getTexture(), width - 212, 20, 0, 0.75, 0.75)
        love.graphics.setBlendMode("alpha")
        love.graphics.rectangle("line", width - 212, 20, 192, 192)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("WASD / arrows: move camera | = / -: zoom | M: minimap", 16, 16)
end
function Multiview:unload()
    self.mainView:release(); self.mapView:release(); self.mapTarget:release()
end
function Multiview:draw(context)
    self:drawWorld(context)
    if context.view ~= self.mainView then return end
    context:withScreen(function() self:drawOverlay(context) end)
end
return Multiview
]]
function Examples.create(project)
    local Fs = require("editor.HostFileSystem")
    local folder, script, levelPath = "Assets/Examples", "Assets/Examples/Multiview.lua", "Assets/Examples/L_Multiview.level"
    for _, reference in ipairs({script, levelPath}) do
        assert(not project:getAssetId(reference) and not Fs.info(assert(project:resolvePath(reference))), "Rendering example already exists: " .. reference)
    end
    assert(require("editor.PluginOperations").apply(project, "LaboEssentials", true, true))
    if not Fs.info(assert(project:resolvePath(folder))) then assert(project:createEntry("Assets", "folder", "Examples")) end
    assert(project:createEntry(folder, "lua", "Multiview", {scriptKind = "script"}))
    assert(Fs.writeAtomic(assert(project:resolveSourceFile(script)), SOURCE))
    assert(project:rebuildAssetIndex())
    local level = require("editor.Level").new()
    local main = assert(level:addLObject(0, 0, nil, "Main Camera"))
    local map = assert(level:addLObject(0, 0, nil, "Map Camera"))
    local cameraId, mapId, managerId = require("project.AssetId").new(), require("project.AssetId").new(), require("project.AssetId").new()
    main.scripts = {{id = cameraId, name = "Camera", source = "Camera"}}
    map.scripts = {{id = mapId, name = "Camera", source = "Camera"}}
    main.scriptOverrides = {[cameraId] = {viewWidth = 640, viewHeight = 360}}
    map.scriptOverrides = {[mapId] = {viewWidth = 1440, viewHeight = 1440}}
    level.scripts = {{id = managerId, name = "rendering", source = project:getAssetId(script)}}
    level.scriptOverrides = {[managerId] = {mainCamera = {authoringId = main.authoringId, script = cameraId},
        mapCamera = {authoringId = map.authoringId, script = mapId}}}
    assert(project:createEntry(folder, "level", "L_Multiview", {level = level}))
    return {level = levelPath, script = script}
end
return Examples
