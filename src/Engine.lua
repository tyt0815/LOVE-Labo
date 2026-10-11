-- 프로젝트는 내부 모듈 경로 대신 공개 API를 사용한다.
return {
    LObject = require("core.LObject"), Script = require("core.Script"),
    Transform = require("core.Transform"), Bounds = require("core.Bounds"),
    CoordinateSpace = require("core.CoordinateSpace"), Viewport = require("core.Viewport"),
    spawnLObject = function(world, prefab, transform, overrides) return world:spawnLObject(prefab, transform, overrides) end,
    openLevel = function(world, reference) return world:openLevel(reference) end
}
