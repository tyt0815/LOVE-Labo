# 0047. 레벨 Main Camera 저장과 기본 카메라 생성

- 상태: 채택·구현
- 날짜: 2026-10-10
- 관련: [ADR 0046](0046-camera-screen-canvas-and-component-order.md)

## 배경과 제약

선택이 없는 Inspector에서 레벨 설정을 편집하고 새 레벨의 화면 범위를 즉시 확인해야 한다. GUI·CLI·Play·Export의 저장 계약을 공유하며 기존 레벨의 구성을 바꾸지 않는다.

## 대안과 판단 기준

첫 카메라 자동 선택만으로는 계층 순서에 기본 화면이 종속된다. 인스턴스만 저장하면 여러 카메라를 구별하지 못한다. 기본 카메라 전용 직렬화 타입 대신 기존 Lua Class·컴포넌트 계약을 사용한다. 보조 소스 생성도 같은 Undo 작업에 포함한다.

## 결정 및 근거

formatVersion 2의 선택적 mainCamera = {authoringId, component}를 저장한다. 누락은 Auto다. 런타임 구성 뒤 beginPlay 전에 지정하며 이후 setActiveCamera가 전환할 수 있다. 대상이 없거나 비활성이면 첫 enabled 카메라로 대체한다. 인스턴스 삭제 시 지정도 제거하고 Undo로 함께 복원한다.

빈 곳 클릭은 현재 레벨 Inspector를 표시한다. Main Camera는 스포이드로 인스턴스와 필요 시 컴포넌트 이름을 선택한다. 찾기는 프레이밍, 리셋은 Auto다. 사용자 propertyOverrides에는 저장하지 않는다.

새 레벨은 Sources/Defaults/Camera.lua를 일반 LObject Class로 생성·재사용하고 CameraComponent 루트 인스턴스를 Main Camera로 지정한다. 기본 크기 1280×720, zoom 1, 배치 Transform 0이다. 기존 클래스는 덮어쓰지 않고 카메라 루트 여부를 검사한다. 실제 루트 이름을 저장한다. 함께 생성한 파일·메타는 하나의 Undo/Redo로 복원한다.

기존 레벨 로드·Save As는 카메라를 추가하지 않는다. level create --empty 또는 JSON empty=true는 빈 레벨을 명시한다. level set-camera는 다중 카메라에 component 이름을 요구하며 instance 생략 또는 false는 Auto다. 아직 저장하지 않은 빈 편집 문서는 기존 상태를 유지한다.

## 예상 결과

- 긍정: 새 사용자와 AI가 동일한 기본 화면으로 시작하고 코드 없이 카메라를 지정한다.
- 부정: 최초 레벨 생성은 보조 소스·메타도 추가하여 생성 Undo와 외부 변경 충돌 검사가 필요하다.
- 중립: 카메라는 일반 프로젝트 클래스로 수정·상속할 수 있다. 파일 버전은 유지한다.
