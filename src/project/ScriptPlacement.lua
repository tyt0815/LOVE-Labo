local Placement = {}
function Placement.valid(project, reference)
    local kind, err = project:getScriptKind(reference)
    if kind ~= "script" then return false, err or "Only object scripts can be placed" end
    return require("project.LuaScript").load(project, reference, "script")
end
function Placement.add(project, level, reference, x, y, parent)
    local class, err = Placement.valid(project, reference)
    if not class then return nil, err end
    local source = assert(project:getAssetReference(reference))
    local id = assert(project:getAssetId(source), "Script asset is not registered")
    local object = assert(level:addLObject(x or 0, y or 0, nil, source:match("([^/]+)%.lua$")))
    object.scripts = {{id = "s1", source = id}}
    if parent then object.parentAuthoringId = parent.authoringId end
    return object
end
return Placement
