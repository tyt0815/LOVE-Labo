local Json = require("editor.json")
local Theme = {}

-- 기본 테마의 유일한 원본이다. 외부 파일 없이도 모든 UI가 그려진다.
-- 공통 역할을 공유하되 독립적인 조절이 필요한 UI에는 용도별 색을 제공한다.
local defaults = {
    -- love2d.org/style/style.css와 box.svg의 배경·텍스트·강조색을 사용한다.
    background = "#B1E3FA", panel = "#B1E3FA", viewportBackground = "#E0F4FC", surface = "#E0F4FC",
    button = "#E0F4FC", hover = "#FFFFFF", selection = "#25AAE14D",
    border = "#4C90B166", panelBorder = "#4C90B166", panelTitle = "#1B4D68",
    focus = "#EA316E", input = "#FFFFFF", textSelection = "#258AE180",
    text = "#383F4A", textMuted = "#4C90B1", textDisabled = "#7798A9", error = "#EA316E",
    overlay = "#1B4D6866", thumbnailBackground = "#FFFFFF",
    iconBackground = "#FFFFFF", iconBorder = "#25AAE1", iconText = "#1B4D68",
    assetLevel = "#25AAE1", assetPrefab = "#EA316E",
    classLevel = "#1B4D68", classLObject = "#00A651", classComponent = "#4C90B1",
    folderTab = "#4C90B1", folderBody = "#25AAE1",
    grid = "#B1E3FA", axisX = "#EA316E", axisY = "#00A651", axisZ = "#25AAE1", origin = "#1B4D68",
    object = "#EA316E", objectSelected = "#00A651", gameBackground = "#E0F4FC"
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
    if not readFile then
        if love.filesystem.isFused() then
            -- 배포물의 설정은 작업 디렉터리와 무관하게 실행 파일 옆에서 읽는다.
            local FS = require("editor.host_filesystem")
            local directory = love.filesystem.getSourceBaseDirectory()
            readFile = function(path)
                local relative = path:gsub("^editor/", "")
                return FS.read(FS.join(directory, relative))
            end
        else readFile = love.filesystem.read end
    end
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
