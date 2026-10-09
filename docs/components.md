# 컴포넌트와 Inspector 프로퍼티

아래 코드를 프로젝트의 LObject Class에 작성하고 이 클래스를 부모로 하는 Prefab을 만든다. Asset Browser에서 Prefab을 Scene View로 드래그하면 배치된다. 배치 인스턴스를 선택하면 위치와 아래 선언한 값들이 Inspector에 표시된다.

```lua
-- labo-script: lobject
local Engine = require("Engine")
local Actor = {}

Actor.properties = {
    speed = {type = "number", default = 100},
    title = {type = "string", default = "캐릭터"},
    enabled = {type = "boolean", default = true},
    target = {type = "object", default = false},
    projectile = {type = "lobjectTemplate", default = false},
}

-- 에디터에서도 실행되므로 게임 동작 없이 구성만 선언한다.
function Actor.build(self)
    local mount = self:addComponent("mount", Engine.SceneComponent, {x = 20, y = 0})
    mount:addComponent("sprite", Engine.SpriteComponent, {x = 0, y = 0})
end

function Actor.beginPlay(self, world)
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

Inspector 위쪽 계층 트리에서 `sprite (SpriteComponent)`를 선택한 다음 `image`의 드롭다운 또는 스포이드로 Assets의 이미지를 지정한다. 이미지를 외부에서 추가했다면 Asset Browser의 Refresh를 누른다. 선택한 SceneComponent의 `Transform` 그룹은 부모 계층에 대한 상대 위치를 `X/Y`로 표시하며 코드·저장에는 `x/y`를 쓴다. 트리와 프로퍼티 그룹은 기본 펼침이며 접기·선택 상태는 저장 데이터에 포함하지 않는다. 객체 노드를 선택하면 객체의 Actor Transform과 클래스 프로퍼티가 나타난다. `target` 옆 스포이드를 누르고 같은 레벨의 인스턴스를 Scene View 또는 Hierarchy에서 클릭한다. 찾기 버튼은 대상을 프레이밍하고 리셋은 기본 참조(None)로 복원한다. 숫자·문자열은 입력 후 Enter, boolean은 버튼으로 수정한다. 각 필드의 되돌리기 화살표 아이콘(↺)은 Prefab/클래스 기본값으로 복원한다.

`projectile`에는 LObject Lua 클래스 또는 Prefab을 드롭다운·스포이드로 지정한다. 스포이드로 인스턴스를 선택하면 직접 원본을 사용한다. 이미지·생성 템플릿·Parent Class의 찾기는 폴더를 열고 잠시 강조하며 선택과 Inspector를 유지한다. 일반 에셋 클릭·드래그는 해당 에셋의 Inspector를 연다. 이미지 행은 두 줄이며 리셋은 드롭다운 오른쪽, 스포이드·찾기는 아래에 있다. 런타임 생성은 [spawnLObject 사용법](runtime-spawn.md)을 참고한다.

Prefab 값 변경은 저장 전에도 배치된 인스턴스의 기본값과 Play에 적용된다. 인스턴스의 개별 override가 우선한다. Inspector 오른쪽 위 Save 또는 Ctrl+S는 현재 문서를 저장한다. File → Save All 또는 Ctrl+Shift+S는 변경된 Prefab·레벨 목록을 기본 체크된 체크박스로 보여주며 확인한 대상만 저장한다. 행 클릭·Space로 체크를 전환한다. 체크 해제·취소는 초안을 유지하고, 체크된 이름 없는 레벨은 확인 후 경로를 입력한다.

Prefab에서 바꾼 값은 인스턴스의 기본값이 된다. 인스턴스의 변경값은 레벨에 따로 저장된다. 객체·컴포넌트 복제는 값 테이블을 공유하지 않으며, 다른 인스턴스 참조는 같은 대상을 유지한다. 순환 참조도 가능하다. 참조한 객체를 삭제하면 Missing으로 표시되며 참조를 수정하기 전까지 Play 시작이 실패한다. 참조는 같은 레벨 내에서만 사용한다. Prefab의 object 필드는 None으로 두고 배치한 인스턴스에서 대상을 지정한다.

Inspector는 **계층 트리 → 선택 대상의 프로퍼티 그룹** 순이다. 트리에는 Prefab 또는 인스턴스, 루트, 자손·손자 컴포넌트를 들여써서 표시한다. 트리 선택은 뷰포트의 객체 선택을 유지한다. `Actor.lua`의 기본 오브젝트 프로퍼티는 `Actor` 그룹, SpriteComponent의 기본 프로퍼티는 `SpriteComponent` 그룹에 표시한다. 각 그룹은 같은 깊이이고 기본 펼침이다. 각 행은 왼쪽 절반에 이름, 오른쪽 절반에 값과 초기값 복원 아이콘을 둔다. 펼친 그룹은 하나의 배경 박스와 테두리로 범위를 표시한다. 복원 아이콘은 기본적으로 기호만 보인다. 텍스트 필드는 마우스 클릭·좌우/Home/End로 커서를 옮기고, 드래그·Shift 이동으로 선택한 문자만 입력·붙여넣기로 교체한다. 한글 조합도 커서 위치에 삽입된다.

프로퍼티 선언에 `group = "Movement"`를 추가하면 별도 그룹에 표시한다. 객체·레벨·컴포넌트 모두 같은 문법을 쓰며 부모의 지정 그룹은 자식에서 생략하면 상속한다. 그룹 이름은 비어 있지 않은 문자열이어야 한다. SceneComponent의 x/y는 기본 `Transform` 그룹이다.

```lua
Actor.properties.speed = {type = "number", default = 100, group = "Movement"}
Actor.properties.title = {type = "string", default = "Actor"} -- Actor 그룹
```

```text
LObjectComponent
└─ SceneComponent        (상속: Transform)
   └─ RenderComponent    (상속: draw / getLocalBounds)
      └─ SpriteComponent (상속: 이미지 렌더링)

LObject ── 소유 ── root (SceneComponent)
                   └─ mount (SceneComponent)
                      └─ sprite (SpriteComponent)
Scene/Game View ── 의존 ── Renderer ── 호출 ── RenderComponent.draw
```

사용자 컴포넌트도 코드를 통해 만들 수 있다. 저장·편집할 값만 `properties`에 선언하고 임시 상태는 일반 필드로 둔다.

이미지 외의 렌더링은 RenderComponent를 부모로 하고 `draw(self, context)`를 구현한다. draw에서는 컴포넌트의 **로컬 좌표**로 그린다. 공용 Renderer가 부모 Transform·카메라·줌을 적용하고 그래픽 상태를 복원한다. 사용자 draw는 Scene View에서도 실행되므로 게임 상태를 변경하는 코드는 beginPlay/update에 둔다. `context:image(assetId)`로 호스트의 이미지 캐시를 사용할 수 있다. 선택·외곽선을 지원하려면 `getLocalBounds`에서 로컬 사각형의 x/y/width/height를 반환한다.

```lua
-- labo-script: component
local Shape = {extends = "RenderComponent", properties = {
    size = {type = "number", default = 20},
}}
function Shape.draw(self, context)
    local size = self.properties.size
    love.graphics.setColor(1, 0.5, 0.2, 1)
    love.graphics.rectangle("fill", -size / 2, -size / 2, size, size)
end
function Shape.getLocalBounds(self, context)
    local size = self.properties.size
    return -size / 2, -size / 2, size, size
end
return Shape
```

SpriteComponent는 draw에서 이미지를 중앙 원점에 그리는 구현이다. 이를 상속해 draw를 재정의할 때 `Visual.super.draw(self, context)`로 부모 구현을 호출할 수 있다. draw의 `false` 반환은 표시할 내용 없음, `false, error` 또는 예외는 렌더링 실패이며 호스트에서 처리한다. 반환을 생략하면 그리기를 수행한 것으로 처리한다. getLocalBounds를 생략하면 영역 클릭·외곽선 없이 기존 원점·Hierarchy 선택을 사용한다.

기본 루트는 이름이 `root`인 SceneComponent다. `addComponent`의 네 번째 인자에 같은 객체의 부모 컴포넌트 또는 이름을 지정하고, 생략하면 현재 루트에 부착한다. `component:addComponent(...)`는 해당 컴포넌트 아래에 부착하고 `child:attachTo(parent)`로 재부착한다. 이름은 LObject 전체에서 유일해야 하며 순환·다른 객체로의 부착은 거절한다. 자손은 SceneComponent 부모의 위치·회전·스케일을 이어받는다. 일반 LObjectComponent는 공간 변환에 참여하지 않는다.

```lua
-- Actor.build(self)에서 기본 루트를 SpriteComponent로 교체한다.
self:setRootComponent("root", Engine.SpriteComponent)
local arm = self:addComponent("arm", Engine.SceneComponent, {x = 20}, self.rootComponent)
local hand = arm:addComponent("hand", Engine.SpriteComponent, {x = 10})
hand:attachTo(self.rootComponent)
-- 이미 부착한 SceneComponent를 루트로 지정할 수도 있다.
-- self:setRootComponent(arm)
```

루트는 SceneComponent 계열이어야 한다. 루트 Transform이 곧 인스턴스 Transform이며 `self.transform`은 `self.rootComponent.transform`으로 위임한다. 루트 교체 시 기존 인스턴스 Transform을 유지한다. 기본 루트는 제거하고 기존 자식들을 새 루트로 옮긴다. 사용자 루트를 다른 이름의 루트로 바꾸면 기존 루트는 단위 로컬 Transform의 자식으로 남는다. 같은 이름으로 교체하면 기존 루트를 제거하고 자식들을 옮긴다. 자손은 위치·회전·스케일이 포함된 상대 Transform을 갖는다.

Prefab Inspector에서는 **루트 Transform을 숨긴다**. 루트의 이미지·일반 프로퍼티와 자손 Transform은 계속 편집할 수 있다. 인스턴스의 객체 노드와 루트 노드에서는 같은 배치 Transform을 편집하며 레벨의 `transform`에 한 번만 저장한다. 기존 Prefab·인스턴스 `componentOverrides`의 루트 로컬 offset은 더하지 않는다. 이전에 루트 offset으로 이동시켰다면 인스턴스 배치 또는 자손 Transform으로 옮긴다. 기존 파일을 자동 수정하지 않는다.

```lua
self.rootComponent.transform.x = 100 -- self.transform.x와 같은 값
self.components.hand.transform.rotation = 45 -- 부모 기준 Z 회전
self.components.hand.properties.scaleX = 2 -- transform.scaleX와 같은 값
```

Transform 필드는 `x/y`, `rotationX/rotationY/rotation`(도), `scaleX/scaleY`다. 각도는 setter에서 0 이상 360 미만, 스케일은 양수로 검사한다. Transform을 순회할 때는 `component.transform`을 사용한다. `component.properties`의 Transform 필드는 위임 접근이므로 `pairs(properties)`에는 포함되지 않는다.

**File → New → Lua Class** 또는 Asset Browser 우클릭 생성에서 LObjectComponent·SceneComponent·RenderComponent·SpriteComponent 또는 사용자 Component Class를 부모로 선택한다. Component Class는 일반 테이블을 반환하며 `extends`에 내장 부모 이름 또는 Component Class 에셋 ID를 지정한다. 생략하면 LObjectComponent다. 별도 `extend` 호출은 로더가 처리한다. 예를 들어 `Sources/Visual.lua`:

```lua
-- labo-script: component
local Visual = {
    extends = "SpriteComponent",
    properties = {opacity = {type = "number", default = 1, group = "Appearance"}},
}
function Visual.beginPlay(self, world) self.elapsed = 0 end
function Visual.update(self, dt) self.elapsed = self.elapsed + dt end
return Visual
```

LObject의 build에서 `self:addComponent("visual", "<Visual의 실제 에셋 ID>")`로 부착하거나 `self:setRootComponent("root", "<Visual의 실제 에셋 ID>")`로 루트를 교체한다. 실제 ID는 `.lua.meta` 또는 Cli 응답을 사용한다. Component Class의 선택적 `build(self)`에서 `self:addComponent(...)`로 자손을 구성할 수 있다. 기존처럼 코드 안에서 Core 프로토타입을 직접 확장해도 된다:

```lua
local Counter = Engine.LObjectComponent:extend({
    properties = {count = {type = "number", default = 0}},
})

function Counter:beginPlay(world)
    self.elapsed = 0
end

function Counter:update(dt)
    self.elapsed = self.elapsed + dt
end

-- Actor.build(self) 안에서 추가한다.
-- self:addComponent("counter", Counter)
```

컴포넌트의 beginPlay는 초기 구성·참조 연결 후 실행되고 update는 LObject update 다음에 실행된다. `self.components.sprite`로 컴포넌트를 가져오며 컴포넌트에서는 `self.owner`로 LObject를 가져온다. 컴포넌트 이름은 코드 식별자이며 저장 데이터의 키이므로 안정적으로 유지한다. 런타임 beginPlay에서 추가한 컴포넌트도 beginPlay/update를 지원하지만 Inspector 구성에는 포함되지 않는다. 부모 클래스의 build를 확장할 때는 `Actor.super.build(self)`를 명시적으로 호출한다.

기존 클래스의 `load`와 컴포넌트의 `load`도 초기화 콜백으로 지원한다. 새 코드는 `beginPlay`를 사용한다. 같은 클래스가 두 이름을 선언하면 `beginPlay`를 우선하여 한 번만 호출한다. Editor 구성·Inspector 조회는 beginPlay를 실행하지 않는다.

이미지는 에셋 ID로 저장되어 Asset Browser에서 이동·이름 변경해도 연결을 유지한다. Sprite는 LObject의 `transform.rotationX/rotationY/rotation`(X/Y/Z축, 도, 기본 0), `transform.scaleX/scaleY`(기본 1)를 적용한다. 각도는 편집·저장·로드 시 0 이상 360 미만이다. 스케일 → X → Y → Z 회전 후 XY 직교 투영하며 원근·깊이 정렬은 없다. 컴포넌트 상대 위치도 같은 변환을 따른다. Inspector에서 세 축을 입력한다. 회전 기즈모의 위쪽 선은 X, 오른쪽 선은 Y, 우상단 호는 Z 회전이다. X/Y 선 드래그 중에는 활성 축의 지름선만, Z 호 드래그 중에는 전체 원을 표시한다. Scene View의 이미지 영역 클릭으로 선택하며 정확히 옆면을 향한 Sprite는 Hierarchy로 선택한다. 선택한 각 Sprite의 투영된 이미지 크기 외곽선을 표시한다. 이미지 애니메이션은 아직 제공하지 않는다. Play에서 수정한 프로퍼티와 Transform은 Stop 시 버려진다.
