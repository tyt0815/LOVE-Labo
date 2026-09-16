local Level = require("editor.level")
local LevelFile = require("editor.level_file")

local LevelDocument = {}
LevelDocument.__index = LevelDocument

local function createSavedSnapshot(level)
    local text, err = LevelFile.encode(level)

    if not text then
        return nil, err
    end

    return text
end

function LevelDocument.new(level)
    local self = setmetatable({}, LevelDocument)

    self.level = level or Level.new()
    self.path = nil

    -- 현재 Level 상태를 document의 clean baseline으로 잡는다.
    -- mutation 경로마다 dirty flag를 직접 갱신하지 않고,
    -- 필요할 때 현재 serialization 결과와 이 snapshot을 비교한다.
    local snapshot, err = createSavedSnapshot(self.level)

    if not snapshot then
        return nil, err
    end

    self.savedSnapshot = snapshot

    return self
end

function LevelDocument.load(path)
    local level, loadError = LevelFile.load(path)

    if not level then
        return nil, loadError
    end

    local document, documentError =
        LevelDocument.new(level)

    if not document then
        return nil, documentError
    end

    document.path = path

    return document
end

function LevelDocument:isDirty()
    local currentSnapshot, err =
        createSavedSnapshot(self.level)

    if not currentSnapshot then
        -- 현재 authoring state가 serialize조차 되지 않는다면
        -- clean으로 취급할 수 없으므로 dirty로 반환한다.
        return true, err
    end

    return currentSnapshot ~= self.savedSnapshot
end

function LevelDocument:save(path)
    local targetPath = path or self.path

    if type(targetPath) ~= "string"
        or targetPath == ""
    then
        return false, "level document has no save path"
    end

    -- 실제 save와 dirty baseline이 같은 serialization 결과를 기준으로
    -- 하도록 먼저 canonical snapshot을 만든다.
    local snapshot, snapshotError =
        createSavedSnapshot(self.level)

    if not snapshot then
        return false, snapshotError
    end

    local saved, saveError =
        LevelFile.save(targetPath, self.level)

    if not saved then
        return false, saveError
    end

    -- 성공한 save만 document path와 clean baseline을 갱신한다.
    self.path = targetPath
    self.savedSnapshot = snapshot

    return true
end

return LevelDocument
