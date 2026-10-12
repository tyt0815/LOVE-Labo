# 런타임 오브젝트 생성

`world:spawnLObject(prefabReference, transform, overrides)`는 Prefab의 루트와 자손·부착 스크립트를 생성합니다. 참조는 에셋 ID를 권장하며 Assets 아래 .prefab 경로도 지원합니다. Lua 파일은 행동 정의이므로 생성 템플릿으로 넘길 수 없습니다.

```lua
local Spawner = {properties = {
    projectile = {type = "prefab", default = false},
}}
function Spawner:beginPlay(world)
    if self.projectile ~= false then
        self.spawned = assert(world:spawnLObject(self.projectile, {x = 200, y = 0}))
    end
end
return Spawner
```

반환값은 루트 LObject 또는 `nil, error`입니다. 내부 참조는 새 계층으로 연결하며 모든 스크립트는 독립 상태를 가집니다. 생성 실패는 추가된 객체를 되돌립니다. `overrides.scripts`에는 부착 ID별 프로퍼티를 지정합니다. 사용자 이름도 조회 호환 입력으로 지원하지만 저장 참조는 내부 UUID를 사용합니다.

```lua
local object, err = world:spawnLObject(prefabId, {x = 100, y = 50}, {
    scripts = {movement = {speed = 250}}
})
if object then
    local movement = object:getScriptByName("movement")
    world:removeLObject(object) -- 자손과 포인터 캡처도 정리한다.
end
```

동작 확인은 [level.simulate와 level.pointer](cli-and-export.md)를 사용합니다. Inspector의 prefab 프로퍼티는 스포이드로 Prefab 에셋을 지정합니다.
