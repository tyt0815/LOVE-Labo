local Json = require("project.Json")
local Scoped = require("project.ScopedScripts")
local Document = {}
Document.__index = Document
function Document.new(project)
    local self = setmetatable({project = project, data = project}, Document)
    self.savedSnapshot = self:snapshot()
    return self
end
function Document:snapshot() return assert(Json.encode(assert(Scoped.validate(self.data)), true)) end
function Document:restore(bytes)
    local data = assert(Scoped.validate(assert(Json.decode(bytes))))
    self.data.scripts, self.data.scriptOverrides = data.scripts, data.scriptOverrides
end
function Document:isDirty() return self:snapshot() ~= self.savedSnapshot end
function Document:save()
    local ok, err = self.project:saveScripts()
    if ok then self.savedSnapshot = self:snapshot() end
    return ok, err
end
return Document
