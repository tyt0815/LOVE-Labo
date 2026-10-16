local Space = require("core.CoordinateSpace")
local Order = {}
function Order.objects(objects)
    local ordered, visited, allowed = {}, {}, {}
    for _, object in ipairs(objects) do allowed[object] = true end
    local function visit(object)
        if visited[object] or not allowed[object] then return end
        visited[object] = true; ordered[#ordered + 1] = object
        for _, child in ipairs(object.children or {}) do visit(child) end
    end
    for _, object in ipairs(objects) do if not object.parent or not allowed[object.parent] then visit(object) end end
    for _, object in ipairs(objects) do visit(object) end
    return ordered
end
function Order.entries(objects, capability, predicate)
    local entries, indices, sequence = {}, {}, 0
    local ordered = Order.objects(objects)
    for _, object in ipairs(ordered) do
        local ids = capability == "draw" and object.drawScripts or nil
        if ids then
            for _, script in ipairs(ids) do sequence = sequence + 1; indices[script] = sequence end
        else
            for _, id in ipairs(object.scriptOrder) do sequence = sequence + 1; indices[object.scripts[id]] = sequence end
        end
        local candidates = {}
        if capability == "draw" then candidates = object.drawScripts
        else for _, id in ipairs(object.scriptOrder) do candidates[#candidates + 1] = object.scripts[id] end end
        for _, script in ipairs(candidates) do
            if script[capability] and script.enabled ~= false and (not predicate or predicate(script)) then
                entries[#entries + 1] = {script = script, index = indices[script] or sequence, sequence = #entries + 1}
            end
        end
    end
    for _, entry in ipairs(entries) do
        local script = entry.script
        local pointer = capability == "pointer"
        local source = pointer and script:getBoundsSource() or script
        entry.layer = capability ~= "drawScreen" and Space.canvas(source) and 1 or 0
        entry.order = source.drawOrder ~= 0 and source.drawOrder or source.properties.sortingOrder or 0
        entry.priority = pointer and script.properties.inputPriority or 0
        entry.index = indices[source] or entry.index
    end
    table.sort(entries, function(a, b)
        if a.layer ~= b.layer then return a.layer < b.layer end
        if a.priority ~= b.priority then return a.priority < b.priority end
        if a.order ~= b.order then return a.order < b.order end
        if a.index ~= b.index then return a.index < b.index end
        return a.sequence < b.sequence
    end)
    return entries
end
-- 기본 범위·계층·부착 순서를 유지하되, 숫자가 다르면 범위를 넘어 정렬한다.
function Order.hosts(world, screen)
    local hosts = {}
    if not screen then
        if world.project then hosts[#hosts + 1] = world.project end
        hosts[#hosts + 1] = world
    end
    for _, object in ipairs(Order.objects(world.lobjects)) do hosts[#hosts + 1] = object end
    if screen then
        hosts[#hosts + 1] = world
        if world.project then hosts[#hosts + 1] = world.project end
    end
    return hosts
end
function Order.updates(hosts, legacyWorld)
    local pending = {}
    for _, host in ipairs(hosts) do
        for _, script in ipairs(host.updateScripts) do
            pending[#pending + 1] = {script = script, owner = host, order = script.updateOrder or 0, index = #pending + 1}
        end
        if host == legacyWorld and host.levelScript and host.levelScript.update then
            pending[#pending + 1] = {legacy = host, order = 0, index = #pending + 1}
        end
    end
    table.sort(pending, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.index < b.index
    end)
    return pending
end
return Order
