local Assert = require("tests.Assert")
local Engine, Runtime = require("Engine"), require("core.ScriptRuntime")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function fixture()
    local project = {
        getAssetReference = function(_, reference) return reference end, getAssetId = function() end,
        readAsset = function(_, reference)
            return assert(require("project.Json").encode({formatVersion = 3, lobjects = {},
                scriptReference = reference == "Assets/Fail.level" and "Assets/Fail.lua" or nil}))
        end,
        getScriptKind = function() return "level" end, resolveSourceFile = function() return "Assets/Fail.lua" end,
        readSource = function() return "return {load = function() error('destination failed') end}" end,
    }
    return assert(require("runtime.WorldLoader").create(project, {lobjects = {}}))
end
local function object(world, parent)
    local value = assert(world:addLObject({transform = {x = 10, y = 20}}))
    if parent then value:attachTo(parent) end
    return value
end
add("Carry preserves object and script identity resources and one-time lifecycle across repeated levels", function()
    local world = fixture(); local oldParent = object(world); oldParent.transform.x = 100
    local player = object(world, oldParent); local child = object(world, player)
    local loaded, unloaded, changed, clicked = 0, 0, 0, 0
    local script = Runtime.attach(player, "player", Engine.Script:extend({
        load = function() loaded = loaded + 1 end, unload = function() unloaded = unloaded + 1 end,
        worldChanged = function(self, previous, nextWorld) self.current = nextWorld; changed = changed + 1 end,
        update = function(self) self.ticks = (self.ticks or 0) + 1 end,
    }))
    assert(player:load(world)); script.inventory = {gold = 5}
    local target = Engine.Rendering.createTarget(world, {owner = script, width = 32, height = 32})
    local view = Engine.Rendering.createView(world, {owner = script, target = target})
    local screen = Engine.Rendering.createView(world, {owner = script})
    local region = Engine.Input.registerRegion(world, {owner = script, hitTest = function() return true, 0, 0 end,
        onDown = function() clicked = clicked + 1; return true end})
    for _ = 1, 3 do
        screen.pointerCaptures[1] = region
        assert(world:openLevel("Assets/Next.level", {carry = {player, child, player}}))
        Assert.equal(world, player.world)
        local nextWorld = assert(world:takeLevelTransition())
        Assert.equal(true, world.disposed); Assert.equal(false, target.released == true)
        Assert.equal(2, #nextWorld.lobjects); Assert.equal(player, nextWorld.lobjects[1]); Assert.equal(child, player.children[1])
        Assert.equal(nil, player.parent); Assert.equal(110, player.transform.x)
        Assert.equal(script, player:getScriptByName("player")); Assert.equal(5, script.inventory.gold)
        Assert.equal(nextWorld, script.current); Assert.equal(nextWorld, view.world); Assert.equal(nextWorld, region.world)
        Assert.equal(nextWorld, target.world); Assert.equal(nil, next(screen.pointerCaptures))
        assert(nextWorld:update(0.1)); assert(nextWorld:dispatchPointer("down", 0, 0, 1))
        world = nextWorld
    end
    Assert.equal(1, loaded); Assert.equal(0, unloaded); Assert.equal(3, changed); Assert.equal(3, clicked); Assert.equal(3, script.ticks)
    assert(world:dispose()); Assert.equal(1, unloaded); Assert.equal(true, region.released); Assert.equal(true, target.released)
end)
add("Failed destination restores carried hierarchy IDs registrations and new binding cleanup", function()
    local world = fixture(); local parent = object(world)
    local before = object(world, parent); local player = object(world, parent); local after = object(world, parent)
    local originalTransform = player.transform; local calls = 0
    local script = Runtime.attach(player, "player", Engine.Script:extend({worldChanged = function(self, previous, nextWorld)
        calls = calls + 1
        if nextWorld ~= world then
            Engine.Input.registerRegion(nextWorld, {owner = self, hitTest = function() return false end})
        end
    end}))
    assert(player:load(world))
    local region = Engine.Input.registerRegion(world, {owner = script, hitTest = function() return true end})
    local view = Engine.Rendering.createView(world, {owner = script})
    local id, runtimeId = player.authoringId, player.runtimeId
    assert(world:openLevel("Assets/Fail.level", {carry = {player}}))
    local nextWorld, err = world:takeLevelTransition()
    Assert.equal(nil, nextWorld); Assert.truthy(err:find("destination failed", 1, true)); Assert.equal(2, calls)
    Assert.equal(world, player.world); Assert.equal(parent, player.parent); Assert.equal(originalTransform, player.transform)
    Assert.equal(before, parent.children[1]); Assert.equal(player, parent.children[2]); Assert.equal(after, parent.children[3])
    Assert.equal(runtimeId, player.runtimeId); Assert.equal(id, player.authoringId); Assert.equal(script, player.scripts.player)
    Assert.equal(1, #world.inputRegions); Assert.equal(region, world.inputRegions[1]); Assert.equal(1, #script.bindingHandles)
    Assert.equal(world, view.world); Assert.equal(true, view:isActive()); Assert.equal(nil, player.transferPending)
    assert(world:update(0.1)); assert(world:dispose())
end)
add("Carry rejects foreign removed objects and render targets shared with abandoned Views", function()
    local world, foreign = fixture(), fixture(); local player = object(world); local outsider = object(foreign)
    Assert.equal(false, world:openLevel("Assets/Next.level", {carry = {outsider}}))
    local script = Runtime.attach(player, "player", Engine.Script:extend({})); assert(player:load(world))
    local target = Engine.Rendering.createTarget(world, {width = 32, height = 32})
    Engine.Rendering.createView(world, {owner = script, target = target}); Engine.Rendering.createView(world, {target = target})
    assert(world:openLevel("Assets/Next.level", {carry = {player}}))
    local nextWorld, err = world:takeLevelTransition()
    Assert.equal(nil, nextWorld); Assert.truthy(err:find("shared", 1, true)); Assert.equal(world, player.world)
    assert(world:removeLObject(player))
    Assert.equal(false, world:openLevel("Assets/Next.level", {carry = {player}}))
    assert(world:dispose()); assert(foreign:dispose())
end)
add("Carry movement failure restores objects before any destination load", function()
    local world = fixture(); local parent = object(world); local player = object(world, parent)
    Runtime.attach(player, "readOnly", Engine.Script:extend({configure = function(self)
        Engine.Transform.bindLocal(player, {owner = self, resolve = function(value) return value end})
    end}))
    assert(world:openLevel("Assets/Next.level", {carry = {player}}))
    local nextWorld, err = world:takeLevelTransition()
    Assert.equal(nil, nextWorld); Assert.truthy(err:find("read-only", 1, true))
    Assert.equal(world, player.world); Assert.equal(parent, player.parent); Assert.equal(2, #world.lobjects)
    assert(world:dispose())
end)
add("Project-owned rendering and input follow level replacement without carried objects", function()
    local world = fixture()
    local script = Runtime.attach(world.project, "global", Engine.Script:extend({}))
    local view = Engine.Rendering.createView(world, {owner = script})
    local region = Engine.Input.registerRegion(world, {owner = script, hitTest = function() return true end})
    assert(world:openLevel("Assets/Next.level")); local nextWorld = assert(world:takeLevelTransition())
    Assert.equal(nextWorld, view.world); Assert.equal(true, view:isActive()); Assert.equal(true, region:isActive())
    region:release(); Assert.equal(0, #nextWorld.inputRegions); assert(nextWorld:dispose())
end)
add("worldChanged rejection rolls back and carried structure remains protected during initialization", function()
    local world = fixture(); local player = object(world)
    local script = Runtime.attach(player, "guard", Engine.Script:extend({worldChanged = function(self, previous, nextWorld)
        if nextWorld == world then return end
        Assert.equal(false, nextWorld:removeLObject(player))
        Assert.equal(false, nextWorld:dispose())
        Assert.equal(false, previous:dispose())
        Assert.equal(false, pcall(Runtime.detach, player, "guard"))
        Assert.equal(false, pcall(player.attachTo, player, nil))
        return false, "transfer rejected"
    end}))
    assert(player:load(world)); assert(world:openLevel("Assets/Next.level", {carry = {player}}))
    local nextWorld, err = world:takeLevelTransition()
    Assert.equal(nil, nextWorld); Assert.truthy(err:find("transfer rejected", 1, true)); Assert.equal(world, player.world)
    Assert.equal(nil, player.transferPending); Assert.equal(script, player.scripts.guard)
    assert(world:dispose())
end)
add("Stopping a pending transition disposes its prepared World without unloading carried objects twice", function()
    local world = fixture(); local player = object(world)
    local unloads = 0
    Runtime.attach(player, "life", Engine.Script:extend({unload = function() unloads = unloads + 1 end}))
    assert(player:load(world)); assert(world:openLevel("Assets/Next.level", {carry = {player}}))
    local candidate = world.pendingLevel.world
    assert(world:dispose()); Assert.equal(true, candidate.disposed); Assert.equal(1, unloads)
end)
add("Inverse layout evaluation sees the destination as both object and Project World", function()
    local world = fixture(); local player = object(world)
    Runtime.attach(player, "layout", Engine.Script:extend({configure = function(self)
        Engine.Transform.bindLocal(player, {owner = self,
            resolve = function(value) return value end,
            unresolve = function(value)
                Assert.equal(self:getWorld(), self:getProject():getWorld())
                return value
            end})
    end}))
    assert(player:load(world)); assert(world:openLevel("Assets/Next.level", {carry = {player}}))
    local nextWorld = assert(world:takeLevelTransition()); Assert.equal(nextWorld, nextWorld.project:getWorld())
    assert(nextWorld:dispose())
end)
add("Provided Camera and View retain projection and input through carry success and rollback", function()
    local world = fixture(); local player = object(world)
    local camera = Runtime.attach(player, "camera", require("plugins.LaboEssentials.Assets.Camera"))
    local script = Runtime.attach(player, "view", require("plugins.LaboEssentials.Assets.View"))
    script.cameraSource = camera; assert(player:load(world))
    local view, clicks = script.renderView, 0
    Engine.Input.registerRegion(world, {owner = camera, hitTest = function() return true, 0, 0 end,
        onDown = function() clicks = clicks + 1; return true end})
    for _, destination in ipairs({"Assets/Next.level", "Assets/Fail.level", "Assets/Next.level"}) do
        assert(world:openLevel(destination, {carry = {player}}))
        local candidate, err = world:takeLevelTransition()
        if destination == "Assets/Fail.level" then
            Assert.equal(nil, candidate); Assert.truthy(err:find("destination failed", 1, true))
        else world = assert(candidate) end
        Assert.equal(view, script.renderView); Assert.equal(world, view.world); Assert.equal(true, view:isActive())
        Assert.equal(1280, view:getProjection().width)
        local ok, response = require("core.RenderPipeline").pointer(world, "down", 400, 300, 1, 0, 0,
            function() end, {x = 0, y = 0, width = 800, height = 600})
        Assert.equal(true, ok); Assert.equal(true, response.consumed)
    end
    Assert.equal(3, clicks); assert(world:dispose())
end)

return tests
