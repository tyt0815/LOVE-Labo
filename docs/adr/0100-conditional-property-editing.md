# 0100. 선언적인 조건으로 Inspector 프로퍼티 편집을 제한한다

- 상태: 채택·구현
- 날짜: 2026-10-19
- 관련: [0075](0075-inspector-scope-tabs-and-nested-script-groups.md), [0080](0080-script-header-toggle-and-property-labels.md), [0085](0085-public-projection-layout-and-input.md), [0095](0095-pie-runtime-editing-and-input-ownership.md)

## 배경과 제약

설정 조합에 따라 사용하지 않는 필드를 Inspector에서 구분할 필요가 있다. 편집 불가 상태에서 기존 값·Prefab 상속·재정의를 보존하고, Project·Level·Object·Prefab 및 런타임 Inspector가 같은 규칙을 사용해야 한다. Core는 Editor에 의존하지 않으며 게임 동작을 UI 메타데이터로 제한하지 않는다.

## 대안과 판단 기준

- Inspector 갱신 전 사용자 콜백은 임의 부작용과 호출 시점 의존성을 추가한다. 현재 요구는 다른 값과의 일치 조건으로 충분하다.
- 필드를 숨기면 설정의 존재와 비활성 이유를 찾기 어렵다. 행을 유지하고 흐리게 표시한다.
- 런타임·CLI 할당도 금지하면 편집 편의 설정이 게임 로직과 저장 계약을 바꾼다. Inspector 입력 경로에서만 제한한다.

## 결정 및 근거

프로퍼티에 `enabledIf = {다른프로퍼티 = 비교값}`을 선언한다. 같은 부착의 boolean·number·string 값에 대한 모든 일치 조건을 검사한다. 조건의 활성 상태를 재귀적으로 평가하지 않고 현재 값만 읽는다. 필드 선언 순서와 무관하게 전체 스키마 생성 후 참조·비교값을 검증한다. 자기 참조·미등록 필드·빈 조건·참조 타입은 거부한다. 조건 함수를 실행하지 않는다.

파생 클래스는 조건을 상속하며 명시적 false로 제거한다. 조건 테이블은 복사하고, Inspector용 평면 스키마를 만들 때 의존 이름에도 부착 ID 접두사를 적용한다. 이 방식으로 같은 소스의 여러 부착을 격리한다. 기존 `0.1.0-dev`의 배포 준비 범위에 포함하며 저장 형식과 CLI 스키마 버전은 변경하지 않는다.

ClassInspector는 상속 기본값·현재 재정의를 매번 평가한다. 런타임은 현재 Script 값을 읽는다. 값 변경의 공통 진입점과 마우스 행 입력을 모두 검사하여 입력·드래그·리셋·스포이드·선택 목록을 막고, 편집 중 조건이 바뀌면 텍스트 편집을 취소한다. 기존 값은 변경하지 않는다. 행을 흐리게 표시하고 필요한 조건을 툴팁으로 제공한다.

Canvas의 cameraSource에는 조건을 적용하지 않는다. matchCamera=false에서도 View 필터의 출력 대상 판정에 사용하므로, 배치 조건만으로 편집을 막으면 기존 기능이 손상된다.

```text
Script·LuaScript 로더 ──의존──> PropertySchema (조건 복사·선언 검증)
ObjectDefinition·RuntimeScene ──의존──> PropertySchema (부착별 조건 이름 변환)
ClassInspector ──의존──> PropertySchema (조건 평가)
ClassInspector ──조회──> 편집 대상의 현재 값·상속 기본값
```

상속·인터페이스·포함 구조는 추가하지 않는다. 기존 스키마와 Inspector에 메타데이터·편집 판단 책임을 배치한다.

## 예상 결과

- 긍정: 부적절한 조합의 편집을 줄이고 비활성 이유·기존 값을 유지한다. 플러그인과 사용자 스크립트가 같은 선언을 사용한다.
- 부정: 복잡한 논리식·범위 비교·다른 부착의 조건은 표현할 수 없다. 필요 없는 조합을 런타임에서 무시할 책임은 스크립트에 남는다.
- 중립: 저장값·CLI·Lua 할당 계약은 유지한다. 부모 채우기·Widget·Inspector 사용자 콜백은 이 결정에 포함하지 않는다.
