local Model = require("Examples.StageModel")
local Workspace = require("project.Workspace")
local Editor = {properties = {workspace = {type = "string", default = ""}, drawOrder = {type = "number", default = 100}}}
function Editor:load(world)
    self.view = require("Engine.Rendering").createView(world, {owner = self, projection = {width = 1280, height = 720}})
    local root = self.workspace
    for index, value in ipairs(arg or {}) do if value == "--workspace" then root = arg[index + 1] end end
    if root == "" then root = love.filesystem.getSaveDirectory() .. "/Content/" .. self:getProject().saveIdentity end
    Workspace.ensureDirectory(root)
    self.content = Workspace.new(root)
    self.content:withLock(function()
        local Fs = require("project.NativeFileSystem")
        if not Fs.info(self.content:path("Stage.json")) then
            local data = Model.add(Model.new("My first stage"), 1, 2)
            self.content:writeJson("Stage.json", data, false)
        end
    end)
    self:reload()
end
function Editor:reload()
    local ok, err = pcall(function()
        self.content:withLock(function()
            local data, revision = self.content:readJson("Stage.json")
            self.data, self.revision = Model.validate(data), revision
        end)
    end)
    self.status = ok and "Reloaded Stage.json" or tostring(err)
end
function Editor:keypressed(key)
    if key == "r" then self:reload()
    elseif key == "left" or key == "right" then Model.moveFirst(self.data, key == "left" and -1 or 1); self.status = "Changed in memory; S saves"
    elseif key == "s" then
        local ok, err = pcall(function()
            self.content:withLock(function() self.revision = self.content:writeJson("Stage.json", Model.validate(self.data), self.revision) end)
        end)
        self.status = ok and "Saved Stage.json" or tostring(err)
    end
end
function Editor:draw(context)
    context:withScreen(function()
        love.graphics.setColor(0.08, 0.09, 0.11, 1); love.graphics.rectangle("fill", 0, 0, context.viewport.width, context.viewport.height)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Shared stage editor / game CLI: " .. (self.data and self.data.name or ""), 40, 30)
        love.graphics.printf(self.content.root, 40, 65, context.viewport.width - 80)
        love.graphics.print("Left/Right: move first note | S: save | R: reload external changes", 40, 110)
        love.graphics.print(self.status or "", 40, 145)
        local laneHeight = math.max(60, context.viewport.height - 240)
        for lane = 1, 4 do
            love.graphics.setColor(0.25, 0.27, 0.3, 1); love.graphics.rectangle("line", 80 + (lane - 1) * 130, 220, 110, laneHeight)
        end
        for _, note in ipairs(self.data and self.data.notes or {}) do
            love.graphics.setColor(0.15, 0.6, 1, 1); love.graphics.rectangle("fill", 90 + (note.lane - 1) * 130, 230 + note.beat * 28 % math.max(1, laneHeight - 30), 90, 16)
        end
    end)
end
function Editor:unload() if self.view then self.view:release() end end
return Editor
