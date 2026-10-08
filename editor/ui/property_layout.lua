local UI = require("editor.ui")
local Theme = require("editor.theme")
local Layout = {rowHeight = 32, headerHeight = 26}
function Layout.cells(left, width, top)
    local labelLeft, split = left + UI.metrics.contentPaddingX + 12, left + width / 2
    local reset = {x = left + width - UI.metrics.contentPaddingX - 12 - 26, y = top + 3, w = 26, h = 26}
    return {x = labelLeft, y = top + 3 + (26 - love.graphics.getFont():getHeight()) / 2, w = math.max(0, split - labelLeft - 8), h = 20},
        {x = split + 4, y = top + 3, w = math.max(0, reset.x - UI.metrics.buttonGap - split - 4), h = 26}, reset
end
function Layout.group(left, width, top, height, label, expanded)
    local x, w = left + UI.metrics.contentPaddingX, width - 2 * UI.metrics.contentPaddingX
    if expanded then
        Theme.setColor("surface")
        love.graphics.rectangle("fill", x, top, w, height, 4, 4)
        Theme.setColor("border")
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x + 0.5, top + 0.5, w - 1, height - 1, 4, 4)
    end
    UI.button("", {x = x, y = top, w = w, h = Layout.headerHeight}, false, "Click to expand or collapse properties.")
    UI.chevron(x + 10, top + 13, expanded)
    UI.text(label, x + 26, top + (26 - love.graphics.getFont():getHeight()) / 2, w - 36)
end
return Layout
