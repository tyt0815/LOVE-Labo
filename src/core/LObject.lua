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
function LObject:getScript(id) return self.scripts[id] end
function LObject:addScript(id, class, overrides)
    assert(type(id) == "string" and id:match("^[%a_][%w_]*$") and not self.scripts[id], "Invalid or duplicate script ID")
    if type(class) == "string" then class = assert(self.scriptLoader(class, "script")) end
    assert(type(class) == "table" and type(class.new) == "function", "Expected a script definition")
    local script = class:new(overrides)
    script.owner, script.name, script.id = self, id, id
    self.scripts[id] = script; self.scriptOrder[#self.scriptOrder + 1] = id
    if script.update then self.updateScripts[#self.updateScripts + 1] = script end
    if script.draw then self.drawScripts[#self.drawScripts + 1] = script end
    if self.world then self.world.updateOrderDirty = true end
    if self.hasBegunPlay and not self.beginningPlay then
        local ok, err = self:beginPlay(self.world)
        if not ok then self:removeScript(id); error(err, 0) end
    end
    return script
end
function LObject:removeScript(id)
    local script = assert(self.scripts[id], "Missing script")
    self.scripts[id] = nil
    for _, list in ipairs({self.scriptOrder, self.updateScripts, self.drawScripts}) do
        for index = #list, 1, -1 do if list[index] == id or list[index] == script then table.remove(list, index) end end
    end
    script.owner = nil
    if self.world then self.world.updateOrderDirty = true end
    return script
end
function LObject:beginPlay(world)
    if world and self.world ~= world then return true end
    self.world, self.hasBegunPlay = world, true
    if world then world.updateOrderDirty = true end
    if self.beginningPlay then return true end
    self.beginningPlay = true
    local ok, err = pcall(function()
        -- 콜백이 새 스크립트를 부착해도 재진입하지 않고 동일 초기화 경계에서 처리한다.
        local initialized = 0
        while true do
            if world and self.world ~= world then break end
            local pending
            for _, id in ipairs(self.scriptOrder) do
                local script = self.scripts[id]
                if script and script.owner == self and not script.hasBegunPlay then pending = script; break end
            end
            if not pending then break end
            initialized = initialized + 1
            assert(initialized <= 4096, "Too many scripts added during beginPlay")
            pending.hasBegunPlay = true
            if pending.beginPlay then
                local result, errorText = pending:beginPlay(world)
                assert(result ~= false, errorText)
            end
        end
    end)
    self.beginningPlay = nil
    return ok, not ok and tostring(err) or nil
end
function LObject:update(dt)
    local pending = {}; for _, script in ipairs(self.updateScripts) do pending[#pending + 1] = script end
    for _, script in ipairs(pending) do
        if script.owner == self and self.scripts[script.id] == script then
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
