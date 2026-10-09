# 컴포넌트와 Inspector 프로퍼티

아래 코드를 프로젝트의 LObject Class에 작성하고 이 클래스를 부모로 하는 Prefab을 만든다. Asset Browser에서 Prefab을 Scene View로 드래그하면 배치된다. 배치 인스턴스를 선택하면 위치와 아래 선언한 값들이 Inspector에 표시된다.

```lua
-- labo-script: lobject
local Engine = require("engine")
local Actor = {}

Actor.properties = {
    speed = {type = "number", default = 100},
    title = {type = "string", default = "캐릭터"},
    enabled = {type = "boolean", default = true},
    target = {type = "object", default = false},
    projectile = {type = "prefab", default = false},
}

-- 에디터에서도 실행되므로 게임 동작 없이 구성만 선언한다.
function Actor.build(self)
    self:addComponent("sprite", Engine.SpriteComponent, {x = 0, y = 0})
end

function Actor.BeginPlay(self, world)
    -- target은 Play에서 실제 Runtime LObject로 연결된다.
    local target = self.properties.target
    if target then self.transform.x = target.transform.x end
end

function Actor.update(self, dt)
    if self.properties.enabled then
        self.transform.x = self.transform.x + self.properties.speed * dt
    end
end

return Actor
```

Inspector에서 `> sprite (SpriteComponent)` 헤더를 눌러 펼친 다음 `image`에서 Assets의 이미지를 선택하거나 파일을 해당 필드로 드래그한다. 이미지를 외부에서 추가했다면 Asset Browser의 Refresh를 누른다. 내부 `Transform` 그룹의 `X/Y`는 LObject 위치에 대한 상대 좌표이며 코드·저장에는 `x/y`를 쓴다. 컴포넌트는 기본적으로 접혀 있고 내부 Transform은 펼침이며 접기 상태는 저장 데이터에 포함하지 않는다. `target` 옆 스포이드를 누르고 같은 레벨의 인스턴스를 Scene View에서 클릭한다. 찾기 버튼은 대상을 프레이밍하고 리셋은 기본 참조(None)로 복원한다. 숫자·문자열은 입력 후 Enter, boolean은 버튼으로 수정한다. 각 필드의 되돌리기 화살표 아이콘(↺)은 Prefab/클래스 기본값으로 복원한다.

`projectile`에는 다른 Prefab을 드롭다운 또는 드래그로 지정한다. 이미지·Prefab 참조·Parent Class의 찾기 버튼은 에셋 폴더를 열고 현재 리소스를 선택한다. 이 탐색과 드래그는 편집 중인 Inspector 대상을 바꾸지 않는다. 이미지 행은 두 줄이며 리셋은 드롭다운 오른쪽, 찾기는 아래에 있다. Prefab 런타임 생성은 [SpawnLObject 사용법](runtime-spawn.md)을 참고한다.

Prefab에서 바꾼 값은 인스턴스의 기본값이 된다. 인스턴스의 변경값은 레벨에 따로 저장된다. 객체·컴포넌트 복제는 값 테이블을 공유하지 않으며, 다른 인스턴스 참조는 같은 대상을 유지한다. 순환 참조도 가능하다. 참조한 객체를 삭제하면 Missing으로 표시되며 참조를 수정하기 전까지 Play 시작이 실패한다. 참조는 같은 레벨 내에서만 사용한다. Prefab의 object 필드는 None으로 두고 배치한 인스턴스에서 대상을 지정한다.

Inspector는 **Transform → 컴포넌트 그룹 → 클래스 이름 그룹** 순이다. 세 그룹 모두 접고 펼칠 수 있으며 기본적으로 Transform·클래스는 펼침, 컴포넌트는 접힘이다. `Actor.lua`의 오브젝트 프로퍼티는 `Actor` 그룹에 표시한다. 각 행은 왼쪽 절반에 이름, 오른쪽 절반에 값과 초기값 복원 아이콘을 둔다. 펼친 그룹은 하나의 배경 박스와 테두리로 범위를 표시한다. 복원 아이콘은 기본적으로 기호만 보인다. 텍스트 필드는 마우스 클릭·좌우/Home/End로 커서를 옮기고, 드래그·Shift 이동으로 선택한 문자만 입력·붙여넣기로 교체한다. 한글 조합도 커서 위치에 삽입된다.

```text
LObjectComponent
└─ SceneComponent        (상속: 상대 위치)
   └─ SpriteComponent    (상속: 이미지)

LObject ── 소유 ── 이름별 Component 인스턴스
Scene/Game View ── 의존 ── SpriteRenderer
```

사용자 컴포넌트도 코드를 통해 만들 수 있다. 저장·편집할 값만 `properties`에 선언하고 임시 상태는 일반 필드로 둔다.

```lua
local Counter = Engine.LObjectComponent:extend({
    properties = {count = {type = "number", default = 0}},
})

function Counter:BeginPlay(world)
    self.elapsed = 0
end

function Counter:Update(dt)
    self.elapsed = self.elapsed + dt
end

-- Actor.build(self) 안에서 추가한다.
-- self:addComponent("counter", Counter)
```

컴포넌트의 BeginPlay는 초기 구성·참조 연결 후 실행되고 Update는 LObject update 다음에 실행된다. `self.components.sprite`로 컴포넌트를 가져오며 컴포넌트에서는 `self.owner`로 LObject를 가져온다. 컴포넌트 이름은 코드 식별자이며 저장 데이터의 키이므로 안정적으로 유지한다. 런타임 BeginPlay에서 추가한 컴포넌트도 BeginPlay/Update를 지원하지만 Inspector 구성에는 포함되지 않는다. 부모 클래스의 build를 확장할 때는 `Actor.super.build(self)`를 명시적으로 호출한다.

기존 클래스의 `load`와 컴포넌트의 `Load`도 초기화 콜백으로 지원한다. 새 코드는 `BeginPlay`를 사용한다. 같은 클래스가 두 이름을 선언하면 `BeginPlay`를 우선하여 한 번만 호출한다. Editor 구성·Inspector 조회는 BeginPlay를 실행하지 않는다.

이미지는 에셋 ID로 저장되어 Asset Browser에서 이동·이름 변경해도 연결을 유지한다. Sprite는 LObject의 `transform.rotationX/rotationY/rotation`(X/Y/Z축, 도, 기본 0), `transform.scaleX/scaleY`(기본 1)를 적용한다. 각도는 편집·저장·로드 시 0 이상 360 미만이다. 스케일 → X → Y → Z 회전 후 XY 직교 투영하며 원근·깊이 정렬은 없다. 컴포넌트 상대 위치도 같은 변환을 따른다. Inspector에서 세 축을 입력한다. 회전 기즈모의 위쪽 선은 X, 오른쪽 선은 Y, 우상단 호는 Z 회전이다. X/Y 선 드래그 중에는 활성 축의 지름선만, Z 호 드래그 중에는 전체 원을 표시한다. Scene View의 이미지 영역 클릭으로 선택하며 정확히 옆면을 향한 Sprite는 Hierarchy로 선택한다. 선택한 각 Sprite의 투영된 이미지 크기 외곽선을 표시한다. 이미지 애니메이션은 아직 제공하지 않는다. Play에서 수정한 프로퍼티와 Transform은 Stop 시 버려진다.
