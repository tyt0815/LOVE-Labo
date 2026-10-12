local Scripts = {}
function Scripts.bind(project, target)
    local data = target.data
    target.canRemoveScript = function(_, id)
        for _, item in ipairs(data.scripts or {}) do if item.id == id and item.source then return true end end
        return false
    end
    target.addScript = function(_, source, name)
        local class, err = require("project.LuaScript").load(project, source, "script")
        if not class then return false, err end
        local list = {}; for _, id in ipairs(target.preview.scriptOrder) do list[#list + 1] = target.preview.scripts[id] end
        local attachments = require("project.ScriptAttachments")
        if not name then
            local base = require("project.LuaScript").name(class) or class.scriptType or "Script"
            name = base; local number = 2
            while not attachments.uniqueName(list, name) do name = base .. " " .. number; number = number + 1 end
        end
        local valid, nameError = attachments.uniqueName(list, name)
        if not valid then return false, nameError end
        local id = require("project.AssetId").new()
        data.scripts = data.scripts or {}
        data.scripts[#data.scripts + 1] = {id = id, name = name, source = (source == "Script" or project.plugins.scripts[source]) and source or project:getAssetId(project:getAssetReference(source))}
        return true, id
    end
    target.renameScript = function(_, id, name)
        local list = {}; for _, current in ipairs(target.preview.scriptOrder) do list[#list + 1] = target.preview.scripts[current] end
        local item = require("project.ScriptAttachments").find(list, id)
        if not item then return false, "Missing script" end
        local valid, err = require("project.ScriptAttachments").uniqueName(list, name, item.id)
        if not valid then return false, err end
        data.scripts = data.scripts or {}
        local localItem = require("project.ScriptAttachments").find(data.scripts, item.id)
        if not localItem then localItem = {id = item.id}; data.scripts[#data.scripts + 1] = localItem end
        localItem.name = name; return true
    end
    target.removeScript = function(current, id)
        local script = current.preview:getScriptById(id) or current.preview:getScriptByName(id)
        id = script and script.id or id
        if not current:canRemoveScript(id) then return false, "Inherited scripts cannot be removed" end
        for index = #data.scripts, 1, -1 do if data.scripts[index].id == id then table.remove(data.scripts, index) end end
        if data.scriptOverrides then data.scriptOverrides[id] = nil end
        return true
    end
    target.moveScript = function(current, id, index)
        local script = current.preview:getScriptById(id) or current.preview:getScriptByName(id)
        id = script and script.id or id
        if not current:canRemoveScript(id) then return false, "Inherited scripts cannot be reordered" end
        local localCount = 0
        for _, item in ipairs(data.scripts or {}) do if item.source then localCount = localCount + 1 end end
        local inherited = #current.preview.scriptOrder - localCount
        if type(index) ~= "number" or index % 1 ~= 0 or index <= inherited or index > #current.preview.scriptOrder then return false, "Local scripts must follow inherited scripts" end
        for position, item in ipairs(data.scripts) do
            if item.id == id then
                table.remove(data.scripts, position)
                local ordinal, destination = 0, #data.scripts + 1
                for currentPosition, record in ipairs(data.scripts) do
                    if record.source then
                        ordinal = ordinal + 1
                        if ordinal == index - inherited then destination = currentPosition; break end
                    end
                end
                table.insert(data.scripts, destination, item); return true
            end
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
