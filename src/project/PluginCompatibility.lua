-- 이전 제공 플러그인의 경로 참조를 새 묶음으로 읽되 에셋 ID는 변경하지 않는다.
local Compatibility = {}
local LEGACY = {Camera = true, Sprite = true, Pointer = true, Rect = true, Canvas = true}
function Compatibility.reference(reference)
    if type(reference) ~= "string" then return reference end
    local name, file = reference:match("^Assets/Labo Plugins/([^/]+)/(.+)$")
    if LEGACY[name] and file == name .. ".lua" then
        return "Assets/Labo Plugins/LaboEssentials/" .. (name == "Rect" and "RectBounds" or name) .. ".lua"
    end
    return reference
end
return Compatibility
