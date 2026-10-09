# 0021. BeginPlay 초기화와 X/Y 직교 투영 회전

- 상태: 채택
- 후속: BeginPlay 및 모듈 표기는 [ADR 0036](0036-code-conventions-and-module-names.md)의 camelCase·PascalCase 계약으로 대체한다.
- 후속 확장: [ADR 0023](0023-text-edit-and-component-group-layout.md)의 컴포넌트 우선 정렬·그룹 경계
- 후속 부분 대체: [ADR 0022](0022-three-axis-rotation-gizmo.md)의 X/Y/Z 회전 기즈모
- 날짜: 2026-10-09
- 부분 대체: [ADR 0019](0019-transform-modes-and-relative-snap.md)의 Z 전용 Transform
- 부분 대체: [ADR 0020](0020-independent-snaps-and-inspector-selection.md)의 W/E/R 버튼
- 확장: [ADR 0012](0012-lua-classes-properties-and-unsaved-levels.md), [ADR 0017](0017-components-instance-properties-and-prefab-placement.md)의 생성 템플릿·초기화·Inspector 표시

## 배경과 제약

사용자는 파일명과 같은 클래스 이름, UE BeginPlay와 같은 초기화 이름, 컴포넌트별 접기, 100 단위 그리드, 작은 스냅 필드를 요청했다. 회전 기즈모는 Z만 유지하면서 Inspector X/Y 회전은 2D 직교 투영으로 추가하기로 확인했다. 기존 스크립트·레벨·Prefab과 Core의 Editor 비의존, Edit/Runtime 분리를 유지해야 한다.

## 대안과 판단 기준

- 기존 load를 즉시 삭제하면 프로젝트 코드와 부모 콜백 호출이 깨진다. 새 콜백을 우선하고 기존 이름을 호환시킨다. 파일 읽기 API와 LÖVE의 love.load는 역할이 다르므로 이름을 바꾸지 않는다.
- X/Y를 단순 축소만 하면 두 축을 함께 기울일 때 생기는 전단을 표현하지 못한다. 스케일 후 X/Y/Z 회전과 XY 투영을 하나의 2×2 기저로 계산한다. 원근·3D 깊이 정렬은 요구 범위를 넘는다.
- 컴포넌트 행을 평면 목록으로 유지하면 많은 속성 때문에 탐색이 어렵다. 선언에 컴포넌트 표시 정보를 추가하고 UI 헤더로 묶되 저장 키와 override 계약은 유지한다.
- 클래스 이름은 유효한 Lua 식별자일 때 파일명을 그대로 사용한다. 공백·기호는 밑줄로 보정하고 숫자 시작·예약어는 Class_를 붙인다. 한글만 있는 이름은 기존 종류별 이름으로 대체해 생성 코드가 실행 가능하게 한다.

## 결정 및 근거

1. Level/LObject Class와 LObjectComponent의 시작 콜백을 BeginPlay로 정의한다. 기존 load/Load를 지원하고 직접 선언된 두 이름은 BeginPlay가 우선한다. Lua Class 로더는 기존 콜백을 양방향 별칭으로 연결하여 상속과 기존 super.load 호출을 유지한다. 컴포넌트는 가까운 클래스에서 선언한 BeginPlay/Load를 찾아 기존 자식 Load가 부모 BeginPlay에 가려지지 않게 한다. 실행 순서·동적 컴포넌트 시작·오류 격리는 유지한다.
2. 새 클래스 템플릿은 생성 모듈의 파일명으로 지역 테이블·함수 수신자·반환값 이름을 정한다. ClassName 유틸리티는 템플릿의 의존이며 런타임 클래스 상속에는 참여하지 않는다.
3. Transform에 rotationX/Y를 기본 0으로 추가한다. rotation은 기존 Z 필드다. 세 각도는 0 이상 360 미만으로 정규화하고 기본값은 저장에서 생략한다. 직교 투영 기저를 Sprite 렌더링·상대 위치·클릭 역변환·선택 외곽선·스케일 축에서 공유한다. [LÖVE Transform:setMatrix](https://www.love2d.org/wiki/Transform:setMatrix)의 affine 행렬로 전단까지 그린다.
4. 투영 면적이 0인 정확한 옆면 상태는 역행렬을 만들지 않고 Sprite 클릭을 거부한다. Hierarchy 선택과 기즈모 조작은 가능하며 거의 사라진 스케일 축에는 기존 Z 방향을 사용한다. Z 회전 링은 X/Y를 변경하지 않는다.
5. ClassInspector는 클래스 속성 아래 컴포넌트별 접힌 헤더를 표시한다. 헤더와 펼쳐진 속성의 높이를 합쳐 픽셀 스크롤·클리핑을 적용한다. 접기 상태는 transient Editor UI 상태이며 레벨·Prefab override를 변경하지 않는다.
6. W/E/R 모드 버튼을 없애고 좌상단 단축키 힌트를 표시한다. 우상단 패널에는 독립 Move/Rot/Scale 스냅 버튼·값만 남긴다. 필드 폭은 현재 폰트의 세 자리 숫자와 여백으로 계산하고 좁은 화면에서는 세로 배치한다. 그리드는 기본 100 월드 단위이며 기존 스냅 값 저장과 독립적이다.

## 예상 결과

- 긍정: 초기화 역할이 명확하고 새 파일의 클래스 이름을 찾기 쉽다. Inspector의 컴포넌트 그룹과 작은 도구 패널로 공간을 절약하며 X/Y 기울기와 실제 Sprite 범위가 일치한다.
- 부정: 직교 투영에서는 기울기에 따른 깊이감이 없고 정확한 옆면 Sprite를 이미지 클릭으로 선택할 수 없다. 세 회전 필드로 Inspector Transform 영역이 커진다.
- 중립: 기존 JSON 버전·컴포넌트 상속·소유 관계를 유지한다. 음수 스케일·3D 카메라·깊이 버퍼·X/Y 회전 기즈모는 포함하지 않는다.
