# 0050. LObject에 스크립트를 부착하고 에셋 루트를 통합한다

- 상태: 승인·구현
- 후속 확장: [0074](0074-scoped-scripts-and-screen-drawing.md)의 범위별 부착과 [0075](0075-inspector-scope-tabs-and-nested-script-groups.md)의 Inspector 표시.
- 인스턴스 부착 제한은 [ADR 0052](0052-local-scripts-and-fixed-inherited-topology.md)에서 로컬 부착 허용으로 변경했다.
- 대체 범위: [0017](0017-components-instance-properties-and-prefab-placement.md)의 컴포넌트 모델과 이후 컴포넌트 상속 구조. 계층 Prefab·스포이드·초안·카메라 투영 계약은 유지한다.

## 배경과 제약

LObject 자손 계층과 SceneComponent 계층이 위치·부모 관계를 중복 표현했다. Lua 클래스를 오브젝트 원본으로 사용하는 방식은 독립 행동을 여러 개 조합하기 어려웠다. LÖVE의 직접적인 Lua 프로그래밍을 유지하면서 AI와 GUI가 같은 데이터를 편집해야 한다. 이번 전환에는 플러그인을 포함하지 않는다.

## 대안과 판단 기준

컴포넌트 모델 유지, LObject 단일 상속, 스크립트 부착을 검토했다. 중복 Transform 제거, 조합 가능성, 기존 Prefab 계층·프로퍼티 재정의 보존을 기준으로 스크립트 부착을 선택했다. 편의 스크립트도 제거하는 대안은 기본 카메라·입력 좌표 일관성을 잃으므로 채택하지 않았다.

## 결정과 근거

LObject가 Transform과 자손을 소유한다. 독립 Script 인스턴스를 안정적인 부착 ID로 여러 개 소유한다. self는 Script이고 self.owner가 LObject다. 생명주기 함수는 선택 사항이며 구현된 update/draw만 등록한다. 부모 오브젝트부터 자손으로, 같은 오브젝트에서는 부착 순서로 실행한다. 렌더링·입력은 명시적 우선순위도 반영한다.

Camera·Sprite·Pointer·Rect·Canvas는 Script를 직접 상속한다. Bounds는 선택적인 공간 판정 유틸리티이며 상속 단계가 아니다. Lua 파일은 스크립트 정의이지 오브젝트 생성 템플릿이 아니다. spawnLObject의 원본은 Prefab이다. Prefab에서는 스크립트를 추가·제거·정렬하고 인스턴스에서는 해당 구성을 고정한 채 값을 재정의한다.

프로퍼티는 부착 ID로 구분하며 스크립트 참조는 {authoringId, script}로 저장한다. Prefab 형식 4, 레벨 형식 3을 사용한다. 모든 에셋은 Assets 아래에 둔다. Sources는 충돌이 없을 때 Assets/Scripts로 이동하고 메타데이터 ID를 보존한다. 이전 컴포넌트 코드·Prefab을 추측해 변환하지 않고 명확한 오류를 반환한다.

## 결과

- 긍정: 하나의 공간 계층, 여러 행동 조합, Lua와 GUI·CLI의 공용 부착 계약.
- 부정: 컴포넌트 API와 기존 Prefab 형식은 호환되지 않아 수동 전환이 필요하다.
- 중립: 레벨 스크립트는 별도로 유지한다. 과거 계약 테스트는 보존하고 새 구조 테스트를 별도로 실행한다.
