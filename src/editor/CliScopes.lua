local Scoped = require("project.ScopedScripts")
local Fs = require("editor.HostFileSystem")
local Commands = {}
function Commands.execute(project, request, api)
    local scope, action = request.command:match("^(%w+)%.script%.(.+)$")
    local document, data, path
    if scope == "project" then
        path, data = Fs.join(project.rootPath, "project.labo"), project
    else
        local reference = request.level or project.defaultLevelReference
        assert(reference, "Missing --level")
        assert(not project:isReadOnly(reference) or action == "get", "Labo plugin assets are read-only")
        path = assert(project:resolveAssetFile(reference))
        document = assert(require("editor.LevelDocument").load(path)); data = document.level
    end
    local bytes = assert(Fs.read(path)); api.checkRevision(request, bytes)
    local target = api.ownTarget(assert(Scoped.inspectorTarget(project, data, document and document.level, scope)))
    if action == "add" then assert(target:addScript(api.required(request, "source"), request.script))
    elseif action == "remove" then assert(target:removeScript(api.required(request, "script")))
    elseif action == "rename" then assert(target:renameScript(api.required(request, "script"), api.required(request, "name")))
    elseif action == "move" then assert(target:moveScript(api.required(request, "script"), tonumber(api.required(request, "index"))))
    elseif action == "set" or action == "reset" then
        local name = api.propertyName(target, api.required(request, "property"))
        local item
        if action == "set" then item = api.value(request)
        else item = assert(target.class.properties[name], "Unknown property").default end
        api.setProperty(project, target, name, item)
    else assert(action == "get", "Unknown scope script command") end
    -- 변경한 정의를 저장 전에 검증해 오류 응답 뒤에 불완전한 편집을 남기지 않는다.
    target = api.ownTarget(assert(Scoped.inspectorTarget(project, data, document and document.level, scope)))
    if action ~= "get" then
        assert(assert(Fs.read(path)) == bytes, "Revision conflict: file changed while editing")
        if document then assert(document:save()) else assert(project:saveScripts()) end
    end
    local result = api.properties(target)
    result.scripts = require("project.Json").array(require("project.ScriptAttachments").copy(data.scripts))
    result.revision = api.revision(assert(Fs.read(path)))
    return result
end
return Commands
