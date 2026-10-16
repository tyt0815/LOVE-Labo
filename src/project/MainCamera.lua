local MainCamera = {}
function MainCamera.copy(value)
    if value == nil or value == false then return nil end
    if type(value) ~= "table" or type(value.authoringId) ~= "number" or value.authoringId < 1
        or value.authoringId % 1 ~= 0 or type(value.script) ~= "string" or value.script == "" then
        return nil, "Main Camera requires an instance ID and script ID"
    end
    return {authoringId = value.authoringId, script = value.script}
end
-- 이전 저장값 검증·마이그레이션만 담당하며 런타임 카메라 선택은 제공하지 않는다.
return MainCamera
