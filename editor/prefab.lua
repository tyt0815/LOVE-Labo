local Json = require("editor.json")
local Level = require("editor.level")
local Prefab = {}

function Prefab.encode(definitionReference)
    local valid, err = Level.isValidScriptReference(definitionReference)
    if not definitionReference or not valid then return nil, err or "LObject script is required" end
    -- Definition의 데이터 변형을 위한 에셋이다. 빈 override는 원본 값을 유지한다.
    local text, encodeError = Json.encode({ formatVersion = 2,
        definitionReference = definitionReference, overrides = {} }, true)
    return text and text .. "\n" or nil, encodeError
end

return Prefab
