-- 프로젝트 코드는 Core의 내부 파일 경로 대신 이 공개 API를 사용한다.
return {
    spawnLObject = function(world, template, transform, overrides) return world:spawnLObject(template, transform, overrides) end,
    openLevel = function(world, reference) return world:openLevel(reference) end,
    LObjectComponent = require("core.LObjectComponent"),
    SceneComponent = require("core.SceneComponent"),
    BoundsComponent = require("core.BoundsComponent"),
    RectComponent = require("core.RectComponent"),
    CanvasComponent = require("core.CanvasComponent"),
    CameraComponent = require("core.CameraComponent"),
    PointerComponent = require("core.PointerComponent"),
    RenderComponent = require("core.RenderComponent"),
    SpriteComponent = require("core.SpriteComponent")
}
