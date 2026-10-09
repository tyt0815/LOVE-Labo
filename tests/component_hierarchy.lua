local A = require("tests.assert")
local Object = require("core.lobject")
local Component = require("core.lobject_component")
local Scene = require("core.scene_component")
local Sprite = require("core.sprite_component")
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
    local x, y = hand:getWorldPosition(); A.equal(135, x); A.equal(237, y)
    owner.transform.rotation = 90
    x, y = hand:getWorldPosition()
    A.truthy(math.abs(x - 63) < 0.00001); A.truthy(math.abs(y - 235) < 0.00001)
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
    assert(owner:BeginPlay({}))
    local Child = Component:extend({BeginPlay = function(self) calls[#calls + 1] = self.name end})
    local Parent = Scene:extend({
        build = function(self) self:addComponent("child", Child) end,
        BeginPlay = function(self) calls[#calls + 1] = self.name end
    })
    owner:addComponent("parent", Parent)
    A.equal("parent,child", table.concat(calls, ","))
    owner:setRootComponent("replacement", Parent:extend({build = function() end}))
    A.equal("parent,child,replacement", table.concat(calls, ","))
end)

add("Components attached during initial BeginPlay also initialize once", function()
    local owner, calls = object(), {}
    local Child = Component:extend({BeginPlay = function(self) calls[#calls + 1] = self.name end})
    owner:setRootComponent("root", Scene:extend({BeginPlay = function(self)
        calls[#calls + 1] = self.name
        self:addComponent("late", Child)
    end}))
    assert(owner:BeginPlay({}))
    A.equal("root,late", table.concat(calls, ","))
    A.equal(true, owner.components.late.hasBegunPlay)
end)

add("Nested Sprite render hit and outline share the inherited component position", function()
    local owner = object()
    local branch = owner:addComponent("branch", Scene, {x = 40, y = 20})
    branch:addComponent("sprite", Sprite, {x = 10, image = "image"})
    local pixels = love.image.newImageData(8, 8)
    local image = love.graphics.newImage(pixels); pixels:release()
    local Renderer = require("core.sprite_renderer")
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
    local tree = require("editor.ui.component_tree").new(owner, "Actor", function(name) chosen = name end)
    tree:setBounds(0, 0, 300, 52); tree:clampScroll()
    A.equal(3, tree.nodes[4].depth)
    tree.expanded[false] = false; tree:rebuild(); A.equal(1, #tree.nodes)
    tree:reveal("child"); A.equal(4, #tree.nodes); A.equal(2, tree.scroll)
    tree:dispatch("keypressed", "up"); A.equal("object", chosen)
    tree:dispatch("keypressed", "left"); A.equal(3, #tree.nodes)
    tree:dispatch("keypressed", "right"); A.equal(4, #tree.nodes)
    A.equal(child, owner.components.child)
end)
add("BeginPlay root replacement does not reenter the preserved old root", function()
    local owner, calls = object(), {}
    local Child = Component:extend({BeginPlay = function(self) calls[#calls + 1] = self.name end})
    local NewRoot = Scene:extend({BeginPlay = function(self) calls[#calls + 1] = self.name end})
    owner:setRootComponent("custom", Scene:extend({BeginPlay = function(self)
        calls[#calls + 1] = self.name
        self.owner:setRootComponent("replacement", NewRoot)
    end}))
    owner.rootComponent:addComponent("child", Child)
    assert(owner:BeginPlay({}))
    A.equal("custom,replacement,child", table.concat(calls, ","))
    A.equal(owner.rootComponent, owner.components.custom.parent)
    A.equal(nil, owner.components.custom.beginningPlay)
    A.equal(true, owner.components.custom.hasBegunPlay)
end)

add("Runtime build initializes components added outside its own subtree before Update", function()
    local owner, calls = object(), {}
    assert(owner:BeginPlay({}))
    local Child = Component:extend({
        BeginPlay = function(self) calls[#calls + 1] = self.name; self.ready = true end,
        Update = function(self) A.equal(true, self.ready) end
    })
    owner:addComponent("parent", Scene:extend({
        build = function(self)
            self.owner:addComponent("sibling", Child)
            self:addComponent("child", Child)
        end,
        BeginPlay = function(self) calls[#calls + 1] = self.name end
    }))
    A.equal("parent,child,sibling", table.concat(calls, ","))
    A.equal(owner.rootComponent, owner.components.sibling.parent)
    assert(owner:update(0.1) ~= false)
    owner:addComponent("other", Component)
    A.equal("parent,child,sibling", table.concat(calls, ","))
end)

add("Failed BeginPlay clears initialization guards for a later retry", function()
    local owner, attempts = object(), 0
    owner:setRootComponent("custom", Scene:extend({BeginPlay = function()
        attempts = attempts + 1
        if attempts == 1 then error("expected initialization failure") end
    end}))
    A.equal(false, owner:BeginPlay({}))
    A.equal(nil, owner.initializingComponents); A.equal(nil, owner.rootComponent.beginningPlay)
    assert(owner:BeginPlay({})); A.equal(2, attempts)
end)

add("Fractional component tree wheel input keeps rows drawable and clickable", function()
    local owner = object()
    for i = 1, 10 do owner:addComponent("child" .. i, Scene) end
    local chosen
    local tree = require("editor.ui.component_tree").new(owner, "Actor", function(name) chosen = name end)
    tree:setBounds(0, 0, 300, 78)
    local UI, count = require("editor.ui"), 0
    local original = UI.text
    UI.text = function(...) count = count + 1; return original(...) end
    local ok, err = pcall(function()
        for _, amount in ipairs({-0.1, -0.5, -1.25, 0.1, 0.5, 1.25}) do
            tree:dispatch("wheelmoved", 100, 10, amount)
            A.equal(math.floor(tree.scroll), tree.scroll)
            count = 0; tree:draw(); A.equal(3, count)
            tree:dispatch("mousepressed", 200, 13, 1)
            A.equal(tree.nodes[tree.scroll + 1].key or nil, chosen)
        end
    end)
    UI.text = original; assert(ok, err)
end)
return tests
