local Theme = require("editor.theme")
local Widget = require("editor.ui.widget")
local UI = require("editor.ui")
local Menu = setmetatable({}, { __index = Widget })
Menu.__index = Menu
local WIDTH, ROW, PAD = 190, 30, 4

function Menu.new(root)
    local self = setmetatable(Widget.new(), Menu)
    self.root, self.panels = root, {}
    self.reopenOnRightClick = true
    return self
end

function Menu:show(x, y, items)
    self.panels = {}
    self:addPanel(x, y, items)
    self.root:setPopup(self)
end

function Menu:addPanel(x, y, items)
    local width, height = love.graphics.getDimensions()
    local panelWidth = math.min(width, self.menuWidth or WIDTH)
    self.panels[#self.panels + 1] = { x = math.max(0, math.min(x, width - panelWidth)),
        y = math.max(0, math.min(y, height - (#items * ROW + PAD * 2))),
        w = panelWidth, h = #items * ROW + PAD * 2, items = items, selected = 1 }
end

function Menu:at(x, y)
    for depth = #self.panels, 1, -1 do
        local panel = self.panels[depth]
        if UI.contains(x, y, panel) then
            local index = math.floor((y - panel.y - PAD) / ROW) + 1
            return depth, panel.items[index] and index or nil
        end
    end
end

function Menu:hitTest(x, y)
    return self:at(x, y) and self or nil
end

function Menu:select(depth, index)
    local panel = self.panels[depth]
    if not index then return end
    panel.selected = index
    for i = #self.panels, depth + 1, -1 do self.panels[i] = nil end
    local item = panel.items[index]
    if item.children and item.enabled ~= false then
        local x = panel.x + panel.w - 1
        if x + WIDTH > love.graphics.getWidth() then x = panel.x - WIDTH + 1 end
        self:addPanel(x, panel.y + PAD + (index - 1) * ROW, item.children)
    end
end

function Menu:activate(depth, index)
    local item = index and self.panels[depth].items[index]
    if not item or item.enabled == false then return end
    if item.children then self:select(depth, index); return end
    self.root:dismissPopup()
    if item.action then item.action() end
end

function Menu:dispatch(event, ...)
    if event == "mousemoved" or event == "mousepressed" then
        local x, y, button = ...
        local depth, index = self:at(x, y)
        if depth and index then
            if event == "mousemoved" then self:select(depth, index)
            elseif button == 1 then self:activate(depth, index) end
        end
    elseif event == "keypressed" then
        local key = ...
        local depth, panel = #self.panels, self.panels[#self.panels]
        if key == "up" then panel.selected = (panel.selected - 2) % #panel.items + 1
        elseif key == "down" then panel.selected = panel.selected % #panel.items + 1
        elseif key == "left" and depth > 1 then self.panels[depth] = nil
        elseif key == "right" and panel.items[panel.selected].children
            or key == "return" or key == "kpenter" then
            self:activate(depth, panel.selected)
        end
    end
    return true
end

function Menu:draw()
    for _, panel in ipairs(self.panels) do
        Theme.setColor("surface")
        love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h, 4, 4)
        Theme.setColor("border")
        love.graphics.rectangle("line", panel.x + 0.5, panel.y + 0.5, panel.w - 1, panel.h - 1, 4, 4)
        for i, item in ipairs(panel.items) do
            local y = panel.y + PAD + (i - 1) * ROW
            if i == panel.selected and item.enabled ~= false then
                Theme.setColor("selection")
                love.graphics.rectangle("fill", panel.x + PAD, y, panel.w - PAD * 2, ROW, 3, 3)
            end
            local shortcutWidth = item.shortcut and love.graphics.getFont():getWidth(item.shortcut) + 16 or 0
            UI.text(item.label, panel.x + 12, y + 7, panel.w - 38 - shortcutWidth,
                item.enabled == false and Theme.color("textDisabled") or nil)
            if item.shortcut then UI.text(item.shortcut, panel.x + panel.w - shortcutWidth - 8, y + 7, shortcutWidth, Theme.color("textMuted"), false, "right") end
            UI.hint({x = panel.x, y = y, w = panel.w, h = ROW},
                item.enabled == false and item.label .. " is unavailable here." or item.label .. ". Click or press Enter to select.")
            if item.children then UI.text(">", panel.x + panel.w - 22, y + 7) end
        end
    end
end

return Menu
