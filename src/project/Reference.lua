local Reference = {}
function Reference.validScript(reference)
    if reference == nil or require("project.AssetId").isValid(reference) then return true end
    if type(reference) ~= "string" or not reference:match("^Sources/.+%.lua$")
        or reference:find('[%z\1-\31\\:*?"<>|]') or reference:find("//", 1, true) then
        return false, "level scriptReference must be a canonical Sources/*.lua reference"
    end
    for segment in reference:gmatch("[^/]+") do
        if segment == "." or segment == ".." or segment:match("[ .]$") then
            return false, "level scriptReference contains a non-canonical path segment"
        end
    end
    return true
end
return Reference
