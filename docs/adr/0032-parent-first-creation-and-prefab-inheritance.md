# 0032. 부모 선택 생성 창과 Prefab 값 상속

- 상태: 채택
- 날짜: 2026-10-09
- 부분 대체: [ADR 0012](0012-lua-classes-properties-and-unsaved-levels.md)의 생성 타입 선택·Prefab 부모 범위
- 확장: [ADR 0031](0031-asset-operation-history.md)의 생성 Undo/Redo

## 배경과 제약

사용자는 클래스와 Prefab을 생성할 때 타입 선택 대신 상속 트리에서 부모를 고르고, 다음 창에서 폴더와 이름을 정하기를 요청했다. 우클릭한 폴더는 기본 저장 위치여야 한다. Prefab도 다른 Prefab을 부모로 선택하되 별도 Variant 명칭 없이 프로퍼티 값만 override한다. 기존 ID·저장 형식·CLI·게임 Export와 Lua가 컴포넌트 구성을 소유하는 원칙을 유지한다.

## 대안과 판단 기준

- 타입 목록과 부모 목록을 따로 두면 선택이 중복되거나 종류가 충돌한다. 내장 Level/LObject 루트와 같은 종류의 Lua 상속 트리에서 부모 선택으로 종류를 결정한다.
- 타입·경로·이름을 한 팝업에 모으면 트리를 충분히 표시하기 어렵다. Parent → Location and Name의 두 단계로 나누고 Back에서 입력을 보존한다.
- Lua 상속 관계를 정규식으로 읽으면 실제 반환 클래스와 다른 트리를 만들 수 있다. 기존 LuaClass 로더를 사용하고 선언 최상위 코드가 실행되는 기존 제약을 유지한다.
- Prefab 부모 값을 복사해 저장하면 부모 변경을 따라갈 수 없다. 부모 에셋 ID와 자신의 변경값만 저장하고 해석 시 조상부터 필드별로 병합한다.
- Variant 파일 형식을 추가하면 같은 목적의 에셋이 나뉜다. 기존 `.prefab` 및 버전 2 `definitionReference` ID를 유지한다.

## 결정 및 근거

1. ClassTree는 FolderTree를 상속하여 탐색·접기·펼치기·선택·스크롤 동작을 공유한다. Lua Class 생성은 Level/LObject 두 루트, Level 생성은 Level 루트, Prefab 생성은 LObject 루트만 표시한다. Prefab 창에는 Lua 상속과 Prefab 부모 연결을 함께 표시한다. 노드 이름은 경로 없이 표시하고 선택 요약/힌트에 경로를 제공한다. 오류가 있는 항목은 Invalid로 표시하고 Next를 거절한다.
2. CreateAssetDialog가 두 단계와 입력 상태를 소유한다. 첫 단계는 이름 입력 없이 부모 트리와 Next/Cancel, 두 번째는 이름·폴더 트리와 Back/Create/Cancel이다. 폴더 생성은 부모 선택 없이 위치·이름 단계만 제공한다. 우클릭 폴더 자체, 빈 공간·파일이면 현재 폴더가 기본이며 Lua는 Sources, 나머지 에셋은 Assets 안에서만 선택한다. Back·Next는 디스크를 변경하지 않고 Create 성공만 기존 에셋 기록에 넣는다.
3. Dialog는 onConfirm에서 다른 팝업을 열었을 때 새 창을 닫지 않는다. 내용 위젯의 배치·힌트를 선택적으로 지정하고 Back 콜백을 제공한다. IME를 확정한 이름을 단계 전환 시 보존한다.
4. Project.createEntry의 Lua 생성에 선택적인 `parentReference`를 추가한다. 부모 종류·등록 ID를 검증하고 템플릿의 `extends`에 ID를 쓴다. 상속 클래스의 템플릿은 빈 properties만 선언하며 부모의 build·BeginPlay·update를 빈 함수로 가리지 않는다. CLI class.create의 선택 `--parent`는 같은 API를 사용하며 종류를 자동 결정한다. 기존 부모 없는 템플릿과 `--type` 계약을 유지한다.
5. Prefab.definitionReference는 기존 ID 필드에 LObject Lua 또는 부모 Prefab을 가리킨다. ObjectDefinition.resolve가 조상을 재귀 해석하여 properties와 components의 각 필드를 병합한다. 값은 클래스 → 조상 Prefab → 자식 Prefab → 인스턴스 순서로 적용한다. boolean false와 숫자 0도 명시적 override로 보존한다. 매번 별도 테이블을 만들고 부모 데이터를 수정하지 않는다.
6. 순환은 에셋 ID 방문 집합으로, 과도한 깊이는 64단계 제한으로 검사한다. 부모가 없거나 클래스 종류가 다르면 오류를 반환한다. 각 부모의 프로퍼티와 컴포넌트 값도 검사하여 자식 덮어쓰기로 잘못된 부모 값이 숨겨지지 않게 한다. 구성 함수는 객체별 한 번 실행한 뒤 동일 컴포넌트 스키마로 단계별 값을 검증한다.
7. Prefab Inspector와 CLI의 기본값은 자신의 부모 체인을 해석해 얻는다. 따라서 롤백·기본값 비교는 최종 Lua 기본값이 아닌 바로 부모의 유효 값에 상대적이다. Parent Class 드롭다운은 부모 Prefab도 제공하며 자신/자손을 제외한다. 선택 시 다시 검증하여 외부 변경으로 생긴 순환도 거절한다. 부모 변경의 호환 값 유지 규칙은 기존과 같다.
8. 컴포넌트 추가·제거·순서 변경·중첩 Prefab 인스턴스는 제공하지 않는다. 구성은 Lua 클래스, Prefab은 값의 변경만 소유한다. 런타임과 Export는 동일 Project 해석 계층을 사용한다.

## 관계

```text
AssetBrowser
└─ 의존 → CreateAssetDialog (단계·입력 상태)
           ├─ 포함 → Dialog → 포함 → ClassTree ─ 상속 → FolderTree ─ 상속 → Widget
           └─ 의존 → Project.createEntry / AssetOperations (파일·Undo)

ObjectDefinition
├─ 의존 → Prefab (ID 부모 체인·값 병합)
└─ 의존 → LuaClass (종류·스키마·동작)
ClassInspector / CLI / WorldLoader ─ 의존 → ObjectDefinition
```

## 예상 결과

- 긍정: 부모 선택과 종류가 일치하며 우클릭 위치에서 빠르게 에셋을 생성한다. Prefab 변형을 최소한의 변경값으로 저장하고 부모 수정이 미수정 필드에 전파된다.
- 부정: 상속 트리를 구성할 때 Lua 선언과 Prefab을 읽는 비용이 발생하며 선언 최상위 부작용을 격리하지 않는다. 외부 부모 변경 후 Refresh가 필요하다.
- 중립: 파일 형식 버전·리소스 ID·저장 Undo 범위는 유지한다. 깊은 상속을 권장하거나 컴포넌트 composition 기능을 확대하지 않는다.
