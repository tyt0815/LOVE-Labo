-- 프로젝트 코드는 Core의 내부 파일 경로 대신 이 공개 API를 사용한다.
return {
    spawnLObject = function(world, prefab, transform, overrides) return world:spawnLObject(prefab, transform, overrides) end,
    LObjectComponent = require("core.LObjectComponent"),
    SceneComponent = require("core.SceneComponent"),
    RenderComponent = require("core.RenderComponent"),
    SpriteComponent = require("core.SpriteComponent")
}
