local Fs = require("editor.HostFileSystem")
local Layout = {}

function Layout.migrateSources(root)
    local source, target = Fs.join(root, "Sources"), Fs.join(root, "Assets/Scripts")
    local info, err = Fs.info(source)
    if err then return false, err end
    if not info then return true end
    if info.isLink or info.type ~= "directory" then return false, "Legacy Sources must be a regular folder" end
    local exists, targetError = Fs.info(target)
    if targetError then return false, targetError end
    if exists then return false, "Cannot merge Sources automatically: Assets/Scripts already exists; keep both folders and resolve the destination first" end
    local function validate(path)
        local entries, listError = Fs.list(path)
        if not entries then return false, listError end
        for _, entry in ipairs(entries) do
            if entry.isLink then return false, "Sources migration does not follow filesystem links" end
            if entry.type == "directory" then
                local ok, childError = validate(Fs.join(path, entry.name))
                if not ok then return false, childError end
            end
        end
        return true
    end
    local ok, validateError = validate(source)
    if not ok then return false, validateError end
    -- 동일 프로젝트 안에서 폴더를 한 번에 이동한다. 파일과 .meta의 ID는 그대로 유지한다.
    return Fs.rename(source, target)
end
return Layout
