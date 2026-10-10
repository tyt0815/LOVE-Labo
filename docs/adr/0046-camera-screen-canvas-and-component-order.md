# 0046. 카메라 투영과 화면 Canvas를 분리하고 렌더링·입력 순서를 공유한다

- 상태: 채택·구현
- 날짜: 2026-10-10
- 관련: [ADR 0045](0045-bounds-and-game-pointer-components.md)
- 부분 대체: [ADR 0035](0035-render-components-and-root-transform.md)의 원점 1:1 런타임 표시와 고정 순회 순서

## 배경과 제약

게임 카메라 이동·회전·확대와 화면 좌표 UI 계층이 필요하다. 카메라가 움직여도 UI는 화면에 남아야 하며, 렌더링과 클릭 판정의 좌표·순서는 일치해야 한다. 기존 월드 좌표 API와 에디터 편집 카메라는 유지한다.

## 대안과 판단 기준

- CameraComponent가 BoundsComponent를 상속하면 카메라의 가시 영역과 클릭·배치 영역을 같은 책임으로 묶게 된다. 카메라는 SceneComponent, 화면 영역 루트는 CanvasComponent로 구분한다.
- 우선순위만을 위한 공통 상속 단계를 넣으면 영역 자체에도 불필요한 순서 책임이 생긴다. RenderComponent와 PointerComponent에 각각 필요한 프로퍼티를 둔다.
- UI를 별도 객체 시스템으로 만들면 기존 오브젝트·컴포넌트 계층과 프로퍼티 저장을 중복한다. Canvas 아래에서 기존 계층을 재사용한다.
- 화면 비율에 맞춰 카메라 영역을 늘리는 방식은 해상도별로 보이는 내용이 달라진다. 기준 너비·높이를 유지하고 여백으로 맞춘다.

## 결정 및 근거

CameraComponent는 기준 `viewWidth/viewHeight`, `zoom`, `enabled`를 갖는다. 월드 위치와 합성 Z 방향을 사용하고 스케일·X/Y 기울기는 투영에 적용하지 않는다. Viewport가 카메라 범위를 화면 중앙에 맞춰 투영하며 비율이 다르면 여백을 둔다. 월드 렌더링과 새 클릭은 여백 밖으로 나가지 않지만 기존 포인터 캡처는 계속 전달한다. 카메라가 없으면 원점·배율 1을 유지한다. World는 `setActiveCamera`로 지정한 유효한 활성 카메라 또는 첫 번째 enabled 카메라를 사용한다.

카메라의 위치는 기존 전체 Transform 합성 결과를 유지한다. 방향은 카메라·컴포넌트 조상·오브젝트 조상의 로컬 Z 회전만 합산한다. 투영된 행렬에서 각도를 추출하지 않아 조상의 X/Y 기울기와 비균등 스케일도 방향에 영향을 주지 않는다.

CanvasComponent는 RectComponent → BoundsComponent를 상속한다. 화면 중심이 (0, 0), 오른쪽·아래가 양수이며 1단위는 1픽셀이다. `matchViewport` 기본값 true는 전체 뷰포트 크기를 사용하고 false는 지정한 width/height를 사용한다. Canvas의 로컬 Transform에서 화면 좌표계가 시작되므로 Canvas 위 조상의 월드 변환은 적용하지 않는다. 컴포넌트 자손과 Canvas를 루트로 한 오브젝트의 자손은 이 좌표계를 상속한다. Scene View에서는 기준 크기와 월드 배치로 편집하며 카메라의 기준 외곽선을 표시한다.

RectComponent는 렌더링 없이 사각형 크기를 제공한다. BoundsComponent의 `fillParent`는 가장 가까운 Bounds 조상의 영역을 자신의 로컬 영역으로 사용한다. 기본 로컬 Transform에서 부모 영역을 채우며 명시적인 위치·회전·스케일은 그대로 적용한다. Sprite는 그 영역에 이미지를 늘려 그린다. 영역 공유와 입력의 boundsSource 참조는 서로 다른 계약이며 Panel 별도 타입·앵커·여백·자손 클리핑은 추가하지 않는다.

ComponentOrder는 전체 객체의 컴포넌트를 정렬한다. 화면 Canvas는 월드보다 나중에 그리며 우선 입력을 받는다. 같은 좌표계에서는 RenderComponent.sortingOrder가 큰 순서로 앞에 표시된다. PointerComponent.inputPriority가 크면 먼저 입력을 받으며 기본 0은 boundsSource 렌더러의 sortingOrder와 순회 위치를 따른다. 동률은 기존 순회 순서를 유지한다. 에디터 렌더링·선택과 런타임 렌더링·입력 모두 같은 순서 계약을 사용한다.

Viewport는 화면·월드 좌표 변환을 Game View와 독립 실행 Host에 제공한다. 렌더링과 입력은 CoordinateSpace로 Canvas 경계를 해석한다. CLI `level.view`는 beginPlay 없이 구성한 카메라·Canvas와 좌표 변환을 조회하고, `level.pointer --space screen`은 beginPlay 이후 실제 입력 경로를 실행한다. 두 명령 모두 레벨 파일을 수정하지 않는다.

CLI 포인터 시퀀스도 이벤트마다 현재 World에서 Viewport를 생성한다. 이전 콜백의 카메라 이동·활성 카메라 전환·zoom 변경을 다음 입력에 즉시 반영하여 Game View·독립 실행 Host와 동일하게 처리한다.

## 예상 결과

- 긍정: 카메라 이동과 독립된 UI를 기존 계층으로 구성하며 Play·Export·CLI의 투영과 입력을 검증할 수 있다.
- 부정: 기준 카메라 비율과 화면 비율이 다르면 여백이 생긴다. 픽셀 기반 Canvas는 해상도에 따른 자동 확대 대신 크기가 변하므로 고급 반응형 배치는 별도로 설계해야 한다.
- 중립: 프로젝트 파일 버전은 유지하고 새 기능은 기존 컴포넌트 프로퍼티로 저장한다. 에디터 Scene 카메라와 게임 CameraComponent는 독립이다.
