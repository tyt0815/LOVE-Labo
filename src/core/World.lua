local LObject = require("core.LObject")

local World = {}
World.__index = World

local function validateDeltaTime(dt)
    if type(dt) ~= "number"
        or dt < 0
        or dt ~= dt
        or dt == math.huge
        or dt == -math.huge
    then
        return false, "runtime delta time must be a finite non-negative number"
    end

    return true
end

function World.new()
    local self = setmetatable({}, World)
    require("core.ScriptHost").initialize(self, "level")
    self.world = self

    self.lobjects = {}
    self.nextRuntimeId = 1
    self.debug = require("core.Debug")

    -- Play session 안에서만 진행되는 Runtime clock이다.
    -- 새 World가 생성될 때마다 0부터 다시 시작한다.
    self.elapsedTime = 0

    return self
end

function World:addLObject(initialState)
    if self.disposed then return nil, "World is disposed" end
    local lobject, createError =
        LObject.new(
            self.nextRuntimeId,
            initialState
        )

    if not lobject then
        return nil, createError
    end

    self.nextRuntimeId =
        self.nextRuntimeId + 1

    self.lobjects[#self.lobjects + 1] =
        lobject
    lobject.world = self
    lobject.scriptLoader = self.scriptLoader

    return lobject
end

function World:spawnLObject(template, transform, overrides)
    if self.disposed then return nil, "World is disposed" end
    if not self.spawnLObjectFactory then return nil, "World has no LObjectTemplate loader" end
    return self.spawnLObjectFactory(template, transform, overrides)
end
function World:removeLObject(object)
    if object.transferPending then return false, "Object is being transferred" end
    if object.removing and object.world == self then return true end
    local live = false
    for _, current in ipairs(self.lobjects) do if current == object then live = true end end
    if not live then return false, "Object does not belong to this World" end
    local removed = {}
    local function visit(current)
        removed[current] = true
        for _, child in ipairs(current.children) do visit(child) end
    end
    visit(object); object:attachTo(nil)
    local cleanupError
    local ordered = require("core.ScriptOrder").objects(self.lobjects)
    for _, current in ipairs(ordered) do if removed[current] then current.removing = true end end
    for index = #ordered, 1, -1 do
        local current = ordered[index]
        if removed[current] then
            local ok, err = current:unload()
            if not ok and not cleanupError then cleanupError = err end
        end
    end
    for index = #self.lobjects, 1, -1 do
        local current = self.lobjects[index]
        if removed[current] then
            current.world = nil
            for _, script in pairs(current.scripts) do script.owner = nil end
            table.remove(self.lobjects, index)
        end
    end
    for button, script in pairs(self.pointerCaptures or {}) do if not script.owner then self.pointerCaptures[button] = nil end end
    return cleanupError == nil, cleanupError
end
function World:dispose(preserveProject)
    if self.transitionInProgress then return false, "World is being transferred" end
    if self.disposed then return true end
    self.disposed = true
    if self.pendingLevel then
        local pending = self.pendingLevel; self.pendingLevel = nil
        pending.world:dispose(true)
    end
    self:cancelPointer()
    local pending = {}; for _, object in ipairs(self.lobjects) do pending[#pending + 1] = object end
    local cleanupError
    for index = #pending, 1, -1 do
        local object = pending[index]
        if object.world == self then
            local ok, err = self:removeLObject(object)
            if not ok and not cleanupError then cleanupError = err end
        end
    end
    local ok, err = require("core.ScriptHost").unload(self)
    if not ok and not cleanupError then cleanupError = err end
    if self.project and not preserveProject and self.project.world == self then
        local project = self.project
        local cleaned, cleanup = project:unload()
        project.world, project.disposed = nil, true
        if not cleaned and not cleanupError then cleanupError = cleanup end
    end
    require("core.Rendering").dispose(self)
    return cleanupError == nil, cleanupError
end
for _, name in ipairs({"getScriptOrder", "getScriptById", "getScriptByName", "getScriptByClass", "getScriptsByClass", "getWorld", "getProject", "getWorldTransform"}) do
    World[name] = require("core.ScriptHost")[name]
end
function World:getObjects()
    local result = {}; for _, object in ipairs(self.lobjects) do result[#result + 1] = object end
    return result
end
function World:getAssetData(reference)
    if self.disposed then return nil, "World is disposed" end
    if not self.assetDataLoader then return nil, "World has no asset data loader" end
    return self.assetDataLoader(reference)
end
function World:dispatchPointer(kind, x, y, button, dx, dy, context)
    local ok, result = pcall(require("core.PointerInput").dispatch, self, kind, x, y, button, dx, dy, context)
    if not ok then self:cancelPointer(); return false, "Pointer input failed: " .. tostring(result) end
    return true, result
end
function World:dispatchEvent(name, ...) return require("core.ScriptEvents").dispatch(self, name, ...) end
function World:cancelPointer()
    for _, view in ipairs(self.renderViews or {}) do view.pointerCaptures = {} end
    self.pointerCaptures = {}
    require("core.ScriptEvents").cancel(self)
end
function World:openLevel(reference, options)
    if self.disposed then return false, "World is disposed" end
    if not self.openLevelRequest then return false, "World has no Level loader" end
    local called, ok, err = pcall(self.openLevelRequest, reference, options)
    if not called then return false, tostring(ok) end
    return ok, err
end
function World:takeLevelTransition()
    if not self.applyLevelRequest then return nil end
    return self.applyLevelRequest()
end
function World:update(dt)
    if self.disposed then return false, "World is disposed" end
    local valid, validationError =
        validateDeltaTime(dt)

    if not valid then
        return false, validationError
    end

    -- 프레임 시작 시 모든 범위의 실행 목록과 순서를 고정한다. 새 부착은 다음 프레임부터 실행한다.
    local order = require("core.ScriptOrder")
    local pending = order.updates(order.hosts(self), self)
    local ok, err = require("core.ScriptHost").runUpdates(pending, dt, self)
    if not ok then return false, err end

    self.elapsedTime =
        self.elapsedTime + dt

    return true
end

function World:setLevelScript(script)
    if type(script) ~= "table" then return false, "level script must be a table" end
    for _, name in ipairs({ "load", "update" }) do
        if script[name] ~= nil and type(script[name]) ~= "function" then return false, "invalid level script callback: " .. name end
    end
    local callback = script.load
    if callback then
        local ok, result, err = pcall(callback, self)
        if not ok or result == false then return false, "level script load failed: " .. tostring(ok and err or result) end
    end
    self.levelScript = script
    return true
end

function World.fromLevelData(levelData)
    if type(levelData) ~= "table" then
        return nil, "level runtime data must be a table"
    end

    if type(levelData.lobjects) ~= "table" then
        return nil, "level runtime lobjects must be a table"
    end

    local runtimeLObjects = {}

    -- 모든 Runtime LObject를 먼저 생성한다.
    -- 중간에 하나라도 실패하면 반쯤 만들어진 World를 외부에 노출하지 않는다.
    for i, lobjectData in ipairs(levelData.lobjects) do
        local lobject, createError =
            LObject.new(i, lobjectData)

        if not lobject then
            return nil,
                "invalid runtime lobject "
                .. i
                .. ": "
                .. createError
        end

        runtimeLObjects[i] =
            lobject
    end

    local byId = {}
    for _, object in ipairs(runtimeLObjects) do
        if object.authoringId then
            if byId[object.authoringId] then return nil, "Duplicate object identity" end
            byId[object.authoringId] = object
        end
    end
    for i, object in ipairs(runtimeLObjects) do
        local id = levelData.lobjects[i].parentAuthoringId
        if id then
            if not byId[id] then return nil, "Missing object parent" end
            local ok, err = pcall(object.attachTo, object, byId[id])
            if not ok then return nil, tostring(err) end
        end
    end
    local world = World.new()

    world.lobjects = runtimeLObjects
    for _, object in ipairs(runtimeLObjects) do object.world = world end
    world.nextRuntimeId =
        #runtimeLObjects + 1

    return world
end

return World
