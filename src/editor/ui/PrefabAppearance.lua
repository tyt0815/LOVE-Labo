local Appearance = {}
local COLORS = {{0.3, 0.6, 1}, {0.8, 0.45, 0.85}, {0.3, 0.8, 0.6}, {0.9, 0.65, 0.25}}
function Appearance.background(key, selected, rect)
    if not key then return end
    local hash = 0
    for index = 1, #tostring(key) do hash = (hash * 31 + tostring(key):byte(index)) % 65521 end
    local color = COLORS[hash % #COLORS + 1]
    love.graphics.setColor(color[1], color[2], color[3], selected and 0.2 or 0.08)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
end
return Appearance
