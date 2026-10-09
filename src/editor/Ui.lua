local Theme = require("editor.Theme")
local Utf8 = require("utf8")
local Fonts = require("editor.Fonts")
local Ui = {}
-- 패널의 공통 여백과 글자 크기. 제목 좌표는 패널 바깥쪽 경계를 기준으로 한다.
Ui.METRICS = {
    titlePaddingX = 16, titlePaddingY = 14, titleFontSize = 15,
    contentPaddingX = 16, contentPaddingY = 4,
    buttonPaddingX = 10, buttonGap = 8,
    selectionPaddingX = 8, selectionPaddingY = 2, selectionRadius = 4,
}

function Ui.buttonWidth(label)
    return math.ceil(love.graphics.getFont():getWidth(label)) + 2 * Ui.METRICS.buttonPaddingX
end

function Ui.selection(x, y, width, height)
    local m = Ui.METRICS
    Theme.setColor("selection")
    love.graphics.rectangle("fill", x + m.selectionPaddingX, y + m.selectionPaddingY,
        math.max(0, width - 2 * m.selectionPaddingX), math.max(0, height - 2 * m.selectionPaddingY),
        m.selectionRadius, m.selectionRadius)
end

function Ui.panelHeading(text, x, y, width)
    local m = Ui.METRICS
    Ui.panelTitle(text, x + m.titlePaddingX, y + m.titlePaddingY, math.max(0, width - 2 * m.titlePaddingX))
end
function Ui.beginFrame(x, y)
    Ui.mouseX, Ui.mouseY, Ui.hoverHint = x, y, nil
end
function Ui.hint(rect, text)
    if text and Ui.mouseX and Ui.contains(Ui.mouseX, Ui.mouseY, rect) then Ui.hoverHint = text end
end
function Ui.resetHints() Ui.hoverHint = nil end

function Ui.panel(x, y, width, height, backgroundRole)
    Theme.setColor(backgroundRole or "panel")
    love.graphics.rectangle("fill", x + 6, y + 6, math.max(0, width - 12), math.max(0, height - 12), 6, 6)
    Theme.setColor("panelBorder")
    love.graphics.rectangle("line", x + 6.5, y + 6.5, math.max(0, width - 13), math.max(0, height - 13), 6, 6)
end

function Ui.panelTitle(text, x, y, width)
    love.graphics.push("all")
    love.graphics.setFont(Fonts.get(Ui.METRICS.titleFontSize, true))
    Ui.text(text, x, y, width, Theme.color("panelTitle"), true)
    love.graphics.pop()
end

function Ui.contains(x, y, rect)
    return x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h
end

function Ui.text(text, x, y, width, color, bold, alignment)
    local previousFont = love.graphics.getFont()
    if bold then love.graphics.setFont(Fonts.boldFor(previousFont)) end
    love.graphics.setColor(unpack(color or Theme.color("text")))
    if width then
        local font = love.graphics.getFont()
        if font:getWidth(text) > width then
            local chars = {}
            for _, code in Utf8.codes(text) do chars[#chars + 1] = Utf8.char(code) end
            while #chars > 0 and font:getWidth(table.concat(chars) .. "...") > width do
                chars[#chars] = nil
            end
            text = table.concat(chars) .. "..."
        end
    end
    if width and alignment == "center" then
        x = x + (width - love.graphics.getFont():getWidth(text)) / 2
    end
    love.graphics.print(text, x, y)
    if bold then love.graphics.setFont(previousFont) end
end

function Ui.label(text, x, y, width)
    Ui.text(text, x, y, width, Theme.color("text"), true)
end

function Ui.textLines(text, x, y, width, maxLines)
    local font = love.graphics.getFont()
    local _, lines = font:getWrap(text, width)
    local count = math.min(#lines, maxLines)
    if #lines > maxLines then
        local chars = {}
        for _, code in Utf8.codes(lines[count]) do chars[#chars + 1] = Utf8.char(code) end
        while #chars > 0 and font:getWidth(table.concat(chars) .. "...") > width do
            chars[#chars] = nil
        end
        lines[count] = table.concat(chars) .. "..."
    end
    local lineHeight = font:getHeight() * font:getLineHeight()
    for index = 1, count do
        Ui.text(lines[index], x, y + (index - 1) * lineHeight, width, nil, false, "center")
    end
end

function Ui.button(label, rect, active, hint, flat)
    local hints = {Cancel = "Close this dialog without applying changes. Esc: cancel.",
        Create = "Create a new file or folder. Enter: confirm.", Save = "Save the document at the chosen path.",
        Move = "Move to the selected destination folder.", Rename = "Change the name in the current folder.",
        Delete = "Permanently delete this file or folder.", R = "Reset this property to its class default."}
    Ui.hint(rect, hint or hints[label] or label)
    local mx, my = love.mouse.getPosition()
    local hovered = Ui.contains(mx, my, rect)
    if active then Theme.setColor("selection")
    elseif hovered then Theme.setColor("hover")
    else Theme.setColor("button") end
    if not flat or active or hovered then
        if flat and hovered and love.mouse.isDown(1) then Theme.setColor("selection") end
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 4, 4)
    end
    local padding = Ui.METRICS.buttonPaddingX
    Ui.text(label, rect.x + padding, rect.y + (rect.h - love.graphics.getFont():getHeight()) / 2,
        math.max(0, rect.w - padding * 2), nil, false, "center")
end

function Ui.resetButton(rect)
    Ui.button("", rect, false, "Reset to default.", true)
    love.graphics.push("all")
    Theme.setColor("textMuted")
    love.graphics.setLineWidth(1.5)
    local x, y, radius, points = rect.x + rect.w / 2, rect.y + rect.h / 2, 6, {}
    for i = 0, 24 do
        local angle = math.rad(30 - i * 300 / 24)
        points[#points + 1], points[#points + 2] = x + math.cos(angle) * radius, y + math.sin(angle) * radius
    end
    love.graphics.line(points)
    -- 글꼴에 의존하지 않는 되돌리기 화살표다.
    love.graphics.line(x - 3, y + radius - 3, x, y + radius, x - 3, y + radius + 3)
    love.graphics.pop()
end

function Ui.browseButton(rect, enabled, hint)
    Ui.button("", rect, false, hint or "Find resource in Asset Browser.", true)
    love.graphics.push("all")
    Theme.setColor(enabled and "textMuted" or "textDisabled")
    love.graphics.setLineWidth(1.5)
    local x, y = rect.x + rect.w / 2 - 2, rect.y + rect.h / 2 - 2
    love.graphics.circle("line", x, y, 5)
    love.graphics.line(x + 4, y + 4, x + 8, y + 8)
    love.graphics.pop()
end

function Ui.eyedropperButton(rect, active)
    Ui.button("", rect, active, "Pick an instance in the viewport. Esc: cancel.", true)
    love.graphics.push("all")
    Theme.setColor("textMuted")
    love.graphics.setLineWidth(1.5)
    local x, y = rect.x + rect.w / 2, rect.y + rect.h / 2
    love.graphics.line(x - 6, y + 6, x - 4, y + 1, x + 3, y - 6, x + 6, y - 3, x - 1, y + 4, x - 6, y + 6)
    love.graphics.line(x + 1, y - 6, x + 6, y - 1)
    love.graphics.pop()
end

function Ui.thumbnail(image, rect)
    love.graphics.push("all")
    Theme.setColor("input")
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 3, 3)
    if image then
        love.graphics.setColor(1, 1, 1, 1)
        local w, h = image:getDimensions()
        local scale = math.min((rect.w - 4) / w, (rect.h - 4) / h)
        love.graphics.draw(image, rect.x + (rect.w - w * scale) / 2, rect.y + (rect.h - h * scale) / 2, 0, scale, scale)
    else Ui.text("-", rect.x, rect.y + (rect.h - love.graphics.getFont():getHeight()) / 2, rect.w, Theme.color("textMuted"), false, "center") end
    Theme.setColor("border")
    love.graphics.rectangle("line", rect.x + 0.5, rect.y + 0.5, rect.w - 1, rect.h - 1, 3, 3)
    love.graphics.pop()
end

function Ui.chevron(x, y, expanded)
    love.graphics.push("all")
    Theme.setColor("textMuted")
    love.graphics.setLineWidth(1.5)
    if expanded then
        love.graphics.line(x, y - 2, x + 4, y + 2, x + 8, y - 2)
    else
        love.graphics.line(x + 2, y - 4, x + 6, y, x + 2, y + 4)
    end
    love.graphics.pop()
end

function Ui.field(text, rect, focused, composition, owner)
    love.graphics.push("all")
    love.graphics.setLineWidth(1)
    Ui.hint(rect, "Edit the value. Enter: apply. Esc: cancel.")
    Theme.setColor("input")
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 3, 3)
    Theme.setColor(focused and "focus" or "border")
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 3, 3)
    love.graphics.intersectScissor(rect.x + 8, rect.y, math.max(0, rect.w - 16), rect.h)
    local font = love.graphics.getFont()
    local left = rect.x + 8
    local Edit, state = require("editor.ui.TextEdit"), owner and owner.editState
    local scrubbing = owner and owner.numberDrag and owner.numberDrag.active
    local caretWidth
    if focused and state then
        left, caretWidth = Edit.geometry(owner, text, rect)
        if not composition and not scrubbing then
            local first, last = Edit.range(state)
            Theme.setColor("textSelection")
            love.graphics.rectangle("fill", left + font:getWidth(Edit.prefix(text, first)), rect.y + 3,
                font:getWidth(Edit.prefix(text, last)) - font:getWidth(Edit.prefix(text, first)), rect.h - 6)
        end
    elseif focused then left = math.min(left, rect.x + rect.w - 12 - font:getWidth(text)) end
    Ui.text(text, left, rect.y + (rect.h - font:getHeight()) / 2)
    if focused and composition then
        Theme.setColor("focus")
        local right = left + (caretWidth or font:getWidth(text))
        love.graphics.line(right - font:getWidth(composition), rect.y + (rect.h + font:getHeight()) / 2,
            right, rect.y + (rect.h + font:getHeight()) / 2)
    end
    if focused and not scrubbing and (composition or not state or state.cursor == state.anchor) then
        local cursor = left + (caretWidth or font:getWidth(text)) + 1
        Theme.setColor("focus")
        love.graphics.line(cursor, rect.y + 4, cursor, rect.y + rect.h - 4)
    end
    love.graphics.pop()
end

function Ui.editKey(text, key, replace, owner)
    if owner then return require("editor.ui.TextEdit").key(owner, text, key, replace) end
    local control = love.keyboard.isDown("lctrl", "rctrl")
    if control and key == "a" then return text, true end
    if control and key == "v" then
        local clipboard = love.system.getClipboardText():gsub("[%z\r\n]", "")
        return (replace and "" or text) .. clipboard, false
    end
    if control and key == "c" then love.system.setClipboardText(text) end
    if key == "backspace" then
        if replace then return "", false end
        local offset = Utf8.offset(text, -1)
        return offset and text:sub(1, offset - 1) or "", false
    end
    if key == "delete" and replace then return "", false end
    return text, replace
end

return Ui
