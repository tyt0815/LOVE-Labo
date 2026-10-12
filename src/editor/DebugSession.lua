local Transform = require("core.Transform")
local Session = {}
Session.__index = Session
local function finite(value) assert(Transform.finite(value), "Debug coordinates must be finite"); return value end
local function options(value)
    value = value or {}
    local color = assert(require("editor.Preview").color(value.color or {255, 150, 40}))
    local lifespan = value.lifespan == nil and 3 or finite(value.lifespan)
    assert(lifespan >= 0, "Debug lifespan must be non-negative")
    assert(value.key == nil or type(value.key) == "string" or type(value.key) == "number", "Debug key must be a string or number")
    return color, lifespan, value.key
end
function Session.new()
    return setmetatable({history = {}, screens = {}, shapes = {}, time = 0, revision = 0}, Session)
end
function Session:log(text, settings)
    local color = options(settings)
    local marker = settings and settings.marker
    if marker == nil then marker = "-" end
    assert(type(marker) == "string" and require("utf8").len(marker) == 1
        and not marker:find("%c"), "Debug log marker must be one printable character")
    local entry = {text = tostring(text), color = color, time = self.time, marker = marker}
    self.history[#self.history + 1] = entry
    if #self.history > 1000 then table.remove(self.history, 1) end
    self.latest, self.revision = entry, self.revision + 1
    return true
end
function Session:screenLog(text, settings)
    local color, lifespan, key = options(settings)
    if key ~= nil then for i = #self.screens, 1, -1 do if self.screens[i].key == key then table.remove(self.screens, i) end end end
    table.insert(self.screens, 1, {text = tostring(text), color = color, lifespan = lifespan, key = key, created = self.time})
    return true
end
function Session:addShape(kind, points, settings)
    local color, lifespan = options(settings)
    for _, value in ipairs(points) do finite(value) end
    self.shapes[#self.shapes + 1] = {kind = kind, points = points, color = color, lifespan = lifespan, created = self.time}
    return true
end
function Session:point(x, y, radius, settings)
    radius = radius or 3; assert(finite(radius) >= 0, "Debug radius must be non-negative")
    return self:addShape("point", {finite(x), finite(y), radius}, settings)
end
function Session:line(x1, y1, x2, y2, settings) return self:addShape("line", {finite(x1), finite(y1), finite(x2), finite(y2)}, settings) end
function Session:circle(x, y, radius, settings)
    assert(finite(radius) >= 0, "Debug radius must be non-negative")
    return self:addShape("circle", {finite(x), finite(y), radius}, settings)
end
function Session:rect(x, y, width, height, settings) return self:addShape("rect", {finite(x), finite(y), finite(width), finite(height)}, settings) end
function Session:polygon(points, settings)
    assert(type(points) == "table" and #points >= 6 and #points % 2 == 0, "Debug polygon needs at least three points")
    local copy = {}; for i, value in ipairs(points) do copy[i] = value end
    return self:addShape("polygon", copy, settings)
end
function Session:update(dt)
    assert(finite(dt) >= 0, "Debug delta time must be non-negative")
    self.time = self.time + dt
    for _, entries in ipairs({self.screens, self.shapes}) do
        for i = #entries, 1, -1 do
            local entry = entries[i]
            if entry.presented and self.time >= entry.created + entry.lifespan then table.remove(entries, i) end
        end
    end
end
function Session:finishFrame()
    for _, entries in ipairs({self.screens, self.shapes}) do
        for i = #entries, 1, -1 do
            local entry = entries[i]
            entry.presented = true
            if entry.lifespan == 0 then table.remove(entries, i) end
        end
    end
end
function Session:clearOverlay() self.screens, self.shapes = {}, {} end
function Session:bounds(script)
    local x, y, width, height = script:getBounds(self)
    if not x or width <= 0 or height <= 0 then return false end
    local transform, points = script:getWorldTransform(), {}
    for _, corner in ipairs({{x, y}, {x + width, y}, {x + width, y + height}, {x, y + height}}) do
        local px, py = Transform.point(transform, corner[1], corner[2])
        points[#points + 1] = px; points[#points + 1] = py
    end
    local color = self.color or {1, 0.59, 0.16}
    return self:polygon(points, {color = {color[1] * 255, color[2] * 255, color[3] * 255}})
end
function Session:drawShapes(toScreen)
    love.graphics.push("all")
    love.graphics.setLineWidth(1)
    for _, entry in ipairs(self.shapes) do
        local p, kind = entry.points, entry.kind
        love.graphics.setColor(entry.color[1] / 255, entry.color[2] / 255, entry.color[3] / 255, 1)
        local x, y = toScreen(p[1], p[2])
        if kind == "point" then love.graphics.circle("fill", x, y, p[3])
        elseif kind == "line" then local x2, y2 = toScreen(p[3], p[4]); love.graphics.line(x, y, x2, y2)
        else
            local points = {}
            local function push(px, py) local sx, sy = toScreen(px, py); points[#points + 1] = sx; points[#points + 1] = sy end
            if kind == "circle" then for i = 0, 63 do local angle = i * math.pi * 2 / 64; push(p[1] + math.cos(angle) * p[3], p[2] + math.sin(angle) * p[3]) end
            elseif kind == "rect" then push(p[1], p[2]); push(p[1] + p[3], p[2]); push(p[1] + p[3], p[2] + p[4]); push(p[1], p[2] + p[4])
            else for i = 1, #p, 2 do push(p[i], p[i + 1]) end end
            love.graphics.polygon("line", points)
        end
    end
    love.graphics.pop()
end
function Session:drawScreens(x, y, width, height)
    local Ui = require("editor.Ui")
    love.graphics.push("all"); love.graphics.intersectScissor(x, y, width, height)
    for _, entry in ipairs(self.screens) do
        Ui.text(entry.text, x, y, width, {entry.color[1] / 255, entry.color[2] / 255, entry.color[3] / 255, 1})
        y = y + 20
    end
    love.graphics.pop()
end
return Session
