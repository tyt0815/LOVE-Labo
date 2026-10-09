# 0033. Prefab 런타임 생성과 리소스 Inspector 입력

- 상태: 채택
- 후속: SpawnLObject·BeginPlay 및 모듈 표기는 [ADR 0036](0036-code-conventions-and-module-names.md)으로 대체한다.
- 후속: 컴포넌트 내부 중첩 Transform 배치는 [ADR 0034](0034-component-hierarchy-and-inspector-tree.md)의 선택별 평면 그룹으로 대체한다.
- 날짜: 2026-10-09
- 확장: [ADR 0032](0032-parent-first-creation-and-prefab-inheritance.md)의 Prefab 값 상속·생성 단계
- 부분 대체: [ADR 0026](0026-resource-property-previews-and-reveal.md)의 이미지 행 높이·리셋 배치
- 유지: [설계 문서](../LOVE_Labo_Design.md)의 Core → Editor 의존 금지 및 authoring/runtime 분리

## 배경과 제약

사용자는 Prefab 참조 프로퍼티를 선택하고 Lua에서 SpawnActor처럼 런타임 객체를 생성하기를 요청했다. 이미지 행은 두 줄로 줄이고 에셋·인스턴스 탐색을 일관되게 제공한다. 바로넣기 화살표는 후속 요청으로 취소하여 에셋 필드 드래그앤드롭을 사용한다. 객체 참조는 스포이드와 프레이밍을 제공한다. SceneComponent의 상대 위치도 Transform 하위 그룹으로 묶되 기존 필드 계약을 유지한다.

## 대안과 판단 기준

- Core가 Prefab 파일을 직접 읽으면 프로젝트·Editor 파일 해석에 의존한다. Core World는 생성 API만 제공하고 runtime 생성기를 주입한다.
- 원본 객체를 복제하면 mutable 상태·컴포넌트 참조를 공유할 수 있다. Prefab의 유효 기본값과 호출 override에서 새로운 객체를 구성한다.
- 생성 중 ipairs 순회에 객체를 추가하면 그 프레임 안에서 새 객체까지 계속 Update되어 무한 증식할 수 있다. 프레임 시작 개수를 고정한다.
- 에셋 한 번 클릭을 선택 전용으로 바꾸면 기존 Inspector 탐색 의미가 달라진다. 클릭의 Inspector 변경을 마우스 해제 시까지 미루고 드래그 중에는 원래 편집 문맥을 유지한다.
- X/Y 저장 키를 대문자로 바꾸면 기존 코드·파일·CLI 계약을 깨뜨린다. UI 표시와 그룹만 바꾼다.

## 결정 및 근거

1. PropertySchema에 `prefab` 타입을 추가한다. 값은 `false` 또는 에셋 참조 문자열이며 직렬화는 기존 문자열·ID 필드로 유지한다. 런타임은 실제 Prefab 파일인지 검사하고 ID로 정규화한다. UI·CLI는 선택한 Prefab의 부모 체인도 검사하며 부모/인스턴스 override에 동일한 타입을 사용한다.
2. 공개 API는 `world:SpawnLObject(prefab, transform, overrides)`와 `Engine.SpawnLObject(world, ...)`이다. Core World는 파일을 읽지 않고 WorldLoader가 설치한 PrefabSpawner를 호출한다. 생성기는 기존 ObjectDefinition·클래스 로더·스키마·참조 해석·BeginPlay 경로를 공유한다. Editor Play와 Export 게임에 같은 모듈을 사용한다.
3. transform 생략은 원점/회전 0/스케일 1이며 지정 시 x/y를 요구하고 기존 유한값·각도 정규화·양수 스케일 검사를 사용한다. overrides는 properties/components를 필드별로 적용한다. 기존 레벨 객체의 authoring ID를 객체 참조 override로 사용할 수 있다.
4. 생성 객체는 World에 등록되고 고유 runtime ID만 갖는다. authoring ID·레벨 배치·편집 History를 만들지 않는다. 구성·참조 연결 후 BeginPlay를 즉시 호출하며 실패 시 이번 호출과 그 초기화 중 생성한 객체를 목록에서 제거한다. ID는 재사용하지 않고 기존 객체의 사용자 코드 부수 효과는 복구하지 않는다. 중첩 생성은 64단계로 제한한다.
5. API는 객체 또는 nil/오류 문자열을 반환한다. 사용자 코드가 실패를 처리하거나 assert로 기존 게임 오류 경계에 전달한다. World의 Update는 프레임 시작 객체 수만 순회하여 Update 안에서 생성한 객체는 다음 프레임부터 Update한다. 시작 BeginPlay에서 생성한 객체는 첫 Update부터 참여한다.
6. 이미지 행과 선택 목록은 64px이며 미리보기는 정사각형이다. 리셋은 드롭다운 오른쪽, 이미지 찾기는 아래, Prefab 참조·Parent Class의 찾기는 오른쪽이다. 바로넣기 버튼은 제공하지 않는다. 리소스 드롭다운과 이름만 표시하는 규칙은 유지한다.
7. AssetBrowser의 외부 드롭 대상에 Inspector를 추가한다. ClassInspector가 필드·종류·부모 순환을 검증하고 유효한 값만 설정한다. 드롭은 참조만 바꾸고 파일을 이동하지 않는다. 기존 Scene Prefab 배치·폴더 이동 드롭은 유지한다. 실제 마우스 드래그를 같은 입력 캡처 경로로 검증한다.
8. Inspector에서 열린 에셋은 ID로 별도 보관한다. 폴더 탐색·찾기는 브라우저 선택과 편집 대상을 독립적으로 유지한다. 파일 일반 클릭은 해제 시 기존 Inspector 전환을 실행하고 드래그는 이전 Inspector 문맥을 유지한다. 완료·실패·Escape·포커스 이탈로 드래그를 정리하고 기존 편집 대상으로 돌아간다.
9. `object` 타입은 드롭다운 대신 읽기 전용 값·스포이드·프레이밍·리셋을 표시한다. 스포이드 클릭 후 Scene의 이미지/객체 히트 테스트로 같은 레벨의 authoring ID를 저장한다. 기즈모 이동·선택 변경 없이 원래 Inspector 대상을 유지한다. Esc·우클릭·포커스 이탈·Play·문서 전환에서 모드와 커서를 정리한다. 프레이밍은 카메라만 바꾸고 기존 선택을 유지한다. 참조 변경은 문서 Undo에 기록한다.
10. Level·Prefab 생성 이름 기본값은 L_/PF_이며 이름 단계 진입 시 접두사 뒤 커서와 이름 포커스를 제공한다. SceneComponent 계열에는 컴포넌트 내부 Transform 그룹을 추가하고 x/y를 X/Y로 표시한다. 하위 Transform은 기본 펼침이며 컴포넌트 그룹과 독립적으로 접는다. 일반 컴포넌트에는 이를 추가하지 않는다. Lua·JSON·CLI의 x/y 키와 동작은 유지한다.

## 관계

```text
WorldLoader ─ 의존 → PrefabSpawner ─ 주입 → Core World.SpawnLObject
                       └─ 의존 → ObjectDefinition / LuaClass / LObject
Engine.SpawnLObject ─ 의존 → World.SpawnLObject

EditorApp
├─ 포함 → AssetBrowser ─ 드롭 전달 → ClassInspector
├─ 포함 → 스포이드 입력 상태 ─ 의존 → SceneView 히트 테스트·프레이밍
└─ 포함 → ClassInspector ─ 의존 → ObjectDefinition (Scene Transform 메타데이터)
```

## 예상 결과

- 긍정: 선언한 Prefab을 Inspector에서 선택하고 공용 런타임 생성 API로 게임 동작에 사용할 수 있다. 리소스 드롭과 인스턴스 선택은 편집 대상을 유지하며 기존 Undo를 사용한다.
- 부정: 잘못된/삭제된 리소스나 BeginPlay 오류는 생성 실패를 반환하며 호출자가 처리해야 한다. 중첩 생성의 기존 객체 부수 효과까지 원자적으로 복구하지는 않는다. 드래그 Hover의 부모 검증은 Lua 선언 로딩 비용을 갖는다.
- 중립: Save·파일 생성 Undo 범위, 컴포넌트 구성 책임, 렌더링 의미, 파일 형식 버전은 유지한다. Spawn의 authoring 배치·Destroy API·중첩 Prefab 구성은 추가하지 않는다.
