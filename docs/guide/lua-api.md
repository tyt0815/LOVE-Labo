# Lua API 개요

게임 소스는 Lua 5.1/LuaJIT 계약을 사용합니다. `require("Engine")`로 런타임 기본 타입을 가져옵니다. 프로젝트의 Lua 클래스·Prefab 참조는 에셋 ID로 저장되어 파일을 이동해도 유지됩니다.

| 대상 | 주요 역할 |
|---|---|
| LObject Class | properties 선언, build/beginPlay/update 구현 |
| Level Class | 레벨 프로퍼티와 World 생명주기 |
| LObjectComponent | beginPlay(world), update(dt) |
| SceneComponent | 로컬 Transform과 부모 합성 |
| BoundsComponent | getLocalBounds(context), getBounds(context), hitTest(context, x, y) |
| RenderComponent | draw(context), sortingOrder |
| SpriteComponent | image 참조와 이미지 렌더링 |
| CameraComponent | viewWidth/viewHeight/zoom/enabled |
| RectComponent / CanvasComponent | 사각형 크기 / 화면 좌표계 루트 |
| PointerComponent | onPointerDown/up/move, boundsSource, blockPointer, inputPriority |

## 생명주기

```lua
-- labo-script: lobject
local Engine = require("Engine")
local Player = {properties = {speed = {type = "number", default = 100}}}
function Player.build(self)
    self:setRootComponent("sprite", Engine.SpriteComponent)
end
function Player.beginPlay(self, world)
    self.world = world
end
function Player.update(self, dt)
    self.transform.x = self.transform.x + self.properties.speed * dt
end
return Player
```

build는 구성을 선언하며 에디터 프리뷰에서도 실행됩니다. beginPlay는 Play·게임 초기화, update는 초 단위 dt에 따른 진행입니다. 새 코드는 beginPlay를 사용하며 기존 load는 호환성을 위해 읽을 수 있습니다.

클래스 테이블과 파일은 PascalCase, 변수·함수는 camelCase, 상수는 UPPER_SNAKE_CASE, 들여쓰기는 공백 4칸입니다. LÖVE 콜백은 외부 API의 이름을 그대로 사용합니다.

## World API

- `world:spawnLObject(template, transform, overrides)`: Class 또는 Prefab에서 생성합니다. [생성 API](../runtime-spawn.md)를 참고하세요.
- `world:openLevel(reference)`: 다음 프레임 경계에서 레벨을 전환합니다. [레벨 전환](../level-transition.md)을 참고하세요.
- `world:setActiveCamera(component)`: 같은 World의 CameraComponent를 지정합니다. nil이면 자동 선택으로 돌아갑니다.
- `world:getActiveCamera()`: 유효한 지정 카메라 또는 첫 번째 enabled 카메라를 반환합니다.

## 컴포넌트 API

`self:addComponent(name, class, overrides, parent)`, `self:setRootComponent(name, class, overrides)`로 구성합니다. `component:addComponent(...)` 또는 `child:attachTo(parent)`로 계층을 만듭니다. 컴포넌트 이름은 같은 LObject 안에서 유일해야 합니다. 선언·참조·사용자 정의 렌더링은 [컴포넌트](../components.md)를 참고하세요.

컴포넌트 구성은 build 코드에서 선언하고, 값 편집은 Inspector·CLI를 사용합니다.
