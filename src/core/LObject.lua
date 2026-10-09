local LObject = {}
LObject.__index = function(self, name)
    if name == "transform" then return self.rootComponent and self.rootComponent.transform or self.initialTransform end
    return LObject[name]
end
LObject.__newindex = function(self, name, value)
    if name == "transform" and self.rootComponent then self.rootComponent:setTransform(value)
    else rawset(self, name, value) end
end
local ROOT_PARENT = {}

local function isPositiveInteger(value)
    return type(value) == "number"
        and value >= 1
        and value % 1 == 0
end

local function validateDefinitionReference(reference)
    if reference == nil then
        return true
    end

    if type(reference) ~= "string"
        or reference == ""
    then
        return false,
            "runtime definitionReference must be a non-empty string"
    end

    return true
end

local function validateTransform(transform)
    if type(transform) ~= "table" then
        return false,
            "runtime initial transform must be a table"
    end

    if type(transform.x) ~= "number"
        or type(transform.y) ~= "number"
    then
        return false,
            "runtime initial transform x/y must be numbers"
    end

    return true
end

function LObject.new(runtimeId, initialState)
    if not isPositiveInteger(runtimeId) then
        return nil,
            "runtimeId must be a positive integer"
    end

    if type(initialState) ~= "table" then
        return nil,
            "runtime initial lobject must be a table"
    end

    local validDefinitionReference, definitionReferenceError =
        validateDefinitionReference(
            initialState.definitionReference
        )

    if not validDefinitionReference then
        return nil, definitionReferenceError
    end

    local validTransform, transformError =
        validateTransform(initialState.transform)

    if not validTransform then
        return nil, transformError
    end

    local self =
        setmetatable({}, LObject)

    self.runtimeId = runtimeId
    self.authoringId = initialState.authoringId
    self.components, self.componentOrder = {}, {}

    -- Definition 해석은 프로젝트 로더가 담당하고 Core에는 구성 결과만 전달한다.
    self.definitionReference =
        initialState.definitionReference

    -- Runtime mutable state는 authoring/serialized data와 table reference를
    -- 공유하지 않도록 Runtime LObject가 자기 Transform을 소유한다.
    local transform, transformError = require("core.Transform").copy(initialState.transform)
    if not transform then return nil, transformError end
    self.initialTransform = transform
    self.rootComponent = self:addComponent("root", require("core.SceneComponent"))
    self.rootComponent:setTransform(transform)
    self.initialTransform = nil
    self.rootComponent.isDefaultRoot = true

    return self
end

function LObject:update(dt)
    if self.luaClass and self.luaClass.update then
        local ok, result, err = pcall(self.luaClass.update, self, dt)
        if not ok or result == false then return false, tostring(ok and err or result) end
    end
    for _, name in ipairs(self:getComponentOrder()) do
        local component = self.components[name]
        local ok, result, err = pcall(component.update, component, dt)
        if not ok or result == false then return false, tostring(ok and err or result) end
    end
end

local function detach(component)
    if component.parent then
        for i, child in ipairs(component.parent.children) do
            if child == component then table.remove(component.parent.children, i); break end
        end
    end
    component.parent = nil
end

function LObject:attachComponent(component, parent)
    if type(component) == "string" then component = self.components[component] end
    if type(parent) == "string" then parent = assert(self.components[parent], "Missing parent component") end
    parent = parent or self.rootComponent
    assert(component and component.owner == self, "Component must belong to this LObject")
    assert(component ~= self.rootComponent, "Root cannot be attached below another component")
    assert(parent and parent.owner == self, "Parent must belong to this LObject")
    local ancestor = parent
    while ancestor do assert(ancestor ~= component, "Component attachment cycle"); ancestor = ancestor.parent end
    detach(component)
    component.parent = parent
    parent.children[#parent.children + 1] = component
    return component
end

function LObject:getComponentOrder()
    local order = {}
    local function visit(component)
        order[#order + 1] = component.name
        for _, child in ipairs(component.children) do visit(child) end
    end
    if self.rootComponent then visit(self.rootComponent) end
    return order
end

local function state(object)
    -- 사용자 build의 실패로 기존 부착 관계가 반쯤 바뀐 상태를 남기지 않는다.
    local saved = {components = {}, order = {}, links = {}, root = object.rootComponent, depth = object.componentBuildDepth}
    for name, component in pairs(object.components) do
        saved.components[name] = component
        local children = {}; for _, child in ipairs(component.children) do children[#children + 1] = child end
        saved.links[component] = {parent = component.parent, children = children,
            transform = component.transform and require("core.Transform").copy(component.transform)}
    end
    for _, name in ipairs(object.componentOrder) do saved.order[#saved.order + 1] = name end
    return saved
end
local function restore(object, saved)
    for name, component in pairs(object.components) do
        if saved.components[name] ~= component then component.owner, component.parent, component.children = nil, nil, {} end
    end
    object.components, object.componentOrder, object.rootComponent, object.componentBuildDepth = saved.components, saved.order, saved.root, saved.depth
    for component, link in pairs(saved.links) do
        component.owner, component.parent, component.children = object, link.parent, link.children
        if link.transform then component:setTransform(link.transform) end
    end
end
local function resolveClass(object, class)
    if type(class) == "string" then
        assert(object.componentLoader, "Component asset loader is not configured")
        return assert(object.componentLoader(class, "component"))
    end
    return class
end
local function beginComponents(object)
    -- 콜백 안의 루트 교체·추가는 현재 초기화가 끝난 뒤 새 계층에서 처리한다.
    if object.initializingComponents then return end
    object.initializingComponents = true
    local ok, err = pcall(function()
        while true do
            local pending
            for _, name in ipairs(object:getComponentOrder()) do
                local component = object.components[name]
                if not component.hasBegunPlay and not component.beginningPlay then pending = component; break end
            end
            if not pending then break end
            pending.beginningPlay = true
            local called, result, callbackError = pcall(require("core.LObjectComponent").beginPlayCallback(pending), pending, object.world)
            pending.beginningPlay = nil
            if not called then error(result, 0) end
            assert(result ~= false, callbackError)
            pending.hasBegunPlay = true
        end
    end)
    object.initializingComponents = nil
    if not ok then error(err, 0) end
end

function LObject:addComponent(name, class, overrides, parent)
    assert(type(name) == "string" and name:match("^[%a_][%w_]*$"), "Component name must be an identifier")
    assert(not self.components[name], "Duplicate component name: " .. name)
    class = resolveClass(self, class)
    local component = class:new(overrides)
    assert(component:isA(require("core.LObjectComponent")), "Expected LObjectComponent")
    local saved = state(self)
    local ok, err = pcall(function()
        component.owner, component.name = self, name
        self.components[name] = component
        self.componentOrder[#self.componentOrder + 1] = name
        if self.rootComponent and parent ~= ROOT_PARENT then self:attachComponent(component, parent) end
        if component.build then
            self.componentBuildDepth = (self.componentBuildDepth or 0) + 1
            assert(self.componentBuildDepth <= 64, "Component construction is too deep")
            local result, buildError = component.build(component)
            self.componentBuildDepth = self.componentBuildDepth - 1
            assert(result ~= false, buildError)
        end
        if self.hasBegunPlay and (self.componentBuildDepth or 0) == 0 and parent ~= ROOT_PARENT then beginComponents(self) end
    end)
    if not ok then restore(self, saved); error(err, 0) end
    return component
end

function LObject:setRootComponent(name, class, overrides)
    local saved, old = state(self), self.rootComponent
    local component = type(name) == "table" and name or self.components[name]
    local replace = class and old and old.name == name
    local ok, err = pcall(function()
        if class then
            class = resolveClass(self, class)
            local ancestor = class
            while ancestor and ancestor ~= require("core.SceneComponent") do ancestor = ancestor.super end
            assert(ancestor, "Root class must inherit SceneComponent")
            if replace then self.components[name] = nil end
            component = self:addComponent(name, class, overrides, ROOT_PARENT)
        end
        assert(component and component.owner == self and component:isA(require("core.SceneComponent")), "Root must be a SceneComponent of this LObject")
        if component == old then return end
        component:setTransform(self.transform)
        detach(component)
        self.rootComponent = component
        if old then
            if old.isDefaultRoot or replace then
                local children = {}; for _, child in ipairs(old.children) do children[#children + 1] = child end
                for _, child in ipairs(children) do self:attachComponent(child, component) end
                if self.components[old.name] == old then self.components[old.name] = nil end
                for i, current in ipairs(self.componentOrder) do if current == old.name then table.remove(self.componentOrder, i); break end end
                old.owner, old.children = nil, {}
            else
                old:setTransform({x = 0, y = 0})
                self:attachComponent(old, component)
            end
        end
        if self.hasBegunPlay and (self.componentBuildDepth or 0) == 0 then beginComponents(self) end
    end)
    if not ok then restore(self, saved); error(err, 0) end
    return component
end

function LObject:beginPlay(world)
    self.world = world
    self.hasBegunPlay = true
    local begun, beginError = pcall(beginComponents, self)
    if not begun then return false, tostring(beginError) end
    local callback = self.luaClass and (self.luaClass.beginPlay or self.luaClass.load)
    if callback then
        local ok, result, err = pcall(callback, self, world)
        if not ok or result == false then return false, tostring(ok and err or result) end
    end
    return true
end
LObject.load = LObject.beginPlay

function LObject:setClass(class, properties, world)
    self.luaClass, self.properties = class, properties or {}
    if class and class.build then
        local ok, result, err = pcall(class.build, self)
        if not ok or result == false then return false, tostring(ok and err or result) end
    end
    return self:beginPlay(world)
end

return LObject
