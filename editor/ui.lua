local Theme = require("editor.theme")
local Utf8 = require("utf8")
local UI = {}

function UI.contains(x, y, rect)
    return x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h
end

function UI.text(text, x, y, width, color, bold)
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
    love.graphics.print(text, x, y)
    -- 시스템 폰트 경로에 의존하지 않고 현재 폰트의 글자 굵기만 강조한다.
    if bold then love.graphics.print(text, x + 0.75, y) end
end

function UI.label(text, x, y, width)
    UI.text(text, x, y, width, Theme.color("text"), true)
end

function UI.button(label, rect, active)
    local mx, my = love.mouse.getPosition()
    if active then Theme.setColor("selection")
    elseif UI.contains(mx, my, rect) then Theme.setColor("hover")
    else Theme.setColor("button") end
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 4, 4)
    UI.text(label, rect.x + 10, rect.y + (rect.h - love.graphics.getFont():getHeight()) / 2, rect.w - 20)
end

function UI.field(text, rect, focused)
    Theme.setColor("input")
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 3, 3)
    Theme.setColor(focused and "focus" or "border")
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 3, 3)
    love.graphics.setScissor(rect.x + 8, rect.y, math.max(0, rect.w - 16), rect.h)
    local font = love.graphics.getFont()
    local left = rect.x + 8
    if focused then left = math.min(left, rect.x + rect.w - 12 - font:getWidth(text)) end
    UI.text(text, left, rect.y + (rect.h - font:getHeight()) / 2)
    if focused then
        local cursor = left + font:getWidth(text) + 2
        Theme.setColor("focus")
        love.graphics.line(cursor, rect.y + 8, cursor, rect.y + rect.h - 8)
    end
    love.graphics.setScissor()
end

function UI.editKey(text, key, replace)
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

return UI
