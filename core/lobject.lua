local LObject = {}
LObject.__index = LObject

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
    local transform, transformError = require("core.transform").copy(initialState.transform)
    if not transform then return nil, transformError end
    self.transform = transform

    return self
end

function LObject:update(dt)
    if self.luaClass and self.luaClass.update then
        local ok, result, err = pcall(self.luaClass.update, self, dt)
        if not ok or result == false then return false, tostring(ok and err or result) end
    end
    for _, name in ipairs(self.componentOrder) do
        local component = self.components[name]
        local ok, result, err = pcall(component.Update, component, dt)
        if not ok or result == false then return false, tostring(ok and err or result) end
    end
end

function LObject:addComponent(name, class, overrides)
    assert(type(name) == "string" and name:match("^[%a_][%w_]*$"), "Component name must be an identifier")
    assert(not self.components[name], "Duplicate component name: " .. name)
    local component = class:new(overrides)
    assert(component:isA(require("core.lobject_component")), "Expected LObjectComponent")
    component.owner, component.name = self, name
    self.components[name] = component
    self.componentOrder[#self.componentOrder + 1] = name
    if self.loaded then
        local result, err = component:Load(self.world)
        assert(result ~= false, err)
    end
    return component
end

function LObject:load(world)
    self.world = world
    for _, name in ipairs(self.componentOrder) do
        local component = self.components[name]
        local ok, result, err = pcall(component.Load, component, world)
        if not ok or result == false then return false, tostring(ok and err or result) end
    end
    self.loaded = true
    if self.luaClass and self.luaClass.load then
        local ok, result, err = pcall(self.luaClass.load, self, world)
        if not ok or result == false then return false, tostring(ok and err or result) end
    end
    return true
end

function LObject:setClass(class, properties, world)
    self.luaClass, self.properties = class, properties or {}
    if class and class.build then
        local ok, result, err = pcall(class.build, self)
        if not ok or result == false then return false, tostring(ok and err or result) end
    end
    return self:load(world)
end

return LObject
