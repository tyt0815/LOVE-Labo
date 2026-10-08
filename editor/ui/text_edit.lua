local Utf8 = require("utf8")
local Edit = {}
-- cursor/anchor는 UTF-8 바이트가 아닌 문자 경계 인덱스(0..문자 수)다.
local function count(text) return Utf8.len(text) or 0 end
local function prefix(text, position)
    local offset = Utf8.offset(text, position + 1)
    return offset and text:sub(1, offset - 1) or text
end
local function suffix(text, position) return text:sub(#prefix(text, position) + 1) end
function Edit.begin(owner, text, selected)
    owner.editState = {text = text, cursor = count(text), anchor = selected and 0 or count(text), scroll = 0}
    return owner.editState
end
function Edit.sync(owner, text, selected)
    if not owner.editState or owner.editState.text ~= text then return Edit.begin(owner, text, selected) end
    if selected then
        owner.editState.anchor, owner.editState.cursor = 0, count(text)
        owner.editState.displayCursor = owner.editState.cursor
    end
    return owner.editState
end
function Edit.range(state) return math.min(state.cursor, state.anchor), math.max(state.cursor, state.anchor) end
function Edit.insert(owner, text, inserted, selected)
    local state = Edit.sync(owner, text, selected)
    local first, last = Edit.range(state)
    text = prefix(text, first) .. inserted .. suffix(text, last)
    state.text, state.cursor = text, first + count(inserted)
    state.anchor, state.dragging = state.cursor, nil
    state.displayCursor, state.compositionStart = state.cursor, nil
    return text, false
end
function Edit.preview(owner, text, selected, composition)
    -- 조합 문자열은 저장값을 수정하지 않고 선택 범위에 끼워 넣어 표시한다.
    local state = Edit.sync(owner, text, selected)
    local first, last = Edit.range(state)
    state.displayCursor, state.compositionStart = state.cursor, nil
    if composition then
        state.compositionStart, state.displayCursor = first, first + count(composition)
        return prefix(text, first) .. composition .. suffix(text, last)
    end
    return text
end
local function wordPosition(text, cursor, direction)
    local n = count(text)
    local function space(index) return suffix(prefix(text, index + 1), index):match("%s") ~= nil end
    if direction < 0 then
        while cursor > 0 and space(cursor - 1) do cursor = cursor - 1 end
        while cursor > 0 and not space(cursor - 1) do cursor = cursor - 1 end
    else
        while cursor < n and not space(cursor) do cursor = cursor + 1 end
        while cursor < n and space(cursor) do cursor = cursor + 1 end
    end
    return cursor
end
function Edit.key(owner, text, key, selected)
    local state = Edit.sync(owner, text, selected)
    local ctrl, shift = love.keyboard.isDown("lctrl", "rctrl"), love.keyboard.isDown("lshift", "rshift")
    local first, last = Edit.range(state)
    if ctrl and key == "a" then state.anchor, state.cursor = 0, count(text)
    elseif ctrl and (key == "c" or key == "x") then
        if first ~= last then
            love.system.setClipboardText(suffix(prefix(text, last), first))
            if key == "x" then return Edit.insert(owner, text, "", false) end
        end
    elseif ctrl and key == "v" then return Edit.insert(owner, text, love.system.getClipboardText():gsub("[%z\r\n]", ""), false)
    elseif key == "left" or key == "right" or key == "home" or key == "end" then
        local target
        if key == "home" then target = 0
        elseif key == "end" then target = count(text)
        elseif not shift and first ~= last then target = key == "left" and first or last
        elseif ctrl then target = wordPosition(text, state.cursor, key == "left" and -1 or 1)
        else target = math.max(0, math.min(count(text), state.cursor + (key == "left" and -1 or 1))) end
        state.cursor = target
        if not shift then state.anchor = target end
    elseif key == "backspace" or key == "delete" then
        if first == last then
            if key == "backspace" then state.anchor = ctrl and wordPosition(text, first, -1) or math.max(0, first - 1)
            else state.cursor = ctrl and wordPosition(text, last, 1) or math.min(count(text), last + 1) end
        end
        return Edit.insert(owner, text, "", false)
    end
    state.displayCursor, state.dragging = state.cursor, nil
    return text, false
end
function Edit.geometry(owner, displayed, rect)
    local state, font = owner.editState, love.graphics.getFont()
    local caret = state.displayCursor or state.cursor
    local width = font:getWidth(prefix(displayed, caret))
    local available = math.max(1, rect.w - 20)
    state.scroll = math.max(0, math.min(state.scroll, math.max(0, font:getWidth(displayed) - available)))
    if width - state.scroll > available then state.scroll = width - available end
    if width - state.scroll < 0 then state.scroll = width end
    return rect.x + 8 - state.scroll, width
end
local function position(owner, text, rect, x)
    local left = Edit.geometry(owner, text, rect)
    local font, previous = love.graphics.getFont(), 0
    for index = 1, count(text) do
        local width = font:getWidth(prefix(text, index))
        if x - left < (previous + width) / 2 then return index - 1 end
        previous = width
    end
    return count(text)
end
function Edit.press(owner, text, rect, x, selectAll)
    local state = Edit.sync(owner, text, selectAll)
    state.displayCursor, state.compositionStart = state.cursor, nil
    local cursor = position(owner, text, rect, x)
    if not selectAll then
        state.cursor = cursor
        if not love.keyboard.isDown("lshift", "rshift") then state.anchor = cursor end
    end
    state.dragAnchor = selectAll and cursor or state.anchor
    state.displayCursor = state.cursor
    state.dragging, state.rect, state.pressX, state.dragMoved = true, rect, x, false
end
function Edit.move(owner, x)
    local state = owner.editState
    if not state or not state.dragging then return false end
    if x ~= state.pressX then state.dragMoved = true end
    if state.dragMoved then
        state.cursor, state.anchor = position(owner, state.text, state.rect, x), state.dragAnchor
        state.displayCursor = state.cursor
        owner.replace, owner.replaceOnTextInput = false, false
    end
    return true
end
function Edit.release(owner)
    if owner.editState then owner.editState.dragging = nil end
end
Edit.prefix = prefix
return Edit
