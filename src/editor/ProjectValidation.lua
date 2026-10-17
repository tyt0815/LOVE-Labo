local Validation = {}
function Validation.run(project)
    local errors, checked = {}, 0
    local references = {}; for reference in pairs(project.assetMetadata) do references[#references + 1] = reference end
    table.sort(references)
    for _, reference in ipairs(references) do
        local kind = project.assetMetadata[reference].scriptKind
        if kind or reference:match("%.prefab$") or reference:match("%.level$") then
            checked = checked + 1
            local ok, err = pcall(function()
                if kind then assert(require("project.LuaScript").load(project, reference, kind))
                elseif reference:match("%.level$") then
                    local document = assert(require("editor.LevelDocument").load(assert(project:resolveAssetFile(reference))))
                    assert(require("runtime.WorldLoader").validate(project, document.level:toData()))
                else
                    assert(require("runtime.WorldLoader").validate(project, {lobjects = {{authoringId = 1, transform = {x = 0, y = 0}, definitionReference = project:getAssetId(reference)}}}))
                end
            end)
            if not ok then errors[#errors + 1] = {reference = reference, error = tostring(err)} end
        end
    end
    return {valid = #errors == 0, checked = checked, errors = errors}
end
return Validation
