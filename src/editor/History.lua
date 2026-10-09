local History = {}
History.__index = History
function History.new(text, selection)
    return setmetatable({entries = {{text = text, selection = selection}}, index = 1, limit = 100}, History)
end
function History:record(text, selection)
    if self.entries[self.index].text == text then self.entries[self.index].selection = selection; return false end
    for i = #self.entries, self.index + 1, -1 do self.entries[i] = nil end
    self.entries[#self.entries + 1] = {text = text, selection = selection}
    if #self.entries > self.limit then table.remove(self.entries, 1) end
    self.index = #self.entries
    return true
end
function History:step(direction)
    local index = self.index + direction
    if index < 1 or index > #self.entries then return nil end
    self.index = index
    return self.entries[index]
end
return History
