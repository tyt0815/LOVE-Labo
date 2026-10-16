local Assert = require("tests.Assert")
local Rendering = require("core.Rendering")
local Pipeline = setmetatable({}, {__index = require("core.RenderPipeline")})
function Pipeline.pointer(world, ...)
    require("tests.pointerFixture").bindWorld(world)
    return require("core.RenderPipeline").pointer(world, ...)
end
local function projection(source)
    return function() if source.owner and source.enabled ~= false then return source:getProjection() end end
end
local Runtime = require("core.ScriptRuntime")
local Script = require("core.Script")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function object(world, x)
    return assert(world:addLObject({transform = {x = x or 0, y = 0}}))
end
local function camera(world, x, width, height)
    return Runtime.attach(object(world, x), "camera", require("plugins.LaboEssentials.Assets.Camera"),
        {viewWidth = width or 100, viewHeight = height or 100})
end
local function render(world, canvas)
    love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear(0, 0, 0, 0)
    local ok, err = pcall(Pipeline.draw, world, function() end, 0, 0, canvas:getDimensions())
    love.graphics.pop(); assert(ok, err)
end
add("Views render registered cameras to screen and texture without multiplying updates", function()
    local world = require("core.World").new()
    local near, far = camera(world, 0), camera(world, 100)
    local actor = Runtime.attach(object(world), "actor", Script:extend({
        update = function(self) self.updates = (self.updates or 0) + 1 end,
        draw = function(self, ctx)
            self.draws = (self.draws or 0) + 1
            assert(ctx.projection and ctx.view and ctx.target)
            love.graphics.setColor(1, 0, 0, 1); love.graphics.rectangle("fill", -10, -10, 20, 20)
        end
    }))
    local hud = Runtime.attach(object(world), "hud", Script:extend({draw = function(self)
        self.draws = (self.draws or 0) + 1
    end}))
    local canvas = love.graphics.newCanvas(100, 100)
    render(world, canvas); Assert.equal(nil, actor.draws)
    local target = Rendering.createTarget(world, {width = 100, height = 100})
    local map = Rendering.createView(world, {projection = projection(far), target = target, filter = function(script) return script ~= hud end, order = -1})
    local main = Rendering.createView(world, {projection = projection(near)})
    assert(world:update(0.1)); render(world, canvas)
    Assert.equal(1, actor.updates); Assert.equal(2, actor.draws); Assert.equal(1, hud.draws)
    local pixels, mapPixels = canvas:newImageData(), target:getTexture():newImageData()
    Assert.equal(1, pixels:getPixel(50, 50)); Assert.equal(0, mapPixels:getPixel(50, 50))
    pixels:release(); mapPixels:release()
    near.zoom = 2
    local vp = Pipeline.primaryViewport(world, 0, 0, 100, 100)
    Assert.equal(2, vp.scale); Assert.equal(70, vp:worldToScreen(10, 0))
    main:setProjection(projection(far)); Assert.equal(100, Pipeline.primaryViewport(world, 0, 0, 100, 100).projection.transform.x)
    map:setEnabled(false); assert(world:dispose()); Assert.truthy(target.released and map.released and main.released)
    Assert.equal(0, #world.renderViews); Assert.equal(0, #world.renderTargets); canvas:release()
end)
add("View composition samples earlier targets and rejects feedback while restoring graphics state", function()
    local world = require("core.World").new()
    local target = Rendering.createTarget(world, {width = 16, height = 16})
    local writer = Rendering.createView(world, {target = target, filter = function() return false end, order = -1, clearColor = {0, 1, 0, 1}})
    Rendering.createView(world)
    Runtime.attach(object(world), "hud", Script:extend({draw = function(_, context)
        context:withScreen(function() love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(target:getTexture(), 0, 0) end)
    end}))
    local canvas = love.graphics.newCanvas(32, 32)
    render(world, canvas)
    local pixels = canvas:newImageData(); local _, green = pixels:getPixel(4, 4); Assert.equal(1, green); pixels:release()
    writer.filter = nil
    local before = love.graphics.getCanvas()
    local ok, err = pcall(render, world, canvas)
    Assert.equal(false, ok); Assert.truthy(err:find("currently being written", 1, true))
    Assert.equal(before, love.graphics.getCanvas()); Assert.equal(nil, target.writing)
    writer.filter = function() return false end; target:resize(32, 16); Assert.equal(32, target:getTexture():getWidth())
    assert(world:dispose()); canvas:release()
end)
add("Views isolate owners targets filters and pointer capture across multiple screen regions", function()
    local world, other = require("core.World").new(), require("core.World").new()
    local cam = camera(world)
    Assert.equal(false, pcall(Rendering.createView, other, {camera = cam}))
    local target = Rendering.createTarget(world, {width = 16, height = 16})
    Assert.equal(false, pcall(Rendering.createView, other, {target = target}))
    local a, b = object(world), object(world, 100)
    local pointerClass = Script:extend({getLocalBounds = function() return -50, -50, 100, 100 end,
        onPointerDown = function(self) self.downs = (self.downs or 0) + 1; return true end,
        onPointerUp = function(self, event) self.up = true; self.inside = event.inside; return true end})
    local first, second = Runtime.attach(a, "a", pointerClass), Runtime.attach(b, "b", pointerClass)
    local left = Rendering.createView(world, {projection = projection(cam), viewport = {x = 0, y = 0, width = 100, height = 100},
        filter = function(script) return script.owner == a end})
    Rendering.createView(world, {projection = projection(camera(world, 100)), viewport = {x = 100, y = 0, width = 100, height = 100},
        filter = function(script) return script.owner == b end})
    local rect = {x = 0, y = 0, width = 200, height = 100}
    assert(Pipeline.pointer(world, "down", 50, 50, 1, 0, 0, function() end, rect))
    Assert.equal(1, first.downs); Assert.equal(nil, second.downs)
    assert(Pipeline.pointer(world, "up", 150, 50, 1, 0, 0, function() end, rect))
    Assert.truthy(first.up); Assert.equal(false, first.inside)
    assert(Pipeline.pointer(world, "down", 150, 50, 1, 0, 0, function() end, rect)); Assert.equal(1, second.downs)
    assert(world:removeLObject(cam.owner)); Assert.equal(false, left:isActive())
    world:cancelPointer(); assert(world:dispose()); assert(other:dispose())
end)
add("Unmigrated camera selection never creates implicit Runtime output", function()
    local world = require("core.World").new()
    camera(world); Assert.equal(0, #Rendering.views(world)); Assert.equal(nil, world.getActiveCamera)
    assert(world:dispose())
end)
add("Provided View tolerates removed unchanged cameras and accepts valid replacements", function()
    local world, other = require("core.World").new(), require("core.World").new()
    local first = camera(world)
    local owner = object(world)
    local script = Runtime.attach(owner, "view", require("plugins.LaboEssentials.Assets.View"))
    script.cameraSource = first
    assert(owner:load(world))
    assert(world:removeLObject(first.owner))
    assert(world:update(0.1)); Assert.equal(0, #Rendering.views(world))
    local replacement = camera(world, 100)
    script.cameraSource = replacement
    assert(world:update(0.1)); Assert.equal(100, Rendering.views(world)[1]:getProjection().transform.x)
    script.cameraSource = camera(other)
    local ok, err = world:update(0.1)
    Assert.equal(true, ok); Assert.equal(0, #Rendering.views(world))
    script.cameraSource = replacement
    assert(world:update(0.1)); assert(world:dispose()); assert(other:dispose())
end)
add("Inactive View owners cancel captures before reactivation and allow other screen input", function()
    local world = require("core.World").new()
    local owner = Runtime.attach(object(world), "owner", Script)
    local a, b = object(world), object(world)
    local pointer = Script:extend({
        getLocalBounds = function() return -50, -50, 100, 100 end,
        onPointerDown = function() return true end,
        onPointerMove = function(self) self.moves = (self.moves or 0) + 1; return true end
    })
    local first, second = Runtime.attach(a, "a", pointer), Runtime.attach(b, "b", pointer)
    local left = Rendering.createView(world, {owner = owner, viewport = {x = 0, y = 0, width = 100, height = 100},
        filter = function(script) return script.owner == a end})
    Rendering.createView(world, {viewport = {x = 100, y = 0, width = 100, height = 100},
        filter = function(script) return script.owner == b end})
    local rect = {x = 0, y = 0, width = 200, height = 100}
    assert(Pipeline.pointer(world, "down", 50, 50, 1, 0, 0, function() end, rect))
    Assert.equal(first, left.pointerCaptures[1].owner)
    owner.enabled = false
    assert(Pipeline.pointer(world, "up", 50, 50, 1, 0, 0, function() end, rect))
    Assert.equal(nil, next(left.pointerCaptures))
    owner.enabled = true
    assert(Pipeline.pointer(world, "move", 150, 50, 1, 0, 0, function() end, rect))
    Assert.equal(nil, first.moves); Assert.equal(1, second.moves)
    assert(world:dispose())
end)
add("Rendering CLI uses registered views and creates an actual minimap image", function()
    local Fs = require("editor.HostFileSystem")
    local project = assert(require("editor.Project").create(Fs.join(love.filesystem.getSourceBaseDirectory(), "build"),
        "Rendering_" .. os.time() .. "_" .. love.math.random(100000, 999999)))
    local example = require("editor.RenderingExamples").create(project)
    local result = require("editor.Cli").execute({command = "level.render", project = project.rootPath,
        level = example.level, width = 640, height = 360, output = Fs.join(project.rootPath, "render.png")})
    Assert.equal(2, #result.views); Assert.equal("texture", result.views[1].target)
    Assert.equal("screen", result.views[2].target); Assert.equal(1, result.scale)
    local pixels = love.image.newImageData(love.filesystem.newFileData(assert(Fs.read(result.output)), "render.png"))
    Assert.equal(640, pixels:getWidth()); Assert.equal(360, pixels:getHeight()); pixels:release()
end)
return tests
