-- 프로젝트 코드는 Core의 내부 파일 경로 대신 이 공개 API를 사용한다.
return {
    SpawnLObject = function(world, prefab, transform, overrides) return world:SpawnLObject(prefab, transform, overrides) end,
    LObjectComponent = require("core.lobject_component"),
    SceneComponent = require("core.scene_component"),
    RenderComponent = require("core.render_component"),
    SpriteComponent = require("core.sprite_component")
}
