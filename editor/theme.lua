local Json = require("editor.json")
local Theme = {}

-- 기본 테마의 유일한 원본이다. 외부 파일 없이도 모든 UI가 그려진다.
-- 공통 역할을 공유하되 독립적인 조절이 필요한 UI에는 용도별 색을 제공한다.
local defaults = {
    background = "#14171C", panel = "#1B1F25", surface = "#222831",
    button = "#2B313D", hover = "#3D4554", selection = "#335C8C",
    border = "#474D59", focus = "#66A6E6", input = "#13161B",
    text = "#DFE3ED", textMuted = "#A6AFBF", textDisabled = "#737B87", error = "#FF8C80",
    overlay = "#0000008C", thumbnailBackground = "#FFFFFF",
    iconBackground = "#FFFFFF", iconBorder = "#739CD1", iconText = "#325AA3",
    assetLevel = "#4078F2", assetPrefab = "#A626A4",
    classLevel = "#0184BC", classLObject = "#50A14F", classComponent = "#986801",
    folderTab = "#C29140", folderBody = "#E6B857",
    grid = "#292B33", axisX = "#BF5252", axisY = "#52B361", origin = "#EBEBF0",
    object = "#FF6666", objectSelected = "#66E68C", gameBackground = "#090A0D"
}

local function parseColor(value)
    if type(value) ~= "string" or (not value:match("^#%x%x%x%x%x%x$")
        and not value:match("^#%x%x%x%x%x%x%x%x$")) then return nil end
    return { tonumber(value:sub(2, 3), 16) / 255, tonumber(value:sub(4, 5), 16) / 255,
        tonumber(value:sub(6, 7), 16) / 255, #value == 9 and tonumber(value:sub(8, 9), 16) / 255 or 1 }
end

local function builtIn()
    local colors = {}
    for role, value in pairs(defaults) do colors[role] = parseColor(value) end
    return colors
end

local function decodeTheme(text, base)
    local data, err = Json.decode(text)
    if type(data) ~= "table" or data.version ~= 1 or type(data.colors) ~= "table" then
        return nil, err or "Invalid theme format"
    end
    local colors = {}
    for role, value in pairs(base) do colors[role] = { unpack(value) } end
    for role, value in pairs(data.colors) do
        if not defaults[role] then return nil, "Unknown theme color: " .. tostring(role) end
        local color = parseColor(value)
        if not color then return nil, "Invalid theme color: " .. role end
        colors[role] = color
    end
    return colors
end

Theme.colors, Theme.name = builtIn(), "default"

function Theme.load(readFile)
    readFile = readFile or love.filesystem.read
    local function read(path)
        local ok, text = pcall(readFile, path)
        return ok and type(text) == "string" and text or nil
    end
    local base = builtIn()
    -- 이전 테마가 남지 않도록 매번 기본 팔레트부터 선택한다.
    Theme.colors, Theme.name, Theme.lastError = base, "default", nil
    local settingsText = read("editor/settings.json")
    if not settingsText then return true end
    local settings, err = Json.decode(settingsText)
    if type(settings) ~= "table" or settings.version ~= 1 then
        Theme.lastError = err or "Invalid editor settings format"
    elseif settings.theme == nil or settings.theme == "default" then
        return true
    elseif type(settings.theme) ~= "string" or not settings.theme:match("^[%w_-]+$") then
        Theme.lastError = "Invalid theme name"
    else
        local text = read("editor/themes/" .. settings.theme .. ".json")
        local colors, themeError
        if text then colors, themeError = decodeTheme(text, base) end
        if colors then Theme.colors, Theme.name = colors, settings.theme; return true end
        Theme.lastError = themeError or "Theme file not found"
    end
    return false, Theme.lastError
end

function Theme.color(role, opacity)
    local color = assert(Theme.colors[role], "Unknown theme role: " .. tostring(role))
    if opacity then return {color[1], color[2], color[3], color[4] * opacity} end
    return color
end

function Theme.setColor(role, opacity)
    love.graphics.setColor(unpack(Theme.color(role, opacity)))
end

function Theme.clear(role)
    love.graphics.clear(unpack(Theme.color(role)))
end

function Theme.mix(first, second, amount)
    local a, b, result = Theme.color(first), Theme.color(second), {}
    for i = 1, 4 do result[i] = a[i] + (b[i] - a[i]) * amount end
    return result
end

return Theme
