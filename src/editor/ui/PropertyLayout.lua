local Ui = require("editor.Ui")
local Theme = require("editor.Theme")
local Layout = {ROW_HEIGHT = 32, HEADER_HEIGHT = 32, GROUP_INDENT = 14}
-- 재설정 버튼과 공통 패딩을 제외한 이름·값 영역의 비율. 기본은 1:1이다.
Layout.NAME_COLUMN_RATIO = 0.5
function Layout.columnSplit(left, width)
    local labelLeft = left + Ui.METRICS.contentPaddingX + 26
    local valueRight = left + width - Ui.METRICS.contentPaddingX - 12 - 26 - Ui.METRICS.buttonGap
    local available = math.max(0, valueRight - labelLeft - 12)
    return labelLeft + 8 + available * math.max(0, math.min(1, Layout.NAME_COLUMN_RATIO))
end
function Layout.cells(left, width, top)
    local labelLeft, split = left + Ui.METRICS.contentPaddingX + 26, Layout.columnSplit(left, width)
    local reset = {x = left + width - Ui.METRICS.contentPaddingX - 12 - 26, y = top + 3, w = 26, h = 26}
    return {x = labelLeft, y = top + 3 + (26 - love.graphics.getFont():getHeight()) / 2, w = math.max(0, split - labelLeft - 8), h = 20},
        {x = split + 4, y = top + 3, w = math.max(0, reset.x - Ui.METRICS.buttonGap - split - 4), h = 26}, reset
end
function Layout.separators(left, width, top, height, rightInset, indent, skipTop)
    love.graphics.push("all")
    Theme.setColor("border")
    love.graphics.setLineWidth(1)
    local x, right, split = left + Ui.METRICS.contentPaddingX + (indent or 0) + 0.5, left + width - (rightInset or 0) - Ui.METRICS.contentPaddingX - 0.5, Layout.columnSplit(left, width) + 0.5
    if not skipTop then love.graphics.line(x, top + 0.5, right, top + 0.5) end
    love.graphics.line(split, top + 0.5, split, top + (height or Layout.ROW_HEIGHT) - 0.5)
    love.graphics.pop()
end
function Layout.groupHeaderHeight(expanded, height)
    return Layout.HEADER_HEIGHT
end
function Layout.group(left, width, top, height, label, expanded, rightInset)
    local x, w = left + Ui.METRICS.contentPaddingX, width - 2 * Ui.METRICS.contentPaddingX
    local headerHeight = Layout.groupHeaderHeight(expanded, height)
    if expanded then
        Theme.setColor("surface")
        love.graphics.rectangle("fill", x, top, w, height, 4, 4)
        Theme.setColor("border")
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x + 0.5, top + 0.5, w - 1, height - 1, 4, 4)
    end
    Ui.button("", {x = x, y = top, w = w, h = headerHeight}, false, "Click to expand or collapse properties.")
    Ui.chevron(x + 10, top + headerHeight / 2, expanded)
    Ui.text(label, x + 26, top + (headerHeight - love.graphics.getFont():getHeight()) / 2, math.max(0, w - 36 - (rightInset or 0)))
end
function Layout.propertyGroup(left, width, top, height, label, expanded, rightInset)
    local x, w = left + Ui.METRICS.contentPaddingX, width - 2 * Ui.METRICS.contentPaddingX - (rightInset or 0)
    local headerHeight = Layout.groupHeaderHeight(expanded, height)
    Ui.row({x = x, y = top, w = w, h = headerHeight}, false)
    Layout.separators(left, width, top, headerHeight, rightInset)
    local labelRect = Layout.cells(left, width, top)
    Ui.chevron(x + 10, top + headerHeight / 2, expanded)
    Ui.text(label, labelRect.x, labelRect.y, labelRect.w)
    -- 자식 박스의 들여쓰기와 관계없이 헤더 아래 선은 전체 폭으로 이어진다.
    Theme.setColor("border")
    love.graphics.setLineWidth(1)
    love.graphics.line(x + 0.5, top + headerHeight - 0.5, x + w - 0.5, top + headerHeight - 0.5)
end
function Layout.groupBodyRect(left, width, top, height, rightInset)
    return {x = left + Ui.METRICS.contentPaddingX + Layout.GROUP_INDENT, y = top,
        w = math.max(0, width - 2 * Ui.METRICS.contentPaddingX - Layout.GROUP_INDENT - (rightInset or 0)), h = height}
end
function Layout.groupBody(left, width, top, height, rightInset)
    if height <= 0 then return end
    local rect = Layout.groupBodyRect(left, width, top, height, rightInset)
    Theme.setColor("surface")
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    Theme.setColor("border")
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", rect.x + 0.5, rect.y + 0.5, rect.w - 1, rect.h - 1)
end
return Layout
