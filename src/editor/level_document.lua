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
    -- 각 mutation 경로에서 dirty flag를 직접 관리하지 않고,
    -- 필요할 때 serialization snapshot을 비교한다.
    local snapshot, err = createSavedSnapshot(self.level)

    if not snapshot then
        return nil, err
    end

    self.savedSnapshot = snapshot

    return self
end

function LevelDocument.create(path)
    if type(path) ~= "string" or path == "" then
        return nil, "path must be a non-empty string"
    end

    -- New asset 생성은 기존 파일을 덮어쓰지 않는다.
    -- 기존 asset 교체는 명시적인 save/save-as 흐름의 책임으로 남긴다.
    if LevelFile.exists(path) then
        return nil, "level file already exists"
    end

    local document, documentError =
        LevelDocument.new()

    if not document then
        return nil, documentError
    end

    local saved, saveError =
        document:save(path)

    if not saved then
        return nil, saveError
    end

    return document
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
        -- serialize할 수 없는 현재 상태는 clean으로 볼 수 없다.
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

    -- 실제 save가 성공한 뒤에만 document metadata를 갱신한다.
    self.path = targetPath
    self.savedSnapshot = snapshot

    return true
end

return LevelDocument
