local Json = require("project.Json")
local Transition = {}
-- 호출 프레임에는 교체하지 않는다. 후보 World는 완전히 초기화한 뒤에만 공개한다.
function Transition.bind(project, world)
    world.openLevelRequest = function(reference, options)
        if world.pendingLevel then return false, "A level transition is already pending" end
        local roots = require("core.WorldTransfer").roots(world, options)
        local path, err = project:getAssetReference(reference)
        if not path or not path:match("^Assets/.+%.level$") then return false, err or "openLevel requires a Level asset" end
        local bytes, readError = project:readAsset(reference)
        if not bytes then return false, readError end
        local data, decodeError = Json.decode(bytes)
        if not data then return false, decodeError end
        if data.formatVersion ~= 1 and data.formatVersion ~= 2 and data.formatVersion ~= 3 then return false, "Unsupported level format version" end
        -- 파일 구조와 객체 관계를 검증하되 load는 프레임 경계까지 실행하지 않는다.
        local prepared, class, initial, loadClass = require("runtime.WorldLoader").prepare(project, data, world.project)
        if not prepared then return false, class end
        world.pendingLevel = {reference = project:getAssetId(path) or path, world = prepared, roots = roots, class = class, initial = initial, loadClass = loadClass}
        world.levelTransitionError = nil
        return true
    end
    world.applyLevelRequest = function()
        local pending = world.pendingLevel
        if not pending then return nil end
        world.pendingLevel = nil
        pending.world.debug = world.debug
        local transferred, transaction = pcall(require("core.WorldTransfer").begin, world, pending.world, pending.roots)
        if not transferred then
            pending.world:dispose(true)
            world.levelTransitionError = tostring(transaction)
            return nil, world.levelTransitionError
        end
        local called, candidate, err = pcall(require("runtime.WorldLoader").activate, project, pending.world, pending.class, pending.initial, pending.loadClass, transaction)
        if not called or not candidate then
            local rollbackError = transaction:rollback()
            pending.world:dispose(true)
            world.levelTransitionError = tostring(called and err or candidate) .. (rollbackError and "\nRollback callback: " .. tostring(rollbackError) or "")
            return nil, world.levelTransitionError
        end
        transaction:commit()
        candidate.levelReference = pending.reference
        local ok, cleanupError = world:dispose(true)
        if not ok then candidate.levelTransitionError = cleanupError end
        return candidate, cleanupError
    end
end
return Transition
