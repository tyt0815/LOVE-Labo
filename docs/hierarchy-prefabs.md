# 계층 Prefab

Prefab은 하나의 루트 LObject, 자손 LObject, 각 오브젝트의 부착 스크립트와 프로퍼티를 저장합니다. 컴포넌트 계층은 없습니다.

![Prefab 편집](guide/images/prefab-details.png)

Inspector는 오브젝트 계층 → Parent Prefab → 자손 Transform → 부착 스크립트 그룹 순서입니다. 루트 Transform은 숨기며 배치 위치는 레벨 인스턴스에서 설정합니다. 내부 계층은 3행 높이로 시작하며 하단 손잡이로 조절하고 자체 스크롤 끝에서는 Inspector 전체 스크롤로 이어집니다.

Hierarchy에서 루트를 우클릭하여 Create Prefab...을 선택하면 자손·현재 유효 값·부착 스크립트·내부 참조를 캡처합니다. Prefab 계층의 Add Child는 빈 LObject를 추가합니다. 다른 Prefab을 자손으로 넣는 작업은 기존 CLI prefab.child.add로 지원합니다. 순환 참조는 삽입을 취소하고 초안을 보존합니다. 일반 에셋 선택이 Inspector를 바꾸므로 Inspector에 드래그하지 않습니다.

![계층의 Prefab 묶음과 원본 찾기](guide/images/prefab-hierarchy.png)

같은 Prefab 소속을 옅은 배경색으로 묶고 선택한 묶음을 강조합니다. 중첩 원본은 별도 묶음을 시작합니다. 색상은 보조 표시이며 소속은 계층·원본 데이터로 결정합니다. 행의 돋보기로 원본 에셋을 찾고 Rename으로 해당 행에서 이름을 수정합니다.

파생 Prefab은 부모의 계층·부착 구성을 상속합니다. 프로퍼티와 Transform 편집은 값만 재정의하고 원본을 고정하지 않습니다. Parent Prefab을 명시적으로 바꿀 때만 원본 참조를 기록합니다. None은 명시적 false로 저장하여 상속 유지와 구분합니다. 자손 제거는 안정적인 경로로 저장합니다.

독립 복제·캡처는 유효 상속값을 보존합니다. 계층 내부 object/script 참조는 복제 자손에 다시 연결하며 외부 참조는 유지합니다. 연결된 자손 ID를 보존하고 새 형제 ID는 충돌을 피합니다. 원본에서 제거한 자손은 런타임에도 남지 않습니다.

Prefab 형식 4의 scripts는 `{id, source, label}` 목록입니다. overrides.scripts는 부착 ID별 값, removedScripts는 상속 부착 제거, scriptOrder는 순서 재정의입니다. children의 각 노드도 같은 구성을 가집니다. bindings는 from/to 노드 경로와 property를 저장하며 스크립트 대상에는 toScript 부착 ID를 추가합니다.
