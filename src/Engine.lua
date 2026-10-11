-- 프로젝트는 내부 모듈 경로 대신 공개 API를 사용한다.
return {
    LObject = require("core.LObject"), Script = require("core.Script"),
    Camera = require("core.CameraScript"), Sprite = require("core.SpriteScript"),
    Pointer = require("core.PointerScript"), Rect = require("core.RectScript"), Canvas = require("core.CanvasScript"),
    spawnLObject = function(world, prefab, transform, overrides) return world:spawnLObject(prefab, transform, overrides) end,
    openLevel = function(world, reference) return world:openLevel(reference) end
}
