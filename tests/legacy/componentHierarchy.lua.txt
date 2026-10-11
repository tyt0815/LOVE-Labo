local A = require("tests.Assert")
local Object = require("core.LObject")
local Component = require("core.LObjectComponent")
local Scene = require("core.SceneComponent")
local Sprite = require("core.SpriteComponent")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function object() return assert(Object.new(1, {transform = {x = 100, y = 200}})) end

add("Component attachments form a root-first hierarchy and inherit ancestor positions", function()
    local owner = object()
    local root = owner.rootComponent
    A.truthy(root:isA(Scene)); A.equal("root", root.name)
    root.properties.x = 10
    local arm = root:addComponent("arm", Scene, {x = 20, y = 30})
    local logic = arm:addComponent("logic", Component)
    local hand = logic:addComponent("hand", Sprite, {x = 5, y = 7})
    owner:addComponent("other", Scene)
    A.equal("root,arm,logic,hand,other", table.concat(owner:getComponentOrder(), ","))
    local x, y = hand:getWorldPosition(); A.equal(35, x); A.equal(237, y)
    owner.transform.rotation = 90
    x, y = hand:getWorldPosition()
    A.truthy(math.abs(x + 27) < 0.00001); A.truthy(math.abs(y - 225) < 0.00001)
    hand:attachTo("other"); A.equal(owner.components.other, hand.parent)
    A.equal(0, #logic.children)
end)

add("Invalid attachment and failed component builds preserve the previous hierarchy", function()
    local owner, foreign = object(), object()
    local arm = owner:addComponent("arm", Scene)
    local child = arm:addComponent("child", Scene)
    for _, action in ipairs({
        function() arm:attachTo(child) end,
        function() child:attachTo(foreign.rootComponent) end,
        function() child:attachTo("missing") end,
        function() owner.rootComponent:attachTo(child) end,
        function() owner:addComponent("wrong", Scene, nil, "missing") end,
        function() owner:setRootComponent("bad", Component) end,
        function() owner:setRootComponent("root", Scene:extend({build = function(self)
            self:addComponent("temporary", Scene); error("expected build failure")
        end})) end
    }) do
        A.equal(false, pcall(action))
        A.equal("root,arm,child", table.concat(owner:getComponentOrder(), ","))
        A.equal(arm, child.parent); A.equal(nil, owner.components.temporary)
    end
end)

add("Root replacement keeps descendants and supports existing or same-name custom roots", function()
    local owner = object()
    local old = owner.rootComponent
    local arm = owner:addComponent("arm", Scene)
    local hand = arm:addComponent("hand", Sprite)
    local root = owner:setRootComponent("root", Sprite, {x = 8})
    A.equal(nil, old.owner); A.equal(root, arm.parent)
    A.equal("root,arm,hand", table.concat(owner:getComponentOrder(), ","))
    owner:setRootComponent(hand)
    A.equal(hand, owner.rootComponent); A.equal(hand, root.parent); A.equal(root, arm.parent)
    local newRoot = owner:setRootComponent("hand", Scene)
    A.equal(nil, hand.owner); A.equal(newRoot, root.parent)
    A.equal("hand,root,arm", table.concat(owner:getComponentOrder(), ","))
end)

add("Runtime component construction begins parent before children exactly once", function()
    local owner, calls = object(), {}
    assert(owner:beginPlay({}))
    local Child = Component:extend({beginPlay = function(self) calls[#calls + 1] = self.name end})
    local Parent = Scene:extend({
        build = function(self) self:addComponent("child", Child) end,
        beginPlay = function(self) calls[#calls + 1] = self.name end
    })
    owner:addComponent("parent", Parent)
    A.equal("parent,child", table.concat(calls, ","))
    owner:setRootComponent("replacement", Parent:extend({build = function() end}))
    A.equal("parent,child,replacement", table.concat(calls, ","))
end)

add("Components attached during initial beginPlay also initialize once", function()
    local owner, calls = object(), {}
    local Child = Component:extend({beginPlay = function(self) calls[#calls + 1] = self.name end})
    owner:setRootComponent("root", Scene:extend({beginPlay = function(self)
        calls[#calls + 1] = self.name
        self:addComponent("late", Child)
    end}))
    assert(owner:beginPlay({}))
    A.equal("root,late", table.concat(calls, ","))
    A.equal(true, owner.components.late.hasBegunPlay)
end)

add("Nested Sprite render hit and outline share the inherited component position", function()
    local owner = object()
    local branch = owner:addComponent("branch", Scene, {x = 40, y = 20})
    branch:addComponent("sprite", Sprite, {x = 10, image = "image"})
    local pixels = love.image.newImageData(8, 8)
    local image = love.graphics.newImage(pixels); pixels:release()
    local Renderer = require("core.SpriteRenderer")
    A.equal(true, Renderer.hit(owner, function() return image end, 150, 220))
    A.equal(false, Renderer.hit(owner, function() return image end, 110, 200))
    local canvas = love.graphics.newCanvas(250, 250)
    love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear()
    assert(Renderer.draw(owner, function() return image end, function(x, y) return x, y end, 1))
    local points
    Renderer.outline(owner, function() return image end, function(x, y)
        points = points or {}; points[#points + 1] = {x, y}; return x, y
    end)
    love.graphics.pop(); canvas:release(); image:release()
    A.equal(146, points[1][1]); A.equal(216, points[1][2]); A.equal(154, points[3][1])
end)

add("Component tree selects grandchildren, expands ancestors and scrolls independently", function()
    local owner = object()
    local arm = owner:addComponent("object", Scene)
    local child = arm:addComponent("child", Scene)
    local chosen
    local tree = require("editor.ui.ComponentTree").new(owner, "Actor", function(name) chosen = name end)
    tree:setBounds(0, 0, 300, 52); tree:clampScroll()
    A.equal(3, tree.nodes[4].depth)
    tree.expanded[false] = false; tree:rebuild(); A.equal(1, #tree.nodes)
    tree:reveal("child"); A.equal(4, #tree.nodes); A.equal(2, tree.scroll)
    tree:dispatch("keypressed", "up"); A.equal("object", chosen)
    tree:dispatch("keypressed", "left"); A.equal(3, #tree.nodes)
    tree:dispatch("keypressed", "right"); A.equal(4, #tree.nodes)
    A.equal(child, owner.components.child)
end)
add("beginPlay root replacement does not reenter the preserved old root", function()
    local owner, calls = object(), {}
    local Child = Component:extend({beginPlay = function(self) calls[#calls + 1] = self.name end})
    local NewRoot = Scene:extend({beginPlay = function(self) calls[#calls + 1] = self.name end})
    owner:setRootComponent("custom", Scene:extend({beginPlay = function(self)
        calls[#calls + 1] = self.name
        self.owner:setRootComponent("replacement", NewRoot)
    end}))
    owner.rootComponent:addComponent("child", Child)
    assert(owner:beginPlay({}))
    A.equal("custom,replacement,child", table.concat(calls, ","))
    A.equal(owner.rootComponent, owner.components.custom.parent)
    A.equal(nil, owner.components.custom.beginningPlay)
    A.equal(true, owner.components.custom.hasBegunPlay)
end)

add("Runtime build initializes components added outside its own subtree before update", function()
    local owner, calls = object(), {}
    assert(owner:beginPlay({}))
    local Child = Component:extend({
        beginPlay = function(self) calls[#calls + 1] = self.name; self.ready = true end,
        update = function(self) A.equal(true, self.ready) end
    })
    owner:addComponent("parent", Scene:extend({
        build = function(self)
            self.owner:addComponent("sibling", Child)
            self:addComponent("child", Child)
        end,
        beginPlay = function(self) calls[#calls + 1] = self.name end
    }))
    A.equal("parent,child,sibling", table.concat(calls, ","))
    A.equal(owner.rootComponent, owner.components.sibling.parent)
    assert(owner:update(0.1) ~= false)
    owner:addComponent("other", Component)
    A.equal("parent,child,sibling", table.concat(calls, ","))
end)

add("Failed beginPlay clears initialization guards for a later retry", function()
    local owner, attempts = object(), 0
    owner:setRootComponent("custom", Scene:extend({beginPlay = function()
        attempts = attempts + 1
        if attempts == 1 then error("expected initialization failure") end
    end}))
    A.equal(false, owner:beginPlay({}))
    A.equal(nil, owner.initializingComponents); A.equal(nil, owner.rootComponent.beginningPlay)
    assert(owner:beginPlay({})); A.equal(2, attempts)
end)

add("Fractional component tree wheel input keeps rows drawable and clickable", function()
    local owner = object()
    for i = 1, 10 do owner:addComponent("child" .. i, Scene) end
    local chosen
    local tree = require("editor.ui.ComponentTree").new(owner, "Actor", function(name) chosen = name end)
    tree:setBounds(0, 0, 300, 78)
    local Ui, count = require("editor.Ui"), 0
    local original = Ui.text
    Ui.text = function(...) count = count + 1; return original(...) end
    local ok, err = pcall(function()
        for _, amount in ipairs({-0.1, -0.5, -1.25, 0.1, 0.5, 1.25}) do
            tree:dispatch("wheelmoved", 100, 10, amount)
            A.equal(math.floor(tree.scroll), tree.scroll)
            count = 0; tree:draw(); A.equal(3, count)
            tree:dispatch("mousepressed", 200, 13, 1)
            A.equal(tree.nodes[tree.scroll + 1].key or nil, chosen)
        end
    end)
    Ui.text = original; assert(ok, err)
end)
add("Root Transform is the LObject Transform through both APIs and root replacement", function()
    local owner = object()
    A.equal(owner.transform, owner.rootComponent.transform)
    owner.rootComponent.properties.x = 42; A.equal(42, owner.transform.x)
    owner.transform.y = -20; A.equal(-20, owner.rootComponent.properties.y)
    owner.rootComponent.properties.rotation = -30; A.equal(330, owner.transform.rotation)
    local old = owner.rootComponent
    local new = owner:setRootComponent("sprite", Sprite, {x = 999, scaleX = 3})
    A.equal(42, new.transform.x); A.equal(-20, new.transform.y); A.equal(1, new.transform.scaleX)
    A.equal(nil, old.owner); A.equal(owner.transform, new.transform)
    owner.transform = {x = 8, y = 9, scaleY = 2}
    A.equal(8, new.properties.x); A.equal(2, new.properties.scaleY)
    A.equal(nil, rawget(owner, "transform"))
end)

add("Descendant Transform composes parent rotation and scale through nonspatial components", function()
    local owner = object()
    owner.transform.rotation = 90
    local branch = owner:addComponent("branch", Scene, {x = 10, rotation = 90, scaleX = 2, scaleY = 3})
    local logic = branch:addComponent("logic", Component)
    local leaf = logic:addComponent("leaf", Sprite, {x = 5, y = 2, rotation = 30, scaleX = 0.5})
    local x, y = leaf:getWorldPosition()
    A.truthy(math.abs(x - 90) < 0.00001); A.truthy(math.abs(y - 204) < 0.00001)
    local world = leaf:getWorldTransform()
    local wx, wy = require("core.Transform").point(world, 2, 3)
    local lx, ly = require("core.Transform").inversePoint(world, wx, wy)
    A.truthy(math.abs(lx - 2) < 0.00001); A.truthy(math.abs(ly - 3) < 0.00001)
    A.equal(false, pcall(function() leaf.properties.scaleY = 0 end))
    A.equal(1, leaf.properties.scaleY)
end)

add("RenderComponent draw and local bounds work without Sprite-specific dispatch", function()
    local owner, called = object(), 0
    owner.transform = {x = 40, y = 50}
    local Shape = require("Engine").RenderComponent:extend({
        draw = function(self, context)
            called = called + 1; A.truthy(context.image)
            love.graphics.setColor(1, 0, 0, 1); love.graphics.rectangle("fill", -5, -5, 10, 10)
        end,
        getLocalBounds = function() return -5, -5, 10, 10 end
    })
    local shape = owner:addComponent("shape", Shape, {x = 10, rotation = 45})
    A.equal(false, shape:isA(Sprite)); A.truthy(shape:isA(require("Engine").RenderComponent))
    local renderer = require("core.Renderer")
    local canvas = love.graphics.newCanvas(100, 100)
    love.graphics.push("all"); love.graphics.setCanvas(canvas); love.graphics.clear()
    assert(renderer.draw(owner, function() error("shape should not load an image") end, function(x, y) return x, y end, 1))
    love.graphics.setCanvas()
    local pixels = canvas:newImageData(); local red, _, _, alpha = pixels:getPixel(50, 50)
    A.equal(1, red); A.equal(1, alpha); A.equal(1, called)
    pixels:release(); love.graphics.pop(); canvas:release()
    A.equal(true, renderer.hit(owner, function() end, 50, 50))
    A.equal(false, renderer.hit(owner, function() end, 60, 50))
    local corners = 0
    renderer.outline(owner, function() end, function(x, y) corners = corners + 1; return x, y end)
    A.equal(4, corners)
end)

add("draw failure restores graphics state and reaches the caller error boundary", function()
    local owner = object()
    owner:addComponent("broken", require("Engine").RenderComponent:extend({draw = function()
        love.graphics.setColor(0.1, 0.2, 0.3, 0.4); error("expected draw failure")
    end}))
    love.graphics.push("all"); love.graphics.setColor(1, 1, 1, 1)
    local ok, err = pcall(require("core.Renderer").draw, owner, function() end, function(x, y) return x, y end, 1)
    local r, g, b, a = love.graphics.getColor(); love.graphics.pop()
    A.equal(false, ok); A.truthy(err:find("expected draw failure", 1, true))
    A.equal(1, r); A.equal(1, g); A.equal(1, b); A.equal(1, a)
end)
add("Renamed sprite roots ignore legacy root Transform overrides in Prefab layers and instances", function()
    local Definition = require("project.ObjectDefinition")
    local legacy = {overrides = {components = {root = {x = 116, y = 20, rotation = 45}}}}
    local class = {build = function(self) self:setRootComponent("sprite", Sprite) end}
    local owner = object()
    assert(Definition.configure(owner, {class = class, properties = {}, components = legacy.overrides.components, layers = {legacy}}, nil, {root = {x = 300}, sprite = {image = false}}))
    A.equal(nil, owner.components.root); A.equal(owner.components.sprite, owner.rootComponent)
    A.equal(100, owner.transform.x); A.equal(200, owner.transform.y); A.equal(0, owner.transform.rotation)
end)
add("Missing component compatibility accepts only legacy root Transform fields", function()
    local Definition = require("project.ObjectDefinition")
    local class = {build = function(self) self:setRootComponent("sprite", Sprite) end}
    for _, overrides in ipairs({{root = {image = false}}, {removed = {x = 116}}}) do
        for _, layers in ipairs({false, true}) do
            local definition = {class = class, properties = {}, components = layers and overrides or {}}
            if layers then definition.layers = {{overrides = {components = overrides}}} end
            local ok, err = Definition.configure(object(), definition, nil, not layers and overrides or nil)
            A.equal(false, ok); A.truthy(err:find("Unknown component", 1, true))
        end
    end
    local ok, err = Definition.configure(object(), {class = class, properties = {}, components = {root = {x = "invalid"}}})
    A.equal(false, ok); A.truthy(err)
end)
add("Existing root named child overrides still apply to that component", function()
    local owner = object()
    assert(require("project.ObjectDefinition").configure(owner, {properties = {}, components = {root = {x = 116}}, class = {build = function(self)
        self:setRootComponent("sprite", Sprite)
        self:addComponent("root", Scene)
    end}}))
    A.equal(116, owner.components.root.transform.x); A.equal(100, owner.rootComponent.transform.x)
end)

return tests
