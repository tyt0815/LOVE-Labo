local Json = require("editor.Json")
local Theme = {}

-- 기본 테마의 유일한 원본이다. 외부 파일 없이도 모든 UI가 그려진다.
-- 공통 역할을 공유하되 독립적인 조절이 필요한 UI에는 용도별 색을 제공한다.
local DEFAULT_COLORS = {
    -- 제공된 UE 에디터 화면을 참고한 중성 회색 계층과 파란 선택 강조다.
    background = "#141414", panel = "#1B1B1B", viewportBackground = "#242424", surface = "#2B2B2B",
    button = "#333333", hover = "#3D3D3D", selection = "#344F69",
    border = "#414141", panelBorder = "#101010", panelTitle = "#D4D4D4",
    focus = "#008CFF", input = "#161616", textSelection = "#0078D799",
    treeLineHighlight = "#6A9BC4",
    pluginDependencyDisabled = "#E1A84B",
    playRunning = "#87B94A", playPaused = "#E1A84B",
    text = "#D0D0D0", textMuted = "#A3A3A3", textDisabled = "#777777", error = "#EF6A65",
    overlay = "#00000099", thumbnailBackground = "#242424",
    iconBackground = "#242424", iconBorder = "#666666", iconText = "#C8C8C8",
    assetLevel = "#63A9EC", assetPrefab = "#BA8CDB",
    prefabRed = "#EF7777", prefabGreen = "#8BC878", prefabBlue = "#79B2F0",
    prefabYellow = "#DDC36D", prefabCyan = "#71C7CF", prefabMagenta = "#D995D1",
    classLevel = "#63A9EC", classLObject = "#8BC878", classComponent = "#DDC36D",
    folderTab = "#9F854A", folderBody = "#C4A35B",
    grid = "#303030", axisX = "#DA5555", axisY = "#79B94A", axisZ = "#429CEF", origin = "#A3A3A3",
    object = "#D5A65D", objectSelected = "#008CFF", gameBackground = "#181818"
}

local function parseColor(value)
    if type(value) ~= "string" or (not value:match("^#%x%x%x%x%x%x$")
        and not value:match("^#%x%x%x%x%x%x%x%x$")) then return nil end
    return { tonumber(value:sub(2, 3), 16) / 255, tonumber(value:sub(4, 5), 16) / 255,
        tonumber(value:sub(6, 7), 16) / 255, #value == 9 and tonumber(value:sub(8, 9), 16) / 255 or 1 }
end

local function builtIn()
    local colors = {}
    for role, value in pairs(DEFAULT_COLORS) do colors[role] = parseColor(value) end
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
        if not DEFAULT_COLORS[role] then return nil, "Unknown theme color: " .. tostring(role) end
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
            local Fs = require("editor.HostFileSystem")
            local directory = love.filesystem.getSourceBaseDirectory()
            readFile = function(path)
                local relative = path:gsub("^editor/", "")
                return Fs.read(Fs.join(directory, relative))
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
