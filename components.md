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
}

-- 에디터에서도 실행되므로 게임 동작 없이 구성만 선언한다.
function Actor.build(self)
    self:addComponent("sprite", Engine.SpriteComponent, {x = 0, y = 0})
end

function Actor.load(self, world)
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

Inspector의 `sprite.image`에서 Assets의 이미지를 선택한다. 이미지를 외부에서 추가했다면 Asset Browser의 Refresh를 누른다. `sprite.x/y`는 LObject 위치에 대한 상대 좌표다. `target`에서 같은 레벨의 인스턴스를 선택하고, 참조를 지울 때는 None을 선택한다. 숫자·문자열은 입력 후 Enter, boolean은 버튼으로 수정한다. 각 필드의 R 버튼은 Prefab/클래스 기본값으로 복원한다.

Prefab에서 바꾼 값은 인스턴스의 기본값이 된다. 인스턴스의 변경값은 레벨에 따로 저장된다. 객체·컴포넌트 복제는 값 테이블을 공유하지 않으며, 다른 인스턴스 참조는 같은 대상을 유지한다. 순환 참조도 가능하다. 참조한 객체를 삭제하면 Missing으로 표시되며 참조를 수정하기 전까지 Play 시작이 실패한다. 참조는 같은 레벨 내에서만 사용한다. Prefab의 object 필드는 None으로 두고 배치한 인스턴스에서 대상을 지정한다.

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

function Counter:Load(world)
    self.elapsed = 0
end

function Counter:Update(dt)
    self.elapsed = self.elapsed + dt
end

-- Actor.build(self) 안에서 추가한다.
-- self:addComponent("counter", Counter)
```

컴포넌트의 Load는 초기 구성·참조 연결 후 실행되고 Update는 LObject update 다음에 실행된다. `self.components.sprite`로 컴포넌트를 가져오며 컴포넌트에서는 `self.owner`로 LObject를 가져온다. 컴포넌트 이름은 코드 식별자이며 저장 데이터의 키이므로 안정적으로 유지한다. 런타임 load에서 추가한 컴포넌트도 Load/Update를 지원하지만 Inspector 구성에는 포함되지 않는다. 부모 클래스의 build를 확장할 때는 `Actor.super.build(self)`를 명시적으로 호출한다.

이미지는 에셋 ID로 저장되어 Asset Browser에서 이동·이름 변경해도 연결을 유지한다. Sprite는 LObject의 `transform.rotation`(Z축, 도), `transform.scaleX/scaleY`(기본 1)를 적용한다. 컴포넌트의 상대 위치도 오브젝트의 회전·스케일을 따른다. Scene View의 이미지 영역 클릭으로 선택하고 기즈모로 이동·회전·스케일을 조절한다. 이미지 애니메이션은 아직 제공하지 않는다. Play에서 수정한 프로퍼티와 Transform은 Stop 시 버려진다.
