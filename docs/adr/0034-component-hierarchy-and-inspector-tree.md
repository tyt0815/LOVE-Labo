# 0034. 컴포넌트 부착 계층과 Inspector 선택 트리

- 상태: 채택
- 날짜: 2026-10-09
- 부분 대체: [ADR 0017](0017-components-instance-properties-and-prefab-placement.md)의 평면 컴포넌트 소유·상대 위치와 계층 제외 범위
- 부분 대체: [ADR 0024](0024-collapsible-details-and-property-columns.md)의 컴포넌트 중첩 그룹, [ADR 0033](0033-prefab-spawn-and-resource-inspector.md)의 컴포넌트 내부 Transform 하위 그룹
- 유지: Lua 코드가 구성의 원본이며 Core는 Editor에 의존하지 않는다. 기존 컴포넌트 이름·override 저장 계약을 유지한다.

## 배경과 제약

컴포넌트를 자손으로 부착하고 코드에서 루트를 바꾸며 Inspector 트리에서 객체 또는 컴포넌트를 선택하여 편집해야 한다. Component Class도 기존 부모 선택 → 폴더·이름 생성 흐름을 사용한다. 프로퍼티는 기본 클래스 이름 그룹 외에 선언에서 별도 그룹을 지정할 수 있어야 한다. 기존 파일·CLI와 LÖVE 11.5/Lua 5.1 호환성을 유지한다.

## 대안과 판단 기준

- 계층을 JSON에 새로 저장하면 코드 구성이 두 원본으로 나뉜다. `build`에서 계층을 구성하고 기존 이름별 override만 저장한다.
- 공간 컴포넌트만 계층에 넣으면 비공간 컴포넌트를 별도로 표시·소유해야 한다. 모든 컴포넌트에 parent/children을 제공하고 SceneComponent 조상만 상대 위치 계산에 참여시킨다.
- 계층 경로를 저장 키로 쓰면 재부착 시 override가 끊긴다. LObject 전체에서 이름을 유일하게 유지한다.
- 컴포넌트 아래 프로퍼티 그룹을 다시 중첩하면 편집 범위가 불명확하다. 위에는 선택 트리, 아래에는 선택 대상의 평면 프로퍼티 그룹만 둔다.
- 별도 Component 로더·CLI를 만들면 상속·에셋 계약이 갈라진다. 기존 LuaClass와 클래스 생성 경로에 component 종류 및 내장 부모를 추가한다.

## 결정 및 근거

1. LObject 생성 시 `root`라는 SceneComponent를 자동 소유한다. `addComponent(name, class, overrides, parent)`의 parent 생략은 현재 루트에 부착한다. parent는 같은 owner의 컴포넌트 또는 이름이며 `component:addComponent(...)`와 `component:attachTo(parent)`도 제공한다. 루트 재부착·외부 owner·자신/자손 순환은 거절한다.
2. `setRootComponent(name, class, overrides)` 또는 기존 컴포넌트/이름으로 루트를 지정한다. 루트는 SceneComponent 계열이어야 한다. 기본 루트는 제거하고 기존 자손을 새 루트로 옮긴다. 사용자 루트를 다른 이름의 루트로 바꾸면 기존 루트는 새 루트의 자식으로 보존한다. 같은 이름의 루트 교체는 기존 루트를 제거하고 자손을 옮긴다. 실패한 구성은 이전 등록 목록과 부착 관계를 복구하며 사용자 코드의 일반 부수 효과는 복구하지 않는다.
3. `components`는 이름 조회, `componentOrder`는 기존 등록 목록을 유지한다. `getComponentOrder()`가 루트 우선 깊이 순회를 제공한다. Update·초기화·렌더링은 부착 계층을 따른다. 런타임 build 중 추가한 모든 컴포넌트의 BeginPlay는 가장 바깥쪽 구성이 끝난 뒤 부모부터 한 번씩 실행한다. 다른 서브트리 아래에 추가한 컴포넌트도 포함한다. 초기화 진행 상태를 별도로 관리하며 콜백 안의 루트 교체·추가는 현재 콜백 반환 후 새 계층에서 처리하여 재진입을 막는다. 실패 시 진행 상태를 해제한다. 중첩 build는 64단계를 넘지 못한다.
4. SceneComponent의 x/y는 부모 계층에 대한 상대 위치다. 비공간 조상은 건너뛰고 SceneComponent 조상의 상대 위치를 합산한 뒤 LObject의 회전·스케일·이동을 적용한다. Sprite 렌더링·히트·외곽선은 같은 계산을 공유한다. 컴포넌트 회전·스케일 프로퍼티는 이번 변경에서 추가하지 않는다.
5. Component Class는 `-- labo-script: component` 및 기존 component 메타데이터를 쓴다. 반환하는 일반 테이블의 extends는 내장 LObjectComponent/SceneComponent/SpriteComponent 이름 또는 부모 Component Class 에셋 ID다. 생략 시 LObjectComponent를 사용한다. 선택한 부모를 실제 Core 컴포넌트 프로토타입으로 확장하며 build·BeginPlay/Load·Update를 지원한다. 다른 종류의 부모는 거절한다.
6. ObjectDefinition이 프로젝트 클래스 로더를 LObject에 주입하여 `addComponent`/`setRootComponent`에서 Component Class 에셋 ID를 받는다. Core는 파일이나 Project를 직접 읽지 않는다. Editor 미리보기·Play·Spawn·Export에서 같은 구성과 로더를 사용한다.
7. Inspector는 Prefab/인스턴스 → 루트 → 자손 트리를 먼저 표시한다. 트리의 객체 노드는 객체 프로퍼티와 기존 Actor Transform, 컴포넌트 노드는 해당 컴포넌트 프로퍼티만 보여준다. 트리 선택은 Scene의 객체 선택을 바꾸지 않는다. 계층 접기·펼침과 독립 스크롤·방향키를 지원하고 이 UI 상태는 직렬화하지 않는다.
8. 프로퍼티 선언의 `group = "Movement"`는 선택적 비어 있지 않은 문자열이다. 부모의 지정 그룹은 자식에서 생략하면 상속한다. 미지정 프로퍼티는 현재 선택 클래스 이름 그룹에 표시한다. SceneComponent x/y는 Transform 그룹이며 UI만 X/Y로 표시한다. 모든 프로퍼티 그룹은 같은 깊이이고 기본 펼침이다. 기존 override 키·값·파일 버전은 변하지 않는다.

## 관계

```text
상속: LObjectComponent ← SceneComponent ← SpriteComponent / 사용자 Component Class

소유·부착: LObject
           └─ rootComponent (SceneComponent 계열)
              ├─ Component
              │  └─ Component
              └─ Component

의존·주입: Project LuaClass → ObjectDefinition → LObject.componentLoader
UI 포함: ClassInspector → ComponentTree / 선택 대상의 프로퍼티 그룹
렌더 의존: SpriteRenderer → SceneComponent.getRelativePosition / Actor Transform
```

## 예상 결과

- 긍정: 기존 override 데이터를 유지하면서 계층 구성·루트 교체·Component Class 재사용을 지원한다. Inspector의 편집 대상과 범위가 명확해진다. GUI·CLI·게임에서 같은 계층을 사용한다.
- 부정: 컴포넌트 이름은 LObject 전체에서 충돌하지 않아야 한다. build는 미리보기에서도 실행되므로 부작용을 피해야 하며 코드의 이름·루트 타입 변경은 기존 override 호환성에 영향을 줄 수 있다.
- 중립: 컴포넌트 추가·재부착·루트 교체는 코드로만 한다. Prefab의 구성 override, UI에서 계층 편집, 컴포넌트 회전/스케일·소켓·깊이 정렬은 추가하지 않는다.
