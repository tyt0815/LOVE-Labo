local Transform = require("core.Transform")
local Transfer = {}
local function copy(list)
    local result = {}; for index, value in ipairs(list or {}) do result[index] = value end
    return result
end
local function without(list, members)
    local result = {}; for _, value in ipairs(list or {}) do if not members[value] then result[#result + 1] = value end end
    return result
end
function Transfer.roots(world, options)
    if options == nil then return {} end
    assert(type(options) == "table", "Expected level transition options")
    for key in pairs(options) do assert(key == "carry", "Unknown transition option: " .. tostring(key)) end
    local carry, selected = options.carry == nil and {} or options.carry, {}
    assert(type(carry) == "table", "carry must be an array of LObjects")
    local count = 0
    for key, object in pairs(carry) do
        count = count + 1
        assert(type(key) == "number" and key >= 1 and key <= #carry and key % 1 == 0, "carry must be a dense array")
        assert(type(object) == "table" and object.world == world and not object.removing, "Carried object must belong to this World")
        local found = false; for _, value in ipairs(world.lobjects) do if value == object then found = true end end
        assert(found, "Carried object is not live")
        selected[object] = true
    end
    assert(count == #carry, "carry must be a dense array")
    local roots, seen = {}, {}
    for _, object in ipairs(carry) do
        local parent, nested = object.parent, false
        while parent do if selected[parent] then nested = true end; parent = parent.parent end
        if not nested and not seen[object] then roots[#roots + 1] = object; seen[object] = true end
    end
    return roots
end
function Transfer.begin(source, destination, roots)
    roots = Transfer.roots(source, {carry = roots})
    local moved, owners, objects, saved, hosts = {}, {}, {}, {}, {}
    local function visit(object)
        moved[object] = true; objects[#objects + 1] = object
        for _, child in ipairs(object.children) do visit(child) end
    end
    for _, object in ipairs(roots) do visit(object) end
    for _, object in ipairs(objects) do hosts[#hosts + 1] = object end
    if source.project then hosts[#hosts + 1] = source.project end
    local scripts, handles = {}, {}
    for _, host in ipairs(hosts) do for _, id in ipairs(host.scriptOrder) do
        local script = host.scripts[id]; owners[script] = true; scripts[#scripts + 1] = script
        handles[script] = #(script.bindingHandles or {})
    end end
    local groups = {renderViews = {}, renderTargets = {}, inputRegions = {}}
    for _, view in ipairs(source.renderViews or {}) do if owners[view.owner] then
        groups.renderViews[view] = true
        if view.target ~= require("core.Rendering").screen then
            assert(not view.target.owner or owners[view.target.owner], "Carried View depends on a target owned by another script")
            groups.renderTargets[view.target] = true
        end
    end end
    for _, target in ipairs(source.renderTargets or {}) do if owners[target.owner] then groups.renderTargets[target] = true end end
    for _, view in ipairs(source.renderViews or {}) do
        assert(not groups.renderTargets[view.target] or groups.renderViews[view], "Render target is shared with a View left in the old World")
    end
    for _, region in ipairs(source.inputRegions or {}) do if owners[region.owner] then groups.inputRegions[region] = true end end
    local previousLists, previousIds, resourceIds = {}, {}, {}
    for key in pairs(groups) do previousLists[key] = copy(source[key]) end
    for _, key in ipairs({"nextViewId", "nextRegionId"}) do previousIds[key] = source[key] end
    local previousObjects, previousRuntimeId = copy(source.lobjects), source.nextRuntimeId
    for _, object in ipairs(objects) do saved[object] = {runtimeId = object.runtimeId, authoringId = object.authoringId,
        transform = object.transform, parent = object.parent, scriptLoader = object.scriptLoader} end
    local positions, parentChildren = {}, {}
    for _, root in ipairs(roots) do
        positions[root] = root:getWorldTransform()
        if root.parent then parentChildren[root.parent] = copy(root.parent.children) end
    end
    local transaction = {notified = {}, previousWorld = source}
    local function unlock()
        source.transitionInProgress, destination.transitionInProgress = nil, nil
        for _, host in ipairs(hosts) do host.transferPending = nil end
        for _, script in ipairs(scripts) do
            for index = 1, handles[script] do script.bindingHandles[index].transferPending = nil end
        end
        for _, members in pairs(groups) do for resource in pairs(members) do resource.transferPending = nil end end
    end
    function transaction:notify()
        for _, script in ipairs(scripts) do if script.worldChanged then
            self.notified[#self.notified + 1] = script
            local ok, err = script:worldChanged(source, destination); assert(ok ~= false, err or "worldChanged rejected transfer")
        end end
    end
    function transaction:commit() unlock(); self.finished = true end
    function transaction:rollback()
        if self.finished then return end
        unlock()
        -- 후보 초기화 중 추가한 등록만 정리하고 기존 등록은 같은 인스턴스로 복구한다.
        for _, script in ipairs(scripts) do
            local list = script.bindingHandles or {}
            while #list > handles[script] do local handle = table.remove(list); handle:release() end
        end
        for key, members in pairs(groups) do
            for _, resource in ipairs(copy(destination[key])) do
                if owners[resource.owner] and not members[resource] then resource:release() end
            end
            destination[key] = without(destination[key], members)
            source[key] = previousLists[key]
            for resource in pairs(members) do resource.world, resource.id = source, resourceIds[resource] end
        end
        for key, value in pairs(previousIds) do source[key] = value end
        destination.lobjects = without(destination.lobjects, moved)
        source.lobjects, source.nextRuntimeId = previousObjects, previousRuntimeId
        for _, object in ipairs(objects) do
            local state = saved[object]
            object.world, object.runtimeId, object.authoringId = source, state.runtimeId, state.authoringId
            object.transform, object.scriptLoader = state.transform, state.scriptLoader
        end
        for _, root in ipairs(roots) do root:attachTo(saved[root].parent) end
        for parent, children in pairs(parentChildren) do parent.children = children end
        if source.project then source.project.world = source end
        self.finished = true
        local failure
        for index = #self.notified, 1, -1 do
            local script = self.notified[index]
            local ok, result, err = pcall(script.worldChanged, script, destination, source)
            if not ok or result == false then failure = failure or (not ok and result or err or "worldChanged rejected rollback") end
        end
        return failure
    end
    for _, members in pairs(groups) do for resource in pairs(members) do resourceIds[resource] = resource.id end end
    local function move()
        source:cancelPointer()
        for _, root in ipairs(roots) do root:attachTo(nil) end
        source.lobjects = without(source.lobjects, moved)
        for _, object in ipairs(objects) do
            object.world, object.runtimeId, object.authoringId = destination, destination.nextRuntimeId, nil
            destination.nextRuntimeId = destination.nextRuntimeId + 1
            object.scriptLoader = destination.project and destination.project.scriptLoader or saved[object].scriptLoader
            destination.lobjects[#destination.lobjects + 1] = object
        end
        if source.project then source.project.world = destination end
        for _, root in ipairs(roots) do
            local value = assert(Transform.copy(root.transform)); value.x, value.y = positions[root].x, positions[root].y
            root.transform = Transform.unresolve(root, value)
        end
        for key, members in pairs(groups) do
            destination[key] = destination[key] or {}
            source[key] = without(source[key], members)
            for _, resource in ipairs(previousLists[key]) do if members[resource] then
                resourceIds[resource] = resource.id
                resource.world = destination
                if key == "renderViews" or key == "inputRegions" then
                    local counter = key == "renderViews" and "nextViewId" or "nextRegionId"
                    destination[counter] = (destination[counter] or 0) + 1; resource.id = destination[counter]
                end
                if resource.pointerCaptures then resource.pointerCaptures = {} end
                resource.transferPending = true
                destination[key][#destination[key] + 1] = resource
            end end
        end
        source.transitionInProgress, destination.transitionInProgress = true, true
        for _, host in ipairs(hosts) do host.transferPending = true end
        for _, script in ipairs(scripts) do
            for index = 1, handles[script] do script.bindingHandles[index].transferPending = true end
        end
    end
    local ok, err = pcall(move)
    if not ok then transaction:rollback(); error(err, 0) end
    return transaction
end
return Transfer
