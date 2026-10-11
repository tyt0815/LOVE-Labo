local Theme = require("editor.Theme")
local Appearance = {}
local COLORS = {"prefabRed", "prefabGreen", "prefabBlue", "prefabYellow", "prefabCyan", "prefabMagenta"}

function Appearance.layout(rows, groupFor, keyFor)
    local groups, scopes, rootCount = {}, {}, 0
    for index, row in ipairs(rows) do
        local key, reference = groupFor(row.object)
        local scope = scopes[row.depth - 1]
        -- 독립 루트는 현재 트리 순서대로 새 팔레트를 시작한다.
        if reference and not scope then
            rootCount = rootCount + 1
            scope = {start = rootCount - 1, colors = {}, count = 0}
        end
        if reference and not scope.colors[reference] then
            scope.colors[reference] = (scope.start + scope.count) % #COLORS + 1
            scope.count = scope.count + 1
        end
        local colorIndex = reference and scope.colors[reference]
        groups[index] = {key = key, reference = reference, colorIndex = colorIndex,
            isRoot = key ~= nil and key == keyFor(row.object)}
        scopes[row.depth] = scope
    end
    return groups
end
function Appearance.textColor(group)
    return group.colorIndex and Theme.color(COLORS[group.colorIndex]) or Theme.color("text")
end
function Appearance.icon(x, y)
    require("editor.Theme").setColor("text")
    love.graphics.polygon("line", x, y - 5, x + 5, y - 2, x + 5, y + 4, x, y + 7, x - 5, y + 4, x - 5, y - 2)
    love.graphics.line(x - 5, y - 2, x, y + 1, x + 5, y - 2)
    love.graphics.line(x, y + 1, x, y + 7)
end
return Appearance
