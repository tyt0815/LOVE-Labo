-- 플러그인의 저장 참조는 유지하고 탐색 UI에서만 Assets와 나란히 배치한다.
local Folders = {}
function Folders.roots(project, root)
    local roots = {{reference = root == "Assets" and "$project" or root, name = root == "Assets" and (project.name or "Project") or root}}
    if root == "Assets" and project.pluginAssets then
        for _, entry in ipairs(project.pluginAssets:list("Assets")) do roots[#roots + 1] = entry end
        table.sort(roots, function(a, b) return a.reference < b.reference end)
    end
    return roots
end
function Folders.list(project, reference)
    if reference == "$project" then return {{name = "Assets", reference = "Assets", type = "directory", isLink = false}} end
    local entries, err = project:listDirectory(reference)
    local result, present = {}, {}
    for _, entry in ipairs(entries or {}) do
        if reference ~= "Assets" or not project.pluginAssets or not project.pluginAssets.groups[entry.reference] then
            result[#result + 1], present[entry.reference] = entry, true
        end
    end
    for _, missing in ipairs(project.missingAssets or {}) do
        if missing.reference:sub(1, #reference + 1) == reference .. "/" then
            local tail = missing.reference:sub(#reference + 2)
            local name = tail:match("^[^/]+")
            local child = reference .. "/" .. name
            if not present[child] then
                result[#result + 1] = {name = name, reference = child, type = tail:find("/", 1, true) and "directory" or "file",
                    missing = true, id = missing.id, isLink = false}
                present[child] = true
            end
        end
    end
    if not entries and #result == 0 then return nil, err end
    table.sort(result, function(a, b) if a.type ~= b.type then return a.type == "directory" end; return (a.name or a.reference):lower() < (b.name or b.reference):lower() end)
    return result
end
return Folders
