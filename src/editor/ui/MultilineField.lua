local Edit = require("editor.ui.TextEdit")
local Theme = require("editor.Theme")
local Field = {}
function Field.layout(owner, text)
    local font, lines, start, line = love.graphics.getFont(), {}, 0, ""
    local count = require("utf8").len(text) or 0
    for index = 1, count do
        local character = Edit.prefix(text, index):sub(#Edit.prefix(text, index - 1) + 1)
        if line ~= "" and font:getWidth(line .. character) > math.max(1, owner.rect.w - 16) then
            lines[#lines + 1] = {text = line, start = start}; start, line = index - 1, ""
        end
        line = line .. character
    end
    lines[#lines + 1] = {text = line, start = start}
    owner.lineHeight = math.max(24, font:getHeight() + 8)
    owner.rect.h = math.min(#lines * owner.lineHeight, love.graphics.getHeight() - 16)
    owner.rect.y = math.min(owner.baseY or owner.rect.y, love.graphics.getHeight() - owner.rect.h - 8)
    owner.lines = lines; return lines
end
function Field.position(owner, x, y)
    local lines = Field.layout(owner, owner.text)
    local row = math.max(1, math.min(#lines, math.floor((y - owner.rect.y) / owner.lineHeight) + 1 + (owner.lineScroll or 0)))
    local line, font = lines[row], love.graphics.getFont()
    local count = require("utf8").len(line.text) or 0
    for index = 1, count do
        local previous, width = font:getWidth(Edit.prefix(line.text, index - 1)), font:getWidth(Edit.prefix(line.text, index))
        if x - owner.rect.x - 8 < (previous + width) / 2 then return line.start + index - 1 end
    end
    return line.start + count
end
function Field.press(owner, x, y, dragging)
    local state = Edit.sync(owner, owner.text)
    local cursor = Field.position(owner, x, y)
    if not dragging then state.dragging = true; state.dragAnchor = love.keyboard.isDown("lshift", "rshift") and state.anchor or cursor end
    state.cursor, state.anchor, state.displayCursor = cursor, state.dragAnchor, cursor
end
function Field.key(owner, key)
    if key ~= "up" and key ~= "down" then return false end
    local state = Edit.sync(owner, owner.text); local lines = Field.layout(owner, owner.text)
    local row = 1; for index, line in ipairs(lines) do if line.start <= state.cursor then row = index end end
    local x = owner.rect.x + 8 + love.graphics.getFont():getWidth(Edit.prefix(lines[row].text, state.cursor - lines[row].start))
    state.cursor = Field.position(owner, x, owner.rect.y + (row - 1 - (owner.lineScroll or 0) + (key == "up" and -1 or 1)) * owner.lineHeight)
    if not love.keyboard.isDown("lshift", "rshift") then state.anchor = state.cursor end
    return true
end
function Field.draw(owner, text)
    local lines = Field.layout(owner, text); local state, rect, font = owner.editState, owner.rect, love.graphics.getFont()
    local cursor = state.displayCursor or state.cursor
    local row = 1; for index, line in ipairs(lines) do if line.start <= cursor then row = index end end
    local visible = math.max(1, math.floor(rect.h / owner.lineHeight))
    owner.lineScroll = math.max(0, math.max(row - visible, math.min(owner.lineScroll or 0, row - 1)))
    love.graphics.push("all"); Theme.setColor("input"); love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 3, 3)
    Theme.setColor("focus"); love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 3, 3)
    love.graphics.intersectScissor(rect.x, rect.y, rect.w, rect.h)
    local first, last = Edit.range(state)
    for index = owner.lineScroll + 1, math.min(#lines, owner.lineScroll + visible) do
        local line = lines[index]; local count = require("utf8").len(line.text) or 0
        local y = rect.y + (index - 1 - owner.lineScroll) * owner.lineHeight
        local a, b = math.max(0, first - line.start), math.min(count, last - line.start)
        if b > a and not owner.composition then
            Theme.setColor("textSelection"); love.graphics.rectangle("fill", rect.x + 8 + font:getWidth(Edit.prefix(line.text, a)), y + 3,
                font:getWidth(Edit.prefix(line.text, b)) - font:getWidth(Edit.prefix(line.text, a)), owner.lineHeight - 6)
        end
        Theme.setColor("text"); love.graphics.print(line.text, rect.x + 8, y + 4)
        if index == row and (first == last or owner.composition) then
            local x = rect.x + 8 + font:getWidth(Edit.prefix(line.text, cursor - line.start))
            Theme.setColor("focus"); love.graphics.line(x, y + 4, x, y + owner.lineHeight - 4)
        end
    end
    love.graphics.pop()
end
return Field
