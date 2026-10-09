# Prefab 참조와 런타임 LObject 생성

`prefab` 프로퍼티는 생성할 원본 Prefab의 에셋 ID를 저장한다. `object` 프로퍼티가 이미 배치된 인스턴스를 가리키는 것과 구분한다. 이름 변경·이동에도 `.meta`의 ID는 유지된다. 기본값은 `false`이며 Inspector의 드롭다운 또는 에셋 드래그로 설정하고 찾기 버튼으로 리소스를 탐색한다. Prefab 상속과 인스턴스 override에도 같은 타입을 사용한다.

```lua
-- labo-script: lobject
local Spawner = {properties = {
    projectile = {type = "prefab", default = false},
}}

function Spawner.beginPlay(self, world)
    if self.properties.projectile ~= false then
        local object, err = world:spawnLObject(self.properties.projectile, {
            x = self.transform.x + 100,
            y = self.transform.y,
        })
        assert(object, err)
        self.projectileInstance = object
    end
end

return Spawner
```

Inspector에서 `projectile`에 생성할 Prefab을 설정한 다음 Play한다. 결과는 Runtime World에만 존재하고 레벨 파일·Hierarchy 배치·Undo 기록에 추가되지 않으며 Stop 또는 런타임 재시작 시 사라진다. `beginPlay` 이후에는 `self.world`로 같은 World에 접근한다. Level 클래스에서도 `world:spawnLObject(world.properties.projectile, ...)`를 사용한다.

## API

```lua
local object, err = world:spawnLObject(prefabId, transform, overrides)
-- 공개 Engine 모듈의 동일한 호출
local object, err = require("Engine").spawnLObject(world, prefabId, transform, overrides)
```

- `prefabId`: Prefab 에셋 ID. 프로젝트 상대 `.prefab` 경로도 지원하지만 코드의 고정 경로는 이동 시 자동 수정하지 않는다. Lua Class·이미지·`false`는 거절한다.
- `transform`: 생략하면 원점·회전 0·스케일 1이다. 지정하면 `x/y`는 유한한 숫자로 모두 제공한다. `rotationX/rotationY/rotation`은 도 단위, `scaleX/scaleY`는 양수이며 생략 가능하다.
- `overrides`: 생략 가능하다. `{properties = {speed = 42}, components = {sprite = {x = 10}}}`처럼 이번 인스턴스의 값만 변경한다. 객체 참조 override는 기존 레벨의 authoring ID를 사용한다.
- 성공 시 생성된 Runtime LObject, 실패 시 `nil, 오류 문자열`을 반환한다. 실패를 계속 진행할지 `assert`로 게임 오류 경계에 전달할지는 프로젝트 코드에서 결정한다.

클래스 → 부모 Prefab → 자식 Prefab → 호출 override 순서로 값을 적용하고 구성·리소스/객체 참조 해석 후 컴포넌트 및 LObject beginPlay를 실행한다. 등록된 World에서 고유 runtime ID를 부여하며 생성 객체에는 authoring ID가 없다. 구성·beginPlay 실패 시 해당 호출과 그 초기화 안에서 생성한 객체를 목록에서 제거하고 ID를 재사용하지 않는다. 기존 객체에 이미 적용한 사용자 코드의 부수 효과는 되돌리지 않는다. 초기화 안의 중첩 생성은 최대 64단계다.

beginPlay는 즉시 실행한다. update 도중 생성된 객체는 다음 프레임부터 update하므로 생성된 객체가 같은 프레임 안에서 무한히 증식하는 반복을 피한다. 시작 beginPlay에서 생성한 객체는 첫 update부터 참여한다. 객체·컴포넌트 생성은 게임 동작이므로 Inspector에서도 실행되는 `build` 대신 `beginPlay`·`update`에 작성한다.

Editor Play와 Export한 게임은 동일한 런타임 생성 로직을 사용한다. Core World 자체는 프로젝트 파일을 읽지 않으며 WorldLoader가 Prefab 생성기를 연결한다.
