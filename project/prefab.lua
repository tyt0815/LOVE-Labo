local Json = require("project.json")
local Level = {isValidScriptReference = require("project.reference").validScript}
local Prefab = {}

function Prefab.decode(text)
    local data, err = Json.decode(text)
    if type(data) ~= "table" then return nil, err or "Prefab must be an object" end
    if data.formatVersion ~= 1 and data.formatVersion ~= 2 then return nil, "Unsupported Prefab format" end
    local valid, referenceError = Level.isValidScriptReference(data.definitionReference)
    if not valid then return nil, referenceError end
    if type(data.overrides) ~= "table" then return nil, "Prefab overrides must be an object" end
    local properties, propertyError = require("project.property_data").validate(data.overrides.properties)
    if not properties then return nil, propertyError end
    local components, componentError = require("project.property_data").validateComponents(data.overrides.components)
    if not components then return nil, componentError end
    return data
end

function Prefab.encodeData(data)
    local text, err = Json.encode(data, true)
    if not text then return nil, err end
    local valid, validationError = Prefab.decode(text)
    if not valid then return nil, validationError end
    return text .. "\n"
end

function Prefab.encode(definitionReference)
    local valid, err = Level.isValidScriptReference(definitionReference)
    if not valid then return nil, err end
    -- Definition의 데이터 변형을 위한 에셋이다. 빈 override는 원본 값을 유지한다.
    return Prefab.encodeData({ formatVersion = 2,
        definitionReference = definitionReference, overrides = {} })
end

return Prefab
