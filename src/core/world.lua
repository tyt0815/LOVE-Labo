local LObject = require("core.lobject")

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

    self.lobjects = {}
    self.nextRuntimeId = 1

    -- Play session 안에서만 진행되는 Runtime clock이다.
    -- 새 World가 생성될 때마다 0부터 다시 시작한다.
    self.elapsedTime = 0

    return self
end

function World:addLObject(initialState)
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

    return lobject
end

function World:SpawnLObject(prefab, transform, overrides)
    if not self._spawnLObject then return nil, "World has no Prefab loader" end
    return self._spawnLObject(prefab, transform, overrides)
end

function World:update(dt)
    local valid, validationError =
        validateDeltaTime(dt)

    if not valid then
        return false, validationError
    end

    -- 이번 프레임 중 생성된 객체는 BeginPlay만 즉시 호출하고 다음 프레임부터 Update한다.
    local count = #self.lobjects
    if self.levelScript and self.levelScript.update then
        local ok, result, err = pcall(self.levelScript.update, self, dt)
        if not ok or result == false then return false, "level script update failed: " .. tostring(ok and err or result) end
    end

    -- World가 Runtime LObject lifecycle의 호출 순서를 소유한다.
    -- LObject:update()가 false를 명시적으로 반환한 경우만 실패로 취급한다.
    -- 일반적인 Lua callback처럼 nil을 반환하는 update는 정상 완료로 본다.
    for i = 1, count do
        local lobject = self.lobjects[i]
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

    self.elapsedTime =
        self.elapsedTime + dt

    return true
end

function World:setLevelScript(script)
    if type(script) ~= "table" then return false, "level script must be a table" end
    for _, name in ipairs({ "BeginPlay", "load", "update" }) do
        if script[name] ~= nil and type(script[name]) ~= "function" then return false, "invalid level script callback: " .. name end
    end
    local callback = script.BeginPlay or script.load
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

    local world = World.new()

    world.lobjects = runtimeLObjects
    world.nextRuntimeId =
        #runtimeLObjects + 1

    return world
end

return World
