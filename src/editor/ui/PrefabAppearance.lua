local Appearance = {}
-- 펼침 화살표 중앙을 기준으로 한 범위선의 가로 이동량. 두 계층에 함께 적용한다.
local RANGE_OFFSET_X = 0
-- 화살표 아래의 시작점만 위아래로 이동한다. 이어지는 자손 행은 유지한다.
local RANGE_START_OFFSET_Y = 0
function Appearance.layout(rows, groupFor, keyFor)
    local groups, depths, counts = {}, {}, {}
    for _, row in ipairs(rows) do depths[keyFor(row.object)] = row.depth end
    for index, row in ipairs(rows) do
        local key, reference = groupFor(row.object)
        groups[index] = {key = key, reference = reference, depth = depths[key], isRoot = key and key == keyFor(row.object)}
        if key then counts[key] = (counts[key] or 0) + 1 end
    end
    for index, group in ipairs(groups) do
        group.first = index == 1 or groups[index - 1].key ~= group.key
        group.last = index == #groups or groups[index + 1].key ~= group.key
        group.showRange = group.key ~= nil and counts[group.key] > 1
    end
    return groups
end
function Appearance.range(x, y, height, selected, first, last, isRoot, branchEndX)
    x = x + RANGE_OFFSET_X
    require("editor.Theme").setColor(selected and "focus" or "textMuted")
    love.graphics.setLineWidth(selected and 2 or 1)
    local top = y + (isRoot and height / 2 + 6 + RANGE_START_OFFSET_Y or first and height / 2 or 0)
    local bottom = y + (last and height / 2 or height)
    local branchEnd = math.max(x, branchEndX)
    love.graphics.line(x, top, x, bottom)
    if first and not isRoot then love.graphics.line(x, top, branchEnd, top) end
    if last then love.graphics.line(x, bottom, branchEnd, bottom) end
    love.graphics.setLineWidth(1)
end
function Appearance.icon(x, y)
    require("editor.Theme").setColor("text")
    love.graphics.polygon("line", x, y - 5, x + 5, y - 2, x + 5, y + 4, x, y + 7, x - 5, y + 4, x - 5, y - 2)
    love.graphics.line(x - 5, y - 2, x, y + 1, x + 5, y - 2)
    love.graphics.line(x, y + 1, x, y + 7)
end
return Appearance
