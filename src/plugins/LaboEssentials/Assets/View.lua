local Engine = require("Engine")
local View = Engine.Script:extend({scriptType = "View", properties = {
    cameraSource = {type = "script", default = false, group = "View"},
    renderOrder = {type = "number", default = 0, group = "View"},
    acceptInput = {type = "boolean", default = true, group = "View"}
}})
function View:load(world)
    assert(self.cameraSource ~= false, "View requires a projection source")
    self.renderView = Engine.Rendering.createView(world, {owner = self, order = self.renderOrder, input = self.acceptInput,
        filter = function(script)
            local object = script.owner
            while object do
                for _, id in ipairs(object.scriptOrder) do
                    local layout = object.scripts[id]
                    if type(layout.getViewSource) == "function" then
                        local source = layout:getViewSource()
                        if source then return source == self.cameraSource end
                    end
                end
                object = object.parent
            end
            return true
        end,
        projection = function()
            local source = self.cameraSource
            if source == false or not source.owner or source.owner:getWorld() ~= self:getWorld() or source.enabled == false or source.hasUnloaded then return nil end
            return source:getProjection()
        end})
end
function View:update()
    self.renderView:setOrder(self.renderOrder); self.renderView.input = self.acceptInput
end
function View:unload() if self.renderView then self.renderView:release() end end
return View
