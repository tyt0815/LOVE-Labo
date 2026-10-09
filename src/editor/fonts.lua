local Fonts = {DEFAULT_SIZE = 14}
local cache, sizes = {}, setmetatable({}, {__mode = "k"})

function Fonts.get(size, bold)
    size = size or Fonts.DEFAULT_SIZE
    local key = tostring(size) .. (bold and ":bold" or ":regular")
    if not cache[key] then
        local path = "editor/fonts/NanumSquareRound" .. (bold and "B" or "R") .. ".ttf"
        cache[key] = love.graphics.newFont(path, size)
        sizes[cache[key]] = size
    end
    return cache[key]
end

function Fonts.boldFor(font)
    return Fonts.get(sizes[font] or Fonts.DEFAULT_SIZE, true)
end

function Fonts.apply()
    love.graphics.setFont(Fonts.get())
end

return Fonts
