-- 플러그인의 저장 참조는 유지하고 탐색 UI에서만 Assets와 나란히 배치한다.
local Folders = {}
function Folders.roots(project, root)
    local roots = {{reference = root, name = root}}
    if root == "Assets" and project.pluginAssets then
        for _, entry in ipairs(project.pluginAssets:list("Assets")) do roots[#roots + 1] = entry end
        table.sort(roots, function(a, b) return a.reference < b.reference end)
    end
    return roots
end
function Folders.list(project, reference)
    local entries, err = project:listDirectory(reference)
    if not entries then return nil, err end
    if reference ~= "Assets" or not project.pluginAssets then return entries end
    local result = {}
    for _, entry in ipairs(entries) do
        if not project.pluginAssets.groups[entry.reference] then result[#result + 1] = entry end
    end
    return result
end
return Folders
