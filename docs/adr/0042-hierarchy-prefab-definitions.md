# 0042. 루트 오브젝트와 자손을 하나의 Prefab 생성 정의로 저장한다

- 상태: 채택·구현
- 날짜: 2026-10-09
- 확장: [ADR 0032](0032-parent-first-creation-and-prefab-inheritance.md), [ADR 0037](0037-object-hierarchy-and-multi-selection.md), [ADR 0039](0039-lobject-templates-and-resource-picking.md)
- Inspector 선택 구조 대체: [ADR 0034](0034-component-hierarchy-and-inspector-tree.md)
- 상호작용: [ADR 0041](0041-inspector-picking-over-drag-exceptions.md)

## 배경과 제약

기존 Prefab은 단일 LObject 클래스의 프로퍼티 변형이었다. 사용자는 루트와 자손 오브젝트를 함께 저장·생성하고, Inspector에서 오브젝트와 컴포넌트를 각각 선택하기를 요청했다. 기존 부모 Prefab 값 상속, 에셋 ID, 레벨 배치 ID, 루트 Transform의 단일 소유권, 미저장 초안과 Export의 일치는 유지해야 한다.

## 대안과 판단 기준

- 레벨 레코드를 그대로 복사하면 원래 authoring ID와 외부 객체 참조가 새 인스턴스에 섞이고 중첩 Prefab 원본 변경을 전파하기 어렵다.
- 오브젝트와 컴포넌트를 하나의 트리로 합치면 구성 단위와 부모 Transform 관계가 혼동된다.
- 안정적인 자손 ID와 생성 레시피를 사용하면 상속·중첩·내부 참조를 동일한 로더에서 처리하고 각 생성의 mutable 값을 분리할 수 있다.

## 결정 및 근거

1. Prefab formatVersion 3에 `children`, `bindings`, `removedPaths`를 추가한다. 기존 1·2 형식은 계속 읽고 빈 계층으로 취급한다. 각 자손은 형제 안에서 고유한 문자열 ID, 원본 참조, 이름, 로컬 Transform·프로퍼티 override, 자손을 갖는다.
2. 부모 Prefab과 자손 override는 안정적인 ID로 합성한다. Transform은 필드별로 상속한다. Lua 클래스나 Prefab을 자손 원본으로 사용할 수 있으며 자동 확장되는 순환 원본은 거절한다.
3. 내부 객체 참조는 authoring ID 대신 `root/<child-id>/...` 경로 바인딩으로 저장한다. 생성 후 실제 새 객체끼리 연결한다. 캡처 범위 밖의 레벨 객체 참조는 오류로 거절하며 자동으로 지우지 않는다.
4. 계층의 `Create Prefab...`은 선택 루트와 모든 자손의 현재 값을 저장하고 원래 레벨을 유지한다. Inspector의 `Add Child → Pick Source...`는 클래스 기본값, 연결된 Prefab, 레벨 인스턴스의 현재 계층 복사를 구분한다.
5. 배치 시 자손을 레벨 authoring 객체로 구체화하고 `prefabRootId`·`prefabNodePath`로 원본 계층에 연결한다. 기존 레벨의 단일 루트 레코드도 로딩 시 확장한다. 생성 자손을 삭제·외부로 분리하면 원래 그룹에 제거 경로를 남긴다. 분리한 가지는 현재 유효 값을 보존한다.
6. `spawnLObject`는 전체 계층을 구성하고 내부 참조를 연결한 뒤 초기화하며 반환값은 루트다. Play와 독립 게임에서 동일한 생성 레시피를 사용한다. 실제 객체·컴포넌트는 생성마다 새로 만든다.
7. Prefab Inspector는 오브젝트 계층 → 선택 오브젝트 Parent Class → 오브젝트 프로퍼티 → 컴포넌트 계층 → 선택 컴포넌트 프로퍼티 순이다. 인스턴스는 오브젝트 프로퍼티부터 표시한다. Prefab 루트 Transform과 중복 루트 컴포넌트 Transform은 숨긴다. 컴포넌트 구성 자체는 Lua 코드가 소유한다.

```text
PrefabHierarchy --의존--> ObjectDefinition
TemplateObjects --의존--> PrefabHierarchy의 생성 레시피
LObject 루트 --포함--> 자손 LObject --포함--> 컴포넌트 계층
ClassInspector --포함--> ObjectTree, ComponentTree
PrefabEditor --의존--> PrefabHierarchy
```

## 예상 결과

- 긍정: 계층 전체를 재사용하며 상속 기본값과 각 배치 override를 분리한다. 내부 참조가 복제된 자기 계층을 가리킨다. Inspector 선택도 두 구성 단위로 구분된다.
- 부정: 저장 형식과 생성 로더가 복잡해지고 경로 안정성 및 레벨 구체화 동기화를 검증해야 한다. 외부 참조가 있는 계층은 참조 정리 후 캡처해야 한다.
- 중립: 에디터에서 컴포넌트를 추가·삭제하는 기능, Prefab 오브젝트 노드 삭제·재부모화 UI는 이번 결정의 구현 범위가 아니다. Lua 클래스는 계속 코드 원본이며 생성 정의 추상화는 별도 에셋 파일을 요구하지 않는다.
