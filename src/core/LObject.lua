local Transform = require("core.Transform")
local LObject = {}
LObject.__index = LObject
function LObject.new(runtimeId, initial)
    if type(runtimeId) ~= "number" or runtimeId < 1 or runtimeId % 1 ~= 0 then return nil, "Invalid runtime ID" end
    if type(initial) ~= "table" then return nil, "Invalid LObject state" end
    local transform, err = Transform.copy(initial.transform)
    if not transform then return nil, err end
    return setmetatable({runtimeId = runtimeId, authoringId = initial.authoringId, name = initial.name,
        definitionReference = initial.definitionReference, transform = transform, children = {},
        scripts = {}, scriptOrder = {}, updateScripts = {}, drawScripts = {}, properties = {}}, LObject)
end
function LObject:getScriptOrder() return self.scriptOrder end
function LObject:getScriptById(id) return self.scripts[id] end
function LObject:getScriptByName(name)
    for _, id in ipairs(self.scriptOrder) do if self.scripts[id].name == name then return self.scripts[id] end end
end
function LObject:getScriptByClass(class)
    for _, id in ipairs(self.scriptOrder) do if self.scripts[id]:isA(class) then return self.scripts[id] end end
end
function LObject:getScriptsByClass(class)
    local result = {}
    for _, id in ipairs(self.scriptOrder) do if self.scripts[id]:isA(class) then result[#result + 1] = self.scripts[id] end end
    return result
end
function LObject:load(world)
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
function LObject:update(dt)
    local pending = {}; for _, script in ipairs(self.updateScripts) do pending[#pending + 1] = script end
    for _, script in ipairs(pending) do
        if script.owner == self and self.scripts[script.id] == script and script.enabled ~= false then
            local ok, result, err = pcall(script.update, script, dt)
            if not ok or result == false then return false, tostring(ok and err or result) end
        end
    end
    return true
end
function LObject:getWorldTransform()
    return self.parent and Transform.compose(self.parent:getWorldTransform(), self.transform) or self.transform
end
function LObject:attachTo(parent)
    assert(parent == nil or getmetatable(parent) == LObject, "Parent must be an LObject")
    assert(not parent or not self.world or not parent.world or self.world == parent.world, "Objects must belong to the same World")
    local ancestor = parent
    while ancestor do assert(ancestor ~= self, "Object attachment cycle"); ancestor = ancestor.parent end
    if self.parent then
        for index, child in ipairs(self.parent.children) do if child == self then table.remove(self.parent.children, index); break end end
    end
    self.parent = parent
    if parent then parent.children[#parent.children + 1] = self end
    if self.world then self.world.updateOrderDirty = true end
    return self
end
return LObject
