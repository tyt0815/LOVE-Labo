# 0037. 오브젝트 계층과 다중 선택

- 상태: 채택
- 날짜: 2026-10-09
- 부분 대체: [ADR 0035](0035-render-components-and-root-transform.md)의 부모 없는 오브젝트 루트 월드 Transform
- 유지: 루트 Transform 단일 원본, 컴포넌트 코드 구성, authoring/runtime 분리, Core의 Editor 비의존

## 배경과 제약

에셋·계층·뷰포트의 영역 선택, 다중 삭제·이동·복제, 오브젝트 부모 부착과 Prefab 계층 드롭이 필요하다. 기존 레벨과 안정적인 authoring ID, 파일 작업 Undo의 외부 변경 감지·복구 계약을 유지해야 한다. X/Y 회전은 실제 3D가 아닌 XY 직교 투영이다.

## 대안과 판단 기준

- 오브젝트마다 중첩 JSON을 저장하면 기존 인스턴스 ID 참조와 CLI 조회 방식이 바뀐다. 기존 평면 레지스트리와 선택적 부모 ID를 함께 사용한다.
- 다른 오브젝트의 컴포넌트 자식으로 직접 붙이면 컴포넌트의 단일 owner와 이름별 override 계약이 깨진다. 오브젝트 계층과 각 오브젝트의 컴포넌트 계층을 구분한다.
- 부모 변경 시 모든 월드 회전·스케일을 유지하려면 비균일 스케일과 X/Y 투영이 만든 shear를 기존 Euler 프로퍼티로 다시 표현해야 한다. 이번 계약은 월드 위치를 유지하고 로컬 회전·스케일을 유지한다. 부모의 회전·스케일에 따른 새 방향·크기는 즉시 적용한다.
- 파일 다중 작업마다 Undo를 기록하면 한 번의 드래그가 여러 Undo로 분리된다. 기존 단일 명령을 모아 하나의 복합 명령으로 실행하고 중간 실패 시 완료한 명령을 역순 복구한다.

## 결정 및 근거

1. 레벨 버전 2를 유지하고 인스턴스에 선택적 `name`, `parentAuthoringId`를 저장한다. 누락된 부모·순환은 파일 로드와 Runtime World 생성에서 거절한다. 과거 부모 없는 인스턴스는 그대로 읽으며 이름이 없으면 `LObject ID`로 표시한다.
2. authoring Level은 부모 ID로 트리 행과 월드 행렬을 계산한다. Runtime LObject는 `parent`와 `children`을 가진다. `attachTo(parent)`는 로컬 Transform을 유지하고 순환을 거절한다. 부모가 있는 LObject의 루트 Transform은 부모 오브젝트에 상대적이며 SceneComponent의 월드 행렬은 이 오브젝트 월드 행렬에서 시작한다.
3. Hierarchy 드래그와 CLI `instance.reparent`는 월드 위치를 보존한다. 빈 Hierarchy에 드롭하거나 Detach from Parent를 실행하면 최상위로 이동한다. 투영으로 역행렬이 없는 부모는 위치 보존 부착을 거절한다. Hierarchy의 Prefab 드롭은 부모의 로컬 원점에 인스턴스를 만든다.
4. SceneView가 Hierarchy·뷰포트의 공용 선택을 소유한다. 빈 영역 드래그는 사각형과 겹치는 항목을 선택하고 Ctrl은 선택 추가·해제를 제공한다. Hierarchy는 Shift 범위 선택도 제공한다. Inspector는 마지막 선택한 객체를 편집한다.
5. 다중 기즈모 이동은 선택된 최상위 오브젝트에만 적용하여 선택된 자손을 이중 이동하지 않는다. 회전·스케일은 각 최상위 선택의 로컬 Transform에 같은 변화량·배율을 적용한다. 복제·삭제는 각 선택의 자손을 포함하며 중복 처리하지 않는다. 복제 프로퍼티의 기존 객체 참조는 기존 대상을 유지한다.
6. 에셋 영역 선택은 목록·썸네일의 파일/폴더 영역에 적용한다. 다중 이동·삭제는 한 Undo 명령이고 Rename은 단일 선택에만 제공한다. Inspector 리소스 필드에는 한 에셋만 드롭한다. 여러 Prefab은 계층·뷰포트에 함께 드롭할 수 있다.
7. 새 인스턴스 이름은 파일 확장자를 제외한 정확한 Prefab 이름과 레벨 안에서 중복되지 않는 숫자 접미사다. CLI 배치와 런타임 spawn도 같은 이름 형식을 제공한다. Hierarchy의 컨텍스트 메뉴는 Duplicate, Delete, Frame Selection, Detach from Parent, Select All을 제공한다.

## 관계

```text
소유: Level / World → 오브젝트 레지스트리
부착: 부모 LObject → 자식 LObject → 자손 LObject
소유: 각 LObject → 루트 SceneComponent → 자손 컴포넌트
변환 의존: 자식 루트 월드 행렬 → 부모 LObject 월드 행렬 × 자식 로컬 행렬
선택 의존: Hierarchy / Viewport → SceneView의 공용 선택
파일 작업 의존: AssetBrowser → AssetOperations 복합 Undo 명령
```

## 예상 결과

- 긍정: 계층과 렌더링·클릭·기즈모가 같은 Transform을 사용하고 다중 선택의 자손이 중복 변경되지 않는다. 파일 다중 작업은 한 번에 복구된다.
- 부정: 부모 변경은 월드 방향·크기를 보존하지 않는다. 파일 복합 명령은 단일 작업보다 여러 번의 인덱스 재구성이 필요하다. 외부 변경이나 잠금이 복구까지 막으면 오류를 명시한다.
- 중립: Prefab의 오브젝트 트리 정의·저장과 다중 Inspector 동시 편집은 추가하지 않는다. 기존 Prefab 컴포넌트 구성과 인스턴스 override를 유지한다.
