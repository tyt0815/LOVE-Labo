# Lua API와 생명주기


Camera·Sprite·Pointer·RectBounds·Canvas를 사용하려면 먼저 [플러그인](plugins.md)을 활성화합니다. 새 프로젝트에서는 모두 꺼져 있습니다.

Lua 파일은 스크립트 정의 테이블을 반환합니다. LObject를 상속하지 않습니다. `self`는 부착마다 생성되는 스크립트이고 `self.owner`는 Transform과 자손을 가진 LObject입니다. Lua 5.1/LuaJIT와 일반 LÖVE API를 사용할 수 있습니다.

```lua
local Movement = {
    properties = {
        speed = {type = "number", default = 100, group = "Movement"},
        title = {type = "string", default = "Player"},
        enabled = {type = "boolean", default = true},
        target = {type = "object", default = false},
        other = {type = "script", default = false},
        projectile = {type = "prefab", default = false},
    },
}
function Movement:beginPlay(world)
    self.elapsed = 0 -- 일반 필드는 Inspector에 노출되지 않는다.
end
function Movement:update(dt)
    if self.enabled then
        self.owner.transform.x = self.owner.transform.x + self.speed * dt
    end
end
return Movement
```

`beginPlay(world)`는 한 번 초기화합니다. `update(dt)`와 `draw(context)`는 선택 사항이며 실제 구현된 콜백만 실행 목록에 등록됩니다. 초기화 중 추가된 스크립트도 초기화하며 실행 중인 콜백에 재진입하지 않습니다. 부모 오브젝트에서 자손으로, 같은 오브젝트에서는 부착 순서로 실행합니다. Prefab의 스크립트 그룹 헤더 우클릭에서 순서를 바꿉니다.

활성화한 플러그인의 `extends = "Sprite"`를 사용하거나 다른 Lua 스크립트의 에셋 ID를 부모로 지정할 수 있습니다. `require("Engine")`은 LObject·Script·일반 API를 제공하며 Camera·Sprite·Pointer·RectBounds·Canvas는 해당 플러그인을 활성화해야 사용합니다. 프로젝트 내부 일반 모듈은 `require("Helpers.Math")`로 `Assets/Helpers/Math.lua`를 읽습니다.

| API | 역할 |
|---|---|
| self.owner.transform | 부모 기준 Transform |
| self.owner:getWorldTransform() | 합성된 월드 Transform |
| self.owner:getScript(id) | 같은 오브젝트의 부착 ID로 조회 |
| self.owner:addScript(id, Engine.Sprite, values) | 런타임 부착 |
| self.owner:removeScript(id) | 런타임 제거 |
| object:attachTo(parent) | 부모 변경, nil이면 독립 |
| world:spawnLObject(prefab, transform, overrides) | Prefab 계층 생성 |
| world:removeLObject(object) | 자손·입력 캡처까지 제거 |
| world:setActiveCamera(script) | 런타임 카메라 지정 |
| world:openLevel(reference) | 프레임 경계에서 레벨 전환 |
| world.debug | [에디터 로그·화면 로그·디버그 도형](debugging.md); 배포에서는 no-op |

편집 화면 표시에는 별도 `drawEditor(context)` 콜백을 사용합니다. 게임 draw와 분리되어 있으며 Camera 플러그인도 이를 사용합니다.

레벨 Lua 스크립트는 별도로 유지됩니다. 레벨을 상속한 오브젝트가 아니라 World 전체의 초기화·업데이트를 담당합니다. 예전 `build`, 루트 컴포넌트, LObject 클래스 생성 템플릿 API는 지원하지 않습니다.
