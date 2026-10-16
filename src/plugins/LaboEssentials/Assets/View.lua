local Rendering = require("Engine").Rendering
local View = require("core.Script"):extend({scriptType = "View", properties = {
    cameraSource = {type = "script", default = false, group = "View"},
    renderOrder = {type = "number", default = 0, group = "View"},
    includeWorld = {type = "boolean", default = true, group = "View"},
    includeScreen = {type = "boolean", default = true, group = "View"},
    acceptInput = {type = "boolean", default = true, group = "View"}
}})
function View:load(world)
    assert(self.cameraSource ~= false, "View requires a Camera script reference")
    self.renderView = Rendering.createView(world, {camera = self.cameraSource, owner = self,
        order = self.renderOrder, includeWorld = self.includeWorld, includeScreen = self.includeScreen, input = self.acceptInput})
end
function View:update()
    local camera = self.cameraSource or nil
    if self.renderView.camera ~= camera then self.renderView:setCamera(camera) end
    self.renderView:setOrder(self.renderOrder)
    self.renderView.includeWorld, self.renderView.includeScreen, self.renderView.input = self.includeWorld, self.includeScreen, self.acceptInput
end
function View:unload()
    if self.renderView then self.renderView:release() end
end
return View
