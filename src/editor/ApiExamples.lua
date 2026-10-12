local Fs = require("editor.HostFileSystem")
local Json = require("project.Json")
local Examples = {}
local function assignScriptIds(level)
    local ids = {}
    for _, object in ipairs(level.lobjects) do
        object.scripts, ids[object.authoringId] = require("project.ScriptAttachments").reidentify(object.scripts)
        local overrides = {}
        for id, fields in pairs(object.scriptOverrides or {}) do overrides[ids[object.authoringId][id] or id] = fields end
        object.scriptOverrides = overrides
    end
    for _, object in ipairs(level.lobjects) do
        for _, fields in pairs(object.scriptOverrides or {}) do
            for _, value in pairs(fields) do
                if type(value) == "table" and value.script and ids[value.authoringId] then value.script = ids[value.authoringId][value.script] or value.script end
            end
        end
    end
    if level.mainCamera then level.mainCamera.script = ids[level.mainCamera.authoringId][level.mainCamera.script] or level.mainCamera.script end
end
local LEVEL = [[local LevelDemo = {properties = {welcome = {type = "string", default = "API examples ready"}}}
function LevelDemo.beginPlay(world)
    world.exampleElapsed = 0
    world.debug:screenLog(world.properties.welcome, {key = "welcome", lifespan = 5})
end
function LevelDemo.update(world, dt) world.exampleElapsed = world.exampleElapsed + dt end
return LevelDemo
]]
local MOTION = [[local Motion = {properties = {
    speed = {type = "number", default = 35, group = "Movement"},
    enabled = {type = "boolean", default = true, group = "Movement"},
    title = {type = "string", default = "Moving object"},
    target = {type = "object", default = false}, sibling = {type = "script", default = false}
}}
function Motion.beginPlay(self)
    self.originY, self.elapsed = self.owner.transform.y, 0
    local x, y = self:getWorldPosition()
    self.owner.world.debug:log(self.title .. " beginPlay at " .. x .. ", " .. y)
end
function Motion.update(self, dt)
    self.elapsed = self.elapsed + dt
    if self.enabled then
        self.owner.transform.y = self.originY + math.sin(self.elapsed) * self.speed
        self.owner.transform.rotation = (self.owner.transform.rotation + dt * 20) % 360
    end
end
return Motion
]]
local ACTIONS = [[local Engine = require("Engine")
local Actions = {extends = "Pointer", properties = {
    action = {type = "string", default = "Debug", group = "Actions"},
    caption = {type = "string", default = "Click"}, template = {type = "prefab", default = false},
    image = {type = "image", default = false},
    nextLevel = {type = "string", default = ""}, target = {type = "object", default = false},
    boundsX = {type = "number", default = -90}, boundsY = {type = "number", default = -24},
    boundsWidth = {type = "number", default = 180}, boundsHeight = {type = "number", default = 48},
    blockPointer = {type = "boolean", default = true}, inputPriority = {type = "number", default = 10},
    sortingOrder = {type = "number", default = 100}
}}
function Actions.draw(self)
    love.graphics.setColor(0.15, 0.35, 0.55, 1)
    love.graphics.rectangle("fill", -90, -24, 180, 48, 5, 5)
    love.graphics.setColor(1, 1, 1, 1); love.graphics.printf(self.caption, -86, -8, 172, "center")
end
function Actions.onPointerDown(self, event)
    local world, spawned = event.world, event.world.exampleSpawn
    world.debug:log(self.action .. " pointer down", {marker = ">"})
    if self.action == "Spawn" then world.exampleSpawn = assert(Engine.spawnLObject(world, self.template, {x = 150, y = 220}))
    elseif self.action == "Raw" then
        world.exampleSpawn = assert(world:addLObject({name = "Empty object", transform = {x = 150, y = 220}}))
    elseif self.action == "Bounds" then
        local x, y = self:getWorldPosition(); local hit = Engine.Bounds.hitTest(self, {}, x, y)
        local width, height = select(3, self:getBounds({}))
        local viewport = Engine.Viewport.new(world, 0, 0, 1280, 720)
        local sx, sy = viewport:worldToScreen(0, 0); local wx, wy = viewport:screenToWorld(sx, sy)
        local space = Engine.CoordinateSpace.canvas(self) and "screen" or "world"
        world.debug:log(space .. " bounds " .. width .. "x" .. height .. "; hit=" .. tostring(hit) .. "; origin=" .. wx .. "," .. wy)
    elseif self.action == "Remove" and spawned and spawned.world then world:removeLObject(spawned); world.exampleSpawn = nil
    elseif self.action == "Attach" and spawned and spawned.world then spawned:attachTo(spawned.parent and nil or self.target)
    elseif self.action == "Scripts" and spawned and spawned.world then
        local motion = spawned:getScriptByName("motion")
        if motion then motion.enabled = not motion.enabled end
    elseif self.action == "Camera" then
        local camera = world:getActiveCamera(); assert(world:setActiveCamera(camera)); camera.zoom = camera.zoom == 1 and 1.5 or 1
    elseif self.action == "Next" then assert(Engine.openLevel(world, self.nextLevel))
    elseif self.action == "Properties" and self.target then
        local motion = self.target:getScriptByName("motion")
        local class = require("Examples.Motion")
        assert(self.target:getScriptById(motion.id) == motion and self.target:getScriptByClass(class) == motion)
        world.debug:log("Matching scripts: " .. #self.target:getScriptsByClass(class))
        motion.enabled = not motion.enabled
        local t = self.target:getWorldTransform(); local x, y = Engine.Transform.point(t, 10, 10)
        world.debug:log("Property toggled; transformed point " .. x .. ", " .. y)
    else
        world.debug:point(0, 0, 5); world.debug:line(0, 0, 150, 100)
        world.debug:circle(0, 0, 90); world.debug:rect(-100, -60, 200, 120)
        world.debug:polygon({-80, -80, 80, -80, 0, 90})
        world.debug:screenLog("Debug shapes for 3 seconds", {key = "demo"})
    end
    return true
end
function Actions.onPointerUp(self, event) event.world.debug:log(self.action .. " pointer up"); return true end
function Actions.onPointerMove(self, event) self.hovered = event.inside; return true end
function Actions.drawEditor(self, context) context:bounds(self) end
return Actions
]]
function Examples.create(project)
    local operations = require("editor.PluginOperations")
    local folder = "Assets/Examples"
    if Fs.info(assert(project:resolvePath(folder))) then return false, "Assets/Examples already exists; its files are not overwritten" end
    for _, reference in ipairs({"Assets/L_ApiExamples.level", "Assets/L_ApiNext.level"}) do
        if Fs.info(assert(project:resolvePath(reference))) or project:getAssetId(reference) then return false, "Example level already exists: " .. reference end
    end
    assert(operations.apply(project, "LaboEssentials", true, true))
    assert(project:createEntry("Assets", "folder", "Examples"))
    for name, bytes in pairs({Motion = MOTION, Actions = ACTIONS, LevelDemo = LEVEL}) do
        assert(project:createEntry(folder, "lua", name, {scriptKind = name == "LevelDemo" and "level" or "script"}))
        assert(Fs.writeAtomic(assert(project:resolveSourceFile(folder .. "/" .. name .. ".lua")), bytes))
    end
    assert(project:rebuildAssetIndex())
    local motionId, actionsId = project:getAssetId(folder .. "/Motion.lua"), project:getAssetId(folder .. "/Actions.lua")
    local image = love.image.newImageData(48, 48)
    image:mapPixel(function(x, y) return x / 48, y / 48, 0.8, 1 end)
    local png = image:encode("png"); assert(Fs.createFile(assert(project:resolvePath(folder .. "/Tile.png")), png:getString())); png:release(); image:release()
    assert(project:rebuildAssetIndex())
    local imageId = project:getAssetId(folder .. "/Tile.png")
    assert(project:createEntry(folder, "prefab", "PF_Spawned"))
    local doc = assert(require("editor.PrefabDocument").load(project, folder .. "/PF_Spawned.prefab"))
    local editor = require("editor.PrefabEditor").new(project, doc, function() end, function() end)
    local motionAdded, motionAttachment = editor:addScript("root", motionId, "motion")
    assert(motionAdded, motionAttachment)
    local spriteAdded, spriteAttachment = editor:addScript("root", "Sprite", "sprite")
    assert(spriteAdded, spriteAttachment)
    doc.data.overrides.scripts = {[spriteAttachment] = {image = imageId}}
    assert(doc:save(project))
    assert(project:createEntry("Assets", "level", "L_ApiExamples", {empty = true}))
    assert(project:createEntry("Assets", "level", "L_ApiNext", {empty = true}))
    local Level = require("editor.Level")
    local level = Level.new()
    assert(level:setScriptReference(project:getAssetId(folder .. "/LevelDemo.lua")))
    local camera = level:addLObject(0, 0, nil, "Main Camera")
    camera.scripts = {{id = "camera", source = "Camera"}}; level.mainCamera = {authoringId = camera.authoringId, script = "camera"}
    local parent = level:addLObject(-160, 220, nil, "Motion and Property References")
    parent.scripts = {{id = "motion", source = motionId}, {id = "sprite", source = "Sprite"}, {id = "bounds", source = "RectBounds"}}
    parent.scriptOverrides = {sprite = {image = imageId}, motion = {sibling = {authoringId = parent.authoringId, script = "sprite"}}}
    local child = level:addLObject(90, 0, nil, "Inherited Transform Child"); child.parentAuthoringId = parent.authoringId
    child.scripts = {{id = "sprite", source = "Sprite"}}; child.scriptOverrides = {sprite = {image = imageId}}
    parent.scriptOverrides.motion.target = child.authoringId
    local canvas = level:addLObject(0, 0, nil, "Screen Space Canvas")
    canvas.scripts = {{id = "canvas", source = "Canvas"}}
    local title = level:addLObject(-340, -165, nil, "Screen Space Text")
    title.parentAuthoringId = canvas.authoringId; title.scripts = {{id = "text", source = "Text"}}
    title.scriptOverrides = {text = {text = "Labo API Examples\nClick a button to try each API", width = 680, align = "center", fontSize = 16, red = 0.15, green = 0.2, blue = 0.3}}
    for index, action in ipairs({"Spawn", "Remove", "Attach", "Scripts", "Camera", "Properties", "Debug", "Next", "Raw", "Bounds"}) do
        local button = level:addLObject(-190 + ((index - 1) % 2) * 380, -90 + math.floor((index - 1) / 2) * 50, nil, action .. " Button")
        button.parentAuthoringId = canvas.authoringId; button.scripts = {{id = "action", source = actionsId}}
        button.scriptOverrides = {action = {action = action, caption = action, template = doc.assetId, image = imageId,
            nextLevel = project:getAssetId("Assets/L_ApiNext.level"), target = parent.authoringId}}
    end
    local nextLevel = Level.new()
    assert(nextLevel:setScriptReference(level.scriptReference)); nextLevel.propertyOverrides = {welcome = "Second level - press Back"}
    nextLevel.lobjects = require("project.PrefabHierarchy").copy(level.lobjects)
    nextLevel.nextAuthoringId, nextLevel.mainCamera = level.nextAuthoringId, level.mainCamera
    for _, object in ipairs(nextLevel.lobjects) do if object.scriptOverrides and object.scriptOverrides.action and object.scriptOverrides.action.action == "Next" then
        object.scriptOverrides.action.caption = "Back"; object.scriptOverrides.action.nextLevel = project:getAssetId("Assets/L_ApiExamples.level")
    end end
    nextLevel.mainCamera = require("project.MainCamera").copy(level.mainCamera)
    assignScriptIds(level); assignScriptIds(nextLevel)
    assert(Fs.writeAtomic(assert(project:resolveAssetFile("Assets/L_ApiExamples.level")), assert(require("editor.LevelFile").encode(level))))
    assert(Fs.writeAtomic(assert(project:resolveAssetFile("Assets/L_ApiNext.level")), assert(require("editor.LevelFile").encode(nextLevel))))
    assert(project:rebuildAssetIndex())
    return true, {level = "Assets/L_ApiExamples.level", nextLevel = "Assets/L_ApiNext.level", folder = folder}
end
return Examples
