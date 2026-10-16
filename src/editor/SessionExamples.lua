local Examples = {}
local SOURCES = {
    TravelSession = [=[
local Json = require("Examples.SaveJson")
local Session = {properties = {
    levelA = {type = "string", default = ""}, levelB = {type = "string", default = ""},
    status = {type = "string", default = "No save loaded"},
}}
function Session:load()
    self.saveFile = "saves/" .. assert(self.owner.saveIdentity) .. "/slot1.json"
end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
function Session:validate(data)
    if type(data) ~= "table" or data.version ~= 1 then return false, "Unsupported save version" end
    if data.level ~= self.levelA and data.level ~= self.levelB then return false, "Unknown saved level" end
    local player = data.player
    if type(player) ~= "table" then return false, "Missing player data" end
    for _, key in ipairs({"hp", "gold", "keys", "x", "y"}) do
        if not finite(player[key]) then return false, "Invalid player field: " .. key end
    end
    if player.hp < 0 or player.hp > 100 or player.gold < 0 or player.keys < 0
        or player.gold % 1 ~= 0 or player.keys % 1 ~= 0 then return false, "Invalid player values" end
    return true
end
function Session:saveSlot(traveller, level)
    local data = {version = 1, level = level, player = {hp = traveller.hp, gold = traveller.gold, keys = traveller.keys,
        x = traveller.owner.transform.x, y = traveller.owner.transform.y}}
    local valid, err = self:validate(data)
    if not valid then self.status = err; return false, err end
    local directory = self.saveFile:match("^(.*)/")
    local made, makeError = love.filesystem.createDirectory(directory)
    if not made then self.status = makeError or "Could not create save directory"; return false, self.status end
    local encoded, encodeError = Json.encode(data)
    if not encoded then self.status = tostring(encodeError); return false, encodeError end
    local ok, writeError = love.filesystem.write(self.saveFile, encoded)
    self.status = ok and "Saved slot 1" or (writeError or "Could not write save file")
    return ok, writeError
end
function Session:loadSlot()
    local bytes, err = love.filesystem.read(self.saveFile)
    if not bytes then self.status = "Save missing: " .. tostring(err); return false, self.status end
    local data, decodeError = Json.decode(bytes)
    local valid, validationError = self:validate(data)
    if not valid then self.status = decodeError or validationError; return false, self.status end
    self.pendingRestore = data.player
    local ok, transitionError = self:getWorld():openLevel(data.level)
    if not ok then self.pendingRestore = nil end
    self.status = ok and "Loading slot 1" or tostring(transitionError)
    return ok, transitionError
end
return Session
]=],
    Traveller = [=[
local Engine = require("Engine")
local Traveller = {properties = {hp = {type = "number", default = 100}, gold = {type = "number", default = 0},
    keys = {type = "number", default = 0}, visits = {type = "number", default = 0}, token = {type = "number", default = 0}}}
function Traveller:load(world)
    self.currentWorld = world
    self.token = love.math.random(100000, 999999)
    self.camera = self.owner.children[1]:getScriptByName("camera")
    self.view = Engine.Rendering.createView(world, {owner = self, projection = function() return self.camera:getProjection() end})
end
function Traveller:worldChanged(previous, current)
    self.currentWorld = current
    self.visits = self.visits + 1
end
function Traveller:unload() self.view:release() end
function Traveller:update(dt)
    local t = self.owner.transform
    if love.keyboard.isDown("a", "left") then t.x = t.x - 180 * dt end
    if love.keyboard.isDown("d", "right") then t.x = t.x + 180 * dt end
end
function Traveller:draw()
    love.graphics.setColor(1, 0.55, 0.2, 1); love.graphics.rectangle("fill", -22, -32, 44, 64, 5, 5)
end
return Traveller
]=],
    TravelHud = [=[
local Engine = require("Engine")
local Hud = {properties = {drawOrder = {type = "number", default = 100}}}
function Hud:configure() Engine.Bounds.bind(self, function(context) return Engine.Bounds.of(self.owner, context) end) end
function Hud:load(world)
    local actor = self.owner.parent
    while actor and not actor:getScriptByName("traveller") do actor = actor.parent end
    self.actor = assert(actor):getScriptByName("traveller")
    Engine.Input.registerRegion(world, {owner = self, hitTest = function(context, x, y) return self:hitTest(context, x, y) end,
        onDown = function() self.actor.gold = self.actor.gold + 1; return true end})
end
function Hud:draw(context)
    local x, y, w, h = self:getBounds(context)
    love.graphics.setColor(0.12, 0.32, 0.48, 1); love.graphics.rectangle("fill", x, y, w, h, 5, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("CLICK: +1 GOLD | HP " .. self.actor.hp .. " | Gold " .. self.actor.gold .. " | Keys " .. self.actor.keys,
        x + 8, y + 16, w - 16, "center")
end
return Hud
]=],
    TravelStage = [=[
local Stage = {properties = {stageName = {type = "string", default = "A"}, level = {type = "string", default = ""},
    destination = {type = "string", default = ""}, failure = {type = "string", default = ""},
    playerPrefab = {type = "lobjectTemplate", default = false}}}
function Stage:load(world)
    self.session = assert(self:getProject():getScriptByName("travelSession"))
    for _, object in ipairs(world:getObjects()) do
        if object:getScriptByName("traveller") then self.player = object end
    end
    if not self.player then self.player = assert(world:spawnLObject(self.playerPrefab, {x = 0, y = 0})) end
    self.traveller = self.player:getScriptByName("traveller")
    local restored = self.session.pendingRestore
    if restored then
        self.traveller.hp, self.traveller.gold, self.traveller.keys = restored.hp, restored.gold, restored.keys
        self.player.transform.x, self.player.transform.y = restored.x, restored.y
        self.appliedRestore = restored
    end
end
function Stage:update()
    if self.appliedRestore and self.session.pendingRestore == self.appliedRestore then
        self.session.pendingRestore = nil; self.session.status = "Loaded slot 1"; self.appliedRestore = nil
    end
    local err = self:getWorld().levelTransitionError
    if err then self.session.status = "Transition failed; previous World retained" end
end
function Stage:keypressed(key)
    if key == "n" then assert(self:getWorld():openLevel(self.destination, {carry = {self.player}}))
    elseif key == "f" then assert(self:getWorld():openLevel(self.failure, {carry = {self.player}}))
    elseif key == "s" then self.session:saveSlot(self.traveller, self.level)
    elseif key == "l" then self.session:loadSlot()
    elseif key == "h" then self.traveller.hp = math.max(0, self.traveller.hp - 10)
    elseif key == "g" then self.traveller.gold = self.traveller.gold + 1
    elseif key == "k" then self.traveller.keys = self.traveller.keys + 1 end
end
function Stage:draw(context)
    love.graphics.setColor(self.stageName == "A" and 0.16 or 0.24, 0.18, 0.22, 1)
    for x = -2560, 2560, 80 do love.graphics.line(x, -1000, x, 1000) end
    for y = -1000, 1000, 80 do love.graphics.line(-2560, y, 2560, y) end
    context:withScreen(function()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("Stage " .. self.stageName .. " | Player instance " .. self.traveller.token .. " | World changes " .. self.traveller.visits,
            0, 100, context.viewport.width, "center")
        love.graphics.printf("A/D move | N travel | F fail travel | H damage | G gold | K key | S save | L load",
            0, context.viewport.height - 78, context.viewport.width, "center")
        love.graphics.printf(self.session.status, 0, context.viewport.height - 46, context.viewport.width, "center")
    end)
end
return Stage
]=],
    TravelFailure = [=[
local Failure = {}
function Failure:load() error("Intentional destination initialization failure") end
return Failure
]=],
}
function Examples.create(project)
    local Fs, Json, Id = require("editor.HostFileSystem"), require("project.Json"), require("project.AssetId")
    local folder = "Assets/Examples"
    local names = {"TravelSession", "Traveller", "TravelHud", "TravelStage", "TravelFailure", "SaveJson"}
    local paths = {}
    for _, name in ipairs(names) do paths[#paths + 1] = folder .. "/" .. name .. ".lua" end
    for _, name in ipairs({"PF_Traveller.prefab", "L_TravelA.level", "L_TravelB.level", "L_TravelFailure.level"}) do paths[#paths + 1] = folder .. "/" .. name end
    for _, path in ipairs(paths) do assert(not project:getAssetId(path) and not Fs.info(assert(project:resolvePath(path))), "Session example already exists: " .. path) end
    for _, script in ipairs(project.scripts or {}) do assert(script.name ~= "travelSession", "travelSession is already attached") end
    assert(require("editor.PluginOperations").apply(project, "LaboEssentials", true, true))
    if not Fs.info(assert(project:resolvePath(folder))) then assert(project:createEntry("Assets", "folder", "Examples")) end
    local ids = {}
    for _, name in ipairs(names) do
        assert(project:createEntry(folder, "lua", name, {scriptKind = "script"}))
        ids[name] = assert(project:getAssetId(folder .. "/" .. name .. ".lua"))
        local source = name == "SaveJson" and assert(love.filesystem.read("project/Json.lua")) or SOURCES[name]
        assert(Fs.writeAtomic(assert(project:resolveSourceFile(ids[name])), source))
    end
    assert(project:rebuildAssetIndex())
    local function attachment(name, source) return {id = Id.new(), name = name, source = source} end
    local camera = attachment("camera", project.plugins.scripts.Camera.id)
    local layout = attachment("layout", project.plugins.scripts.RectLayout.id)
    local prefab = {formatVersion = 4, name = "PF_Traveller", scripts = {attachment("traveller", ids.Traveller)}, overrides = {scripts = {}}, children = {
        {id = "camera", name = "Camera", scripts = {camera}, overrides = {scripts = {}}, children = {
            {id = "hud", name = "HUD", scripts = {attachment("canvas", project.plugins.scripts.Canvas.id)}, overrides = {scripts = {}}, children = {
                {id = "button", name = "Gold button", transform = {x = 20, y = 20},
                    scripts = {layout, attachment("hud", ids.TravelHud)},
                    overrides = {scripts = {[layout.id] = {width = 550, height = 52, anchor = "topLeft", pivot = "topLeft"}}}}
            }},
        }},
    }}
    assert(project:createEntry(folder, "prefab", "PF_Traveller", {prefabData = prefab}))
    local prefabId = assert(project:getAssetId(folder .. "/PF_Traveller.prefab"))
    for _, name in ipairs({"L_TravelA", "L_TravelB", "L_TravelFailure"}) do
        assert(project:createEntry(folder, "level", name)); ids[name] = assert(project:getAssetId(folder .. "/" .. name .. ".level"))
    end
    for _, label in ipairs({"A", "B"}) do
        local level = require("editor.Level").new(); local stage = attachment("stage", ids.TravelStage)
        level.scripts = {stage}; level.scriptOverrides = {[stage.id] = {stageName = label, level = ids["L_Travel" .. label],
            destination = ids[label == "A" and "L_TravelB" or "L_TravelA"], failure = ids.L_TravelFailure, playerPrefab = prefabId}}
        assert(Fs.writeAtomic(assert(project:resolveAssetFile(ids["L_Travel" .. label])), assert(require("editor.LevelFile").encode(level))))
    end
    local failure = require("editor.Level").new(); failure.scripts = {attachment("failure", ids.TravelFailure)}
    assert(Fs.writeAtomic(assert(project:resolveAssetFile(ids.L_TravelFailure)), assert(require("editor.LevelFile").encode(failure))))
    local target = assert(require("project.ScopedScripts").inspectorTarget(project, project, nil, "Project"))
    assert(target:addScript(ids.TravelSession, "travelSession"))
    local session = project.scripts[#project.scripts]
    project.scriptOverrides[session.id] = {levelA = ids.L_TravelA, levelB = ids.L_TravelB}
    assert(project:saveScripts()); assert(project:rebuildAssetIndex())
    return {level = ids.L_TravelA, nextLevel = ids.L_TravelB, failureLevel = ids.L_TravelFailure, prefab = prefabId}
end
return Examples
