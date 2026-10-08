local Widget = require("editor.ui.widget")
local Layout = {}
Layout.__index = Layout

function Layout.new(app, canvas, slots)
    local self = setmetatable({ app = app, canvas = canvas, slots = slots, drag = nil, cursors = {} }, Layout)
    self.resizeWidget = Widget.new({
        hitTest = function(_, x, y) return self:edgesAt(x, y) ~= nil end,
        mousepressed = function(_, x, y, button)
            if button ~= 1 then return true end
            self.drag = self:edgesAt(x, y)
            app.isResizingAssets = self.drag and self.drag.assets or false
            return true, true
        end,
        mousemoved = function(_, x, y)
            if self.drag then self:resize(x, y) end
            self:updateCursor(x, y)
            return true
        end,
        mousereleased = function(_, _, _, button)
            if button == 1 then self.drag = nil; app.isResizingAssets = false end
            return true
        end
    })
    self.resizeSlot = canvas:addChild(self.resizeWidget, { fill = true, z = 100 })
    self.resizeWidget.focusable = false
    return self
end

function Layout:arrange(width, height)
    local app = self.app
    app.hierarchy.width = math.max(140, math.min(app.hierarchy.width, math.max(140, width - app.inspector.width - 160)))
    app.inspector.width = math.max(180, math.min(app.inspector.width, math.max(180, width - app.hierarchy.width - 160)))
    local browserHeight = 0
    if app.assetBrowser then
        browserHeight = app.assetBrowser.collapsed and 38 or math.max(100, math.min(app.assetBrowserHeight, height - 160))
    end
    self.editorHeight = math.max(0, height - browserHeight)
    self.width, self.height = width, height
    self.canvas:setBounds(0, 0, width, height)
    self.canvas:setSlotBounds(self.slots.hierarchy, 0, 0, app.hierarchy.width, self.editorHeight)
    self.canvas:setSlotBounds(self.slots.center, app.hierarchy.width, 0,
        math.max(0, width - app.hierarchy.width - app.inspector.width), self.editorHeight)
    self.canvas:setSlotBounds(self.slots.inspector, width - app.inspector.width, 0, app.inspector.width, height)
    if self.slots.assets then self.canvas:setSlotBounds(self.slots.assets, 0, self.editorHeight, width - app.inspector.width, browserHeight) end
end

function Layout:edgesAt(x, y)
    if not self.width or x < 0 or y < 0 or x >= self.width or y >= self.height then return nil end
    local app, edges = self.app, {}
    edges.hierarchy = math.abs(x - app.hierarchy.width) <= 3 and y <= self.editorHeight
    edges.inspector = math.abs(x - (self.width - app.inspector.width)) <= 3
    edges.assets = app.assetBrowser and not app.assetBrowser.collapsed
        and math.abs(y - self.editorHeight) <= 4 and x <= self.width - app.inspector.width + 3
    if edges.hierarchy or edges.inspector or edges.assets then return edges end
end

function Layout:resize(x, y)
    local app = self.app
    if self.drag.hierarchy then app.hierarchy.width = math.max(140, math.min(x, self.width - app.inspector.width - 160)) end
    if self.drag.inspector then app.inspector.width = math.max(180, math.min(self.width - x, self.width - app.hierarchy.width - 160)) end
    if self.drag.assets then app.assetBrowserHeight = math.max(100, math.min(self.height - y, self.height - 160)) end
    self:arrange(self.width, self.height)
end

function Layout:updateCursor(x, y)
    local edges = self.drag or self:edgesAt(x, y)
    local name = "arrow"
    if edges then
        local horizontal = edges.hierarchy or edges.inspector
        name = horizontal and (edges.assets and "sizenwse" or "sizewe") or "sizens"
    end
    if not self.cursors[name] then self.cursors[name] = love.mouse.getSystemCursor(name) end
    love.mouse.setCursor(self.cursors[name])
end

return Layout
