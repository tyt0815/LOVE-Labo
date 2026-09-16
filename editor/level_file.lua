local Json = require("editor.json")
local Level = require("editor.level")

local LevelFile = {}

local function fileExists(path)
    local file = io.open(path, "rb")

    if not file then
        return false
    end

    file:close()
    return true
end

local function readText(path)
    local file, openError = io.open(path, "rb")

    if not file then
        return nil, openError
    end

    local text, readError = file:read("*a")
    local closeOk, closeError = file:close()

    if text == nil then
        return nil, readError or "failed to read file"
    end

    if not closeOk then
        return nil, closeError or "failed to close file"
    end

    return text
end

local function writeText(path, text)
    local file, openError = io.open(path, "wb")

    if not file then
        return false, openError
    end

    local writeOk, writeError = file:write(text)

    if not writeOk then
        file:close()
        return false, writeError or "failed to write file"
    end

    local closeOk, closeError = file:close()

    if not closeOk then
        return false, closeError or "failed to close file"
    end

    return true
end

function LevelFile.encode(level)
    if type(level) ~= "table"
        or type(level.toData) ~= "function"
    then
        return nil, "level must provide toData()"
    end

    local data = level:toData()

    -- 빈 Level도 JSON에서 []로 저장되도록 array 의미를 명시한다.
    data.lobjects = Json.array(data.lobjects)

    local text, encodeError = Json.encode(data, true)

    if not text then
        return nil, encodeError
    end

    -- text asset diff가 깔끔하게 끝나도록 newline 하나를 붙인다.
    return text .. "\n"
end

function LevelFile.decode(text)
    local data, decodeError = Json.decode(text)

    if not data then
        return nil, decodeError
    end

    return Level.fromData(data)
end

function LevelFile.save(path, level)
    if type(path) ~= "string" or path == "" then
        return false, "path must be a non-empty string"
    end

    -- 먼저 전체 JSON을 메모리에서 완성한다.
    -- encode가 실패하면 기존 정상 파일에는 손대지 않는다.
    local text, encodeError = LevelFile.encode(level)

    if not text then
        return false, encodeError
    end

    local tempPath = path .. ".tmp"
    local backupPath = path .. ".bak"

    -- 이전 save가 중간에 끝난 흔적을 정리한다.
    -- 정상 target이 없고 backup만 남아 있다면 먼저 복구한다.
    if not fileExists(path) and fileExists(backupPath) then
        local recovered, recoverError =
            os.rename(backupPath, path)

        if not recovered then
            return false,
                "failed to recover previous backup: "
                .. tostring(recoverError)
        end
    end

    if fileExists(tempPath) then
        local removed, removeError = os.remove(tempPath)

        if not removed then
            return false,
                "failed to remove stale temp file: "
                .. tostring(removeError)
        end
    end

    local wroteTemp, writeError =
        writeText(tempPath, text)

    if not wroteTemp then
        os.remove(tempPath)
        return false, writeError
    end

    local hadExistingFile = fileExists(path)

    if hadExistingFile then
        -- target이 정상적으로 존재하면 오래된 backup은 더 이상 필요 없다.
        if fileExists(backupPath) then
            local removed, removeError =
                os.remove(backupPath)

            if not removed then
                os.remove(tempPath)
                return false,
                    "failed to remove stale backup: "
                    .. tostring(removeError)
            end
        end

        local backedUp, backupError =
            os.rename(path, backupPath)

        if not backedUp then
            os.remove(tempPath)
            return false,
                "failed to back up existing level: "
                .. tostring(backupError)
        end
    end

    local replaced, replaceError =
        os.rename(tempPath, path)

    if not replaced then
        os.remove(tempPath)

        if hadExistingFile then
            local restored, restoreError =
                os.rename(backupPath, path)

            if not restored then
                return false,
                    "failed to replace level and failed to restore backup: "
                    .. tostring(replaceError)
                    .. " / "
                    .. tostring(restoreError)
            end
        end

        return false,
            "failed to replace level file: "
            .. tostring(replaceError)
    end

    if hadExistingFile then
        -- 새 파일이 정상 위치에 들어간 뒤에만 backup을 제거한다.
        os.remove(backupPath)
    end

    return true
end

function LevelFile.load(path)
    if type(path) ~= "string" or path == "" then
        return nil, "path must be a non-empty string"
    end

    local text, readError = readText(path)

    if not text then
        return nil, readError
    end

    return LevelFile.decode(text)
end

return LevelFile
