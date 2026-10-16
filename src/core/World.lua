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
    self.updateOrderDirty = true

    return lobject
end

function World:spawnLObject(template, transform, overrides)
    if self.disposed then return nil, "World is disposed" end
    if not self.spawnLObjectFactory then return nil, "World has no LObjectTemplate loader" end
    return self.spawnLObjectFactory(template, transform, overrides)
end
function World:removeLObject(object)
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
    self.updateOrderDirty = true
    return cleanupError == nil, cleanupError
end
function World:dispose(preserveProject)
    if self.disposed then return true end
    self.disposed = true
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
-- 과거 단일 화면 코드의 호환 API다. 새 출력 구성은 Rendering.createView를 사용한다.
function World:setActiveCamera(camera)
    if camera ~= nil and not require("core.RenderView").validCamera(self, camera) then return false, "Camera must belong to this World" end
    if self.disposed then return false, "World is disposed" end
    self.legacyCameraSelection, self.activeCamera = true, camera
    if self.legacyView then self.legacyView:setCamera(camera or self:getActiveCamera()) end
    return true
end
function World:getActiveCamera()
    if not self.legacyCameraSelection then
        local views = require("core.Rendering").views(self)
        for index = #views, 1, -1 do
            if views[index].target == require("core.Rendering").screen then return views[index].camera end
        end
    end
    local first
    local hosts = self:getObjects(); table.insert(hosts, 1, self)
    if self.project then table.insert(hosts, 1, self.project) end
    for _, object in ipairs(hosts) do
        for _, name in ipairs(object:getScriptOrder()) do
            local script = object.scripts[name]
            if script.camera and script.enabled ~= false then
                if script == self.activeCamera then return script end
                first = first or script
            end
        end
    end
    return first
end

function World:openLevel(reference)
    if self.disposed then return false, "World is disposed" end
    if not self.openLevelRequest then return false, "World has no Level loader" end
    local called, ok, err = pcall(self.openLevelRequest, reference)
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

    -- 이번 프레임 중 생성된 객체는 load만 즉시 호출하고 다음 프레임부터 update한다.
    if self.updateOrderDirty or not self.updateObjects then
        self.updateObjects = {}
        for _, object in ipairs(require("core.ScriptOrder").objects(self.lobjects)) do
            if #object.updateScripts > 0 then self.updateObjects[#self.updateObjects + 1] = object end
        end
        self.updateOrderDirty = nil
    end
    local pending = {}; for _, object in ipairs(self.updateObjects) do pending[#pending + 1] = object end
    local hosts = {self.project, self}
    if not self.project then hosts = {self} end
    for _, host in ipairs(hosts) do
        local ok, err = require("core.ScriptHost").update(host, dt)
        if not ok then return false, host.scope .. " script update failed: " .. tostring(err) end
    end
    if self.levelScript and self.levelScript.update then
        local ok, result, err = pcall(self.levelScript.update, self, dt)
        if not ok or result == false then return false, "level script update failed: " .. tostring(ok and err or result) end
    end

    -- World가 Runtime LObject lifecycle의 호출 순서를 소유한다.
    -- LObject:update()가 false를 명시적으로 반환한 경우만 실패로 취급한다.
    -- 일반적인 Lua callback처럼 nil을 반환하는 update는 정상 완료로 본다.
    for _, lobject in ipairs(pending) do
        if lobject.world == self then
        local updated, updateError =
            lobject:update(dt)

        if updated == false then
            return false,
                "runtime lobject "
                .. lobject.runtimeId
                .. " update failed: "
                .. tostring(updateError)
        end
        end
    end

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
