local Color = {}

function Color.rgb(value)
    if type(value) ~= "table" or #value ~= 3 then return nil, "Use three RGB values" end
    for i = 1, 3 do
        local channel = value[i]
        if type(channel) ~= "number" or channel ~= channel or channel < 0 or channel > 255 then
            return nil, "RGB values must be between 0 and 255"
        end
    end
    return {value[1], value[2], value[3]}
end

function Color.default()
    local color = require("editor.Theme").color("viewportBackground")
    return {color[1] * 255, color[2] * 255, color[3] * 255}
end

function Color.hex(value)
    return string.format("%02X%02X%02X", math.floor(value[1] + 0.5), math.floor(value[2] + 0.5), math.floor(value[3] + 0.5))
end

function Color.fromHex(text)
    local value = text:match("^%s*#?(%x%x%x%x%x%x)%s*$")
    if not value then return nil, "Use six hexadecimal digits, for example 2468AC" end
    return {tonumber(value:sub(1, 2), 16), tonumber(value:sub(3, 4), 16), tonumber(value:sub(5, 6), 16)}
end

function Color.toHsv(color)
    local r, g, b = color[1] / 255, color[2] / 255, color[3] / 255
    local maximum, minimum = math.max(r, g, b), math.min(r, g, b)
    local delta, hue = maximum - minimum, 0
    if delta > 0 then
        if maximum == r then hue = ((g - b) / delta) % 6
        elseif maximum == g then hue = (b - r) / delta + 2
        else hue = (r - g) / delta + 4 end
    end
    return hue / 6, maximum == 0 and 0 or delta / maximum, maximum
end

function Color.fromHsv(h, s, v)
    local c = v * s
    local x, m = c * (1 - math.abs((h * 6) % 2 - 1)), v - c
    local sector = math.floor(h * 6) % 6 + 1
    local rgb = ({{c, x, 0}, {x, c, 0}, {0, c, x}, {0, x, c}, {x, 0, c}, {c, 0, x}})[sector]
    return {(rgb[1] + m) * 255, (rgb[2] + m) * 255, (rgb[3] + m) * 255}
end

return Color
