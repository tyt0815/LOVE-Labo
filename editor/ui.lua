local Theme = require("editor.theme")
local Utf8 = require("utf8")
local Fonts = require("editor.fonts")
local UI = {}
function UI.beginFrame(x, y)
    UI.mouseX, UI.mouseY, UI.hoverHint = x, y, nil
end
function UI.hint(rect, text)
    if text and UI.mouseX and UI.contains(UI.mouseX, UI.mouseY, rect) then UI.hoverHint = text end
end
function UI.resetHints() UI.hoverHint = nil end

function UI.panel(x, y, width, height, backgroundRole)
    Theme.setColor(backgroundRole or "panel")
    love.graphics.rectangle("fill", x + 6, y + 6, math.max(0, width - 12), math.max(0, height - 12), 6, 6)
    Theme.setColor("panelBorder")
    love.graphics.rectangle("line", x + 6.5, y + 6.5, math.max(0, width - 13), math.max(0, height - 13), 6, 6)
end

function UI.panelTitle(text, x, y, width)
    love.graphics.push("all")
    love.graphics.setFont(Fonts.get(15, true))
    UI.text(text, x, y, width, Theme.color("panelTitle"), true)
    love.graphics.pop()
end

function UI.contains(x, y, rect)
    return x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h
end

function UI.text(text, x, y, width, color, bold)
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
    love.graphics.print(text, x, y)
    if bold then love.graphics.setFont(previousFont) end
end

function UI.label(text, x, y, width)
    UI.text(text, x, y, width, Theme.color("text"), true)
end

function UI.button(label, rect, active, hint)
    local hints = {Cancel = "Close this dialog without applying changes. Esc: cancel.",
        Create = "Create a new file or folder. Enter: confirm.", Save = "Save the document at the chosen path.",
        Move = "Move to the selected destination folder.", Rename = "Change the name in the current folder.",
        Delete = "Permanently delete this file or folder.", R = "Reset this property to its class default."}
    UI.hint(rect, hint or hints[label] or label)
    local mx, my = love.mouse.getPosition()
    if active then Theme.setColor("selection")
    elseif UI.contains(mx, my, rect) then Theme.setColor("hover")
    else Theme.setColor("button") end
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 4, 4)
    local padding = math.min(10, math.max(4, math.floor(rect.w * 0.2)))
    UI.text(label, rect.x + padding, rect.y + (rect.h - love.graphics.getFont():getHeight()) / 2, rect.w - padding * 2)
end

function UI.field(text, rect, focused)
    UI.hint(rect, "Edit the value. Enter: apply. Esc: cancel.")
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
