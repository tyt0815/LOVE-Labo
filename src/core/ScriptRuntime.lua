-- 에디터·로더 전용 부착 구성. 게임 공개 API에서는 제공하지 않는다.
local Runtime = {}
function Runtime.attach(self, id, class, overrides, name)
    assert(not self:getScriptByName(name or id), "Duplicate script name")
    assert(type(id) == "string" and require("core.ScriptId").isValid(id) and not self.scripts[id], "Invalid or duplicate script ID")
    if type(class) == "string" then class = assert(self.scriptLoader(class, "script")) end
    assert(type(class) == "table" and type(class.new) == "function", "Expected a script definition")
    local script = class:new(overrides)
    script.owner, script.name, script.id = self, name or id, id
    self.scripts[id] = script; self.scriptOrder[#self.scriptOrder + 1] = id
    if script.update then self.updateScripts[#self.updateScripts + 1] = script end
    if script.draw then self.drawScripts[#self.drawScripts + 1] = script end
    if self.world then self.world.updateOrderDirty = true end
    if self.hasBegunPlay and not self.beginningPlay then
        local ok, err = self:beginPlay(self.world)
        if not ok then Runtime.detach(self, id); error(err, 0) end
    end
    return script
end
function Runtime.detach(self, id)
    local script = assert(self.scripts[id], "Missing script")
    self.scripts[id] = nil
    for _, list in ipairs({self.scriptOrder, self.updateScripts, self.drawScripts}) do
        for index = #list, 1, -1 do if list[index] == id or list[index] == script then table.remove(list, index) end end
    end
    script.owner = nil
    if self.world then self.world.updateOrderDirty = true end
    return script
end
return Runtime
