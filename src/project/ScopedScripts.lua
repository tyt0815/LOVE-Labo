local Attachments = require("project.ScriptAttachments")
local Definition = require("project.ObjectDefinition")
local Scoped = {}

function Scoped.validate(data)
    local scripts, err = Attachments.validate(data.scripts)
    if not scripts then return nil, err end
    local overrides, overrideError = require("project.PropertyData").validateScripts(data.scriptOverrides)
    if not overrides then return nil, overrideError end
    local names = {}
    for _, item in ipairs(scripts) do
        if not item.source or names[item.name] then return nil, "Scope scripts require unique names and sources" end
        names[item.name] = true
    end
    return {scripts = scripts, scriptOverrides = overrides}
end

function Scoped.configure(host, data, loadClass)
    local valid, err = Scoped.validate(data)
    if not valid then return false, err end
    return Definition.configure(host, {attachments = valid.scripts, scripts = valid.scriptOverrides, scriptLoader = loadClass})
end

function Scoped.inspectorTarget(project, data, level, label)
    local valid, err = Scoped.validate(data)
    if not valid then return nil, err end
    local target, targetError = Definition.inspectorTarget(project, data,
        {attachments = valid.scripts, scripts = {}, scriptLoader = require("project.LuaScript").loader(project)}, level, label)
    if not target then return nil, targetError end
    -- 범위의 저장 데이터를 편집하며 공간 Transform 필드는 만들지 않는다.
    target.kind, target.scope, target.instance, target.hideParent = "script", true, false, true
    target.class.className = label
    require("project.InstanceScripts").bind(project, target)
    target.reloadTarget = function() return Scoped.inspectorTarget(project, data, level, label) end
    return target
end
return Scoped
