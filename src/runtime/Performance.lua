local Performance = {}
Performance.__index = Performance
function Performance.new()
    return setmetatable({recording = true, detailed = false, frames = {}, scripts = {}, limit = 300}, Performance)
end
function Performance:sample(kind, script, seconds)
    if not self.recording or not self.detailed then return end
    local owner = script.owner
    local key = kind .. ":" .. tostring(owner) .. ":" .. tostring(script.id or "legacy")
    if not self.scripts[key] then
        self.scriptCount = (self.scriptCount or 0) + 1
        if self.scriptCount > 2048 then key = kind .. ":overflow" end
    end
    local overflow = key == kind .. ":overflow"
    local entry = self.scripts[key] or {kind = kind, name = overflow and "Other scripts (limit)" or script.name or "Level", owner = not overflow and owner and owner.runtimeId or nil, calls = 0, totalMs = 0, maxMs = 0}
    entry.calls, entry.totalMs, entry.maxMs = entry.calls + 1, entry.totalMs + seconds * 1000, math.max(entry.maxMs, seconds * 1000)
    self.scripts[key] = entry
end
function Performance:frame(frame)
    if not self.recording then return end
    self.frames[#self.frames + 1] = frame
    if #self.frames > self.limit then table.remove(self.frames, 1) end
end
function Performance:report()
    local scripts, average, maximum = {}, 0, 0
    for _, entry in pairs(self.scripts) do scripts[#scripts + 1] = entry end
    table.sort(scripts, function(a, b) return a.totalMs > b.totalMs end)
    for _, frame in ipairs(self.frames) do average = average + frame.frameMs; maximum = math.max(maximum, frame.frameMs) end
    return {version = 1, frames = self.frames, scripts = scripts, averageMs = #self.frames > 0 and average / #self.frames or 0,
        maxMs = maximum, detailed = self.detailed, timing = "CPU wall time; memory includes editor/shared resources"}
end
function Performance:clear() self.frames, self.scripts, self.scriptCount = {}, {}, 0 end
return Performance
