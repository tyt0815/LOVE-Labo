local UI = require("editor.ui")
local Theme = require("editor.theme")
local Layout = {rowHeight = 32, headerHeight = 26}
function Layout.cells(left, width, top)
    local labelLeft, split = left + UI.metrics.contentPaddingX + 12, left + width / 2
    local reset = {x = left + width - UI.metrics.contentPaddingX - 12 - 26, y = top + 3, w = 26, h = 26}
    return {x = labelLeft, y = top + 3 + (26 - love.graphics.getFont():getHeight()) / 2, w = math.max(0, split - labelLeft - 8), h = 20},
        {x = split + 4, y = top + 3, w = math.max(0, reset.x - UI.metrics.buttonGap - split - 4), h = 26}, reset
end
function Layout.separators(left, width, top)
    love.graphics.push("all")
    Theme.setColor("border")
    love.graphics.setLineWidth(1)
    local x, right, split = left + UI.metrics.contentPaddingX + 0.5, left + width - UI.metrics.contentPaddingX - 0.5, left + width / 2 + 0.5
    love.graphics.line(x, top + 0.5, right, top + 0.5)
    love.graphics.line(split, top + 0.5, split, top + Layout.rowHeight - 0.5)
    love.graphics.pop()
end
function Layout.groupHeaderHeight(expanded, height)
    return expanded and height > Layout.headerHeight and Layout.rowHeight or Layout.headerHeight
end
function Layout.group(left, width, top, height, label, expanded)
    local x, w = left + UI.metrics.contentPaddingX, width - 2 * UI.metrics.contentPaddingX
    local headerHeight = Layout.groupHeaderHeight(expanded, height)
    if expanded then
        Theme.setColor("surface")
        love.graphics.rectangle("fill", x, top, w, height, 4, 4)
        Theme.setColor("border")
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x + 0.5, top + 0.5, w - 1, height - 1, 4, 4)
    end
    UI.button("", {x = x, y = top, w = w, h = headerHeight}, false, "Click to expand or collapse properties.")
    UI.chevron(x + 10, top + headerHeight / 2, expanded)
    UI.text(label, x + 26, top + (headerHeight - love.graphics.getFont():getHeight()) / 2, w - 36)
end
return Layout
