-- Project·World·LObject의 부착 저장소와 실행 메서드를 공유하며 상속 관계를 만들지 않는다.
local Host = {}
Host.__index = Host
function Host.initialize(self, scope)
    self.scope = scope
    self.scripts, self.scriptOrder, self.updateScripts, self.drawScripts = {}, {}, {}, {}
    return self
end
function Host.new(scope)
    return Host.initialize(setmetatable({}, Host), scope)
end
function Host:getWorld()
    if self.isPreview then return nil end
    return self.scope == "level" and self or self.world
end
function Host:getProject()
    if self.isPreview then return nil end
    local world = self:getWorld()
    return self.scope == "project" and self or world and world.project
end
function Host:getWorldTransform()
    return {x = 0, y = 0, rotation = 0, rotationX = 0, rotationY = 0, scaleX = 1, scaleY = 1}
end
function Host:getScriptOrder() return self.scriptOrder end
function Host:getScriptById(id) return self.scripts[id] end
function Host:getScriptByName(name)
    for _, id in ipairs(self.scriptOrder) do if self.scripts[id].name == name then return self.scripts[id] end end
end
function Host:getScriptByClass(class)
    for _, id in ipairs(self.scriptOrder) do if self.scripts[id]:isA(class) then return self.scripts[id] end end
end
function Host:getScriptsByClass(class)
    local result = {}
    for _, id in ipairs(self.scriptOrder) do if self.scripts[id]:isA(class) then result[#result + 1] = self.scripts[id] end end
    return result
end
function Host:load(world)
    if world and self.world ~= world then return true end
    self.world, self.hasLoaded = world, true
    if world then world.updateOrderDirty = true end
    if self.loadingScripts then return true end
    self.loadingScripts = true
    local ok, err = pcall(function()
        -- 콜백이 새 스크립트를 부착해도 재진입하지 않고 동일 초기화 경계에서 처리한다.
        local initialized = 0
        while true do
            if world and self.world ~= world then break end
            local pending
            for _, id in ipairs(self.scriptOrder) do
                local script = self.scripts[id]
                if script and script.owner == self and not script.hasLoaded then pending = script; break end
            end
            if not pending then break end
            initialized = initialized + 1
            assert(initialized <= 4096, "Too many scripts added during load")
            pending.hasLoaded = true
            if pending.load then
                local result, errorText = pending:load(world)
                assert(result ~= false, errorText)
            end
        end
    end)
    self.loadingScripts = nil
    return ok, not ok and tostring(err) or nil
end
function Host:unload()
    local pending = {}; for _, id in ipairs(self.scriptOrder) do pending[#pending + 1] = self.scripts[id] end
    local firstError
    for index = #pending, 1, -1 do
        local ok, err = require("core.ScriptRuntime").unload(pending[index])
        if not ok and not firstError then firstError = err end
    end
    return firstError == nil, firstError
end
function Host:update(dt)
    if self.removing then return true end
    local pending = {}; for _, script in ipairs(self.updateScripts) do pending[#pending + 1] = script end
    for _, script in ipairs(pending) do
        if script.owner == self and self.scripts[script.id] == script and script.enabled ~= false then
            local ok, result, err = pcall(script.update, script, dt)
            if not ok or result == false then return false, tostring(ok and err or result) end
        end
    end
    return true
end
return Host
