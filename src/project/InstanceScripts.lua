local Scripts = {}
function Scripts.bind(project, target)
    local data = target.data
    target.canRemoveScript = function(_, id)
        for _, item in ipairs(data.scripts or {}) do if item.id == id then return true end end
        return false
    end
    target.addScript = function(_, source, id)
        local class, err = require("project.LuaScript").load(project, source, "script")
        if not class then return false, err end
        local used = {}; for _, current in ipairs(target.preview.scriptOrder) do used[current] = true end
        local number = 1; while not id and used["s" .. number] do number = number + 1 end
        id = id or "s" .. number
        if used[id] or not id:match("^[%a_][%w_]*$") then return false, "Invalid or duplicate script ID" end
        data.scripts = data.scripts or {}
        data.scripts[#data.scripts + 1] = {id = id, source = (source == "Script" or project.plugins.scripts[source]) and source or project:getAssetId(project:getAssetReference(source))}
        return true, id
    end
    target.removeScript = function(current, id)
        if not current:canRemoveScript(id) then return false, "Inherited scripts cannot be removed" end
        for index = #data.scripts, 1, -1 do if data.scripts[index].id == id then table.remove(data.scripts, index) end end
        if data.scriptOverrides then data.scriptOverrides[id] = nil end
        return true
    end
    target.moveScript = function(current, id, index)
        if not current:canRemoveScript(id) then return false, "Inherited scripts cannot be reordered" end
        local inherited = #current.preview.scriptOrder - #(data.scripts or {})
        if type(index) ~= "number" or index % 1 ~= 0 or index <= inherited or index > #current.preview.scriptOrder then return false, "Local scripts must follow inherited scripts" end
        for position, item in ipairs(data.scripts) do
            if item.id == id then table.remove(data.scripts, position); table.insert(data.scripts, index - inherited, item); return true end
        end
    end
    target.reloadTarget = function()
        local definition, err = require("project.PrefabHierarchy").authoringDefinition(project, target.level, data)
        if not definition then return nil, err end
        return require("project.ObjectDefinition").inspectorTarget(project, data, definition, target.level, target.label)
    end
    return target
end
return Scripts
