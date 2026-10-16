# 0049. 카메라 선택을 Main Camera 지정과 런타임 전환으로 통일한다

- View 등록·출력 대상과 레벨 전용 카메라 설정은 [ADR 0078](0078-registered-views-and-render-targets.md)으로 부분 대체한다.

- 상태: 채택·구현
- 날짜: 2026-10-10
- 부분 대체: [ADR 0046](0046-camera-screen-canvas-and-component-order.md), [ADR 0047](0047-level-main-camera-and-default-camera.md)의 enabled 선택 조건

## 배경과 제약

현재 게임 화면은 하나의 카메라를 사용한다. Main Camera와 setActiveCamera로 대상을 정할 수 있으며 별도 enabled 값은 지정한 카메라 대신 다른 카메라가 사용되는 추가 조건을 만든다.

## 대안과 판단 기준

enabled를 유지하면 선택과 사용 가능 여부를 각각 제어할 수 있지만 현재 단일 카메라 화면에는 필요하지 않다. 선택 API만 유지하면 Inspector와 코드에서 화면 대상을 명확하게 정할 수 있다. 동시 다중 카메라 렌더링은 현재 범위에 포함하지 않는다.

## 결정 및 근거

CameraComponent의 enabled 프로퍼티를 제거한다. World는 자신에게 속한 지정 카메라가 존재하면 이를 사용하며, 지정이 없거나 대상이 제거되면 첫 번째 카메라를 사용한다. 카메라가 없으면 원점·배율 1의 기본 뷰를 사용한다. setActiveCamera(nil)은 자동 선택으로 돌아간다. PointerComponent의 enabled는 입력 전달 여부를 제어하는 별도 계약이므로 유지한다.

viewWidth/viewHeight는 출력 픽셀 수가 아닌 보이는 월드 범위다. 너비·높이와 zoom으로 가시 영역을 정하고 실제 뷰포트에 비율을 유지해 맞추는 기존 계약은 유지한다.

## 예상 결과

- 긍정: Main Camera 지정과 실제 화면 대상 사이의 숨은 활성 조건이 사라진다.
- 부정: 카메라를 임시 제외하려면 다른 카메라를 명시적으로 선택해야 한다.
- 중립: 상속 계층·레벨 mainCamera 저장 형식·화면 투영은 유지한다.
