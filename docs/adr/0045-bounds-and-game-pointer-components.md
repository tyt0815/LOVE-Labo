# 0045. 렌더링과 게임 포인터 입력이 공간 영역 계약을 공유한다

- 상태: 채택·구현
- 날짜: 2026-10-10
- 관련: [ADR 0035](0035-render-components-and-root-transform.md), [ADR 0044](0044-expanded-authoring-cli.md)

## 배경과 제약

렌더링하지 않는 클릭 영역과 렌더링만 하는 컴포넌트를 모두 지원해야 한다. 게임 입력은 에디터 선택 입력과 구분하고 Editor Play와 독립 실행 게임에서 같은 판정·소비 규칙을 사용해야 한다. 자손의 합성 Transform과 이미지 크기도 판정에 반영해야 한다.

## 대안과 판단 기준

- RenderComponent에 입력 여부와 콜백을 추가하면 보이지 않는 입력 영역도 렌더링 책임에 종속된다.
- 렌더링과 입력의 영역 계산을 따로 구현하면 Transform·이미지 크기 판정이 달라질 수 있다.
- SceneComponent와 RenderComponent 사이에 PointerComponent를 넣으면 모든 렌더러가 입력 기능을 상속한다. 공통 공간 계약 아래에서 두 책임을 분리한다.

## 결정 및 근거

BoundsComponent는 SceneComponent를 상속하며 `getLocalBounds(context)`와 월드 좌표 `hitTest`를 제공한다. RenderComponent와 PointerComponent는 BoundsComponent를 각각 상속한다. SpriteComponent의 기존 영역 계산을 렌더링 선택과 게임 입력에서 함께 사용한다.

PointerComponent는 자체 사각형 또는 같은 LObject의 `boundsSource` 이름으로 지정한 BoundsComponent를 판정에 사용한다. 참조 영역의 Transform도 그대로 사용하며 잘못된 이름과 순환 참조는 오류로 처리한다. 별도의 컴포넌트 참조 자료형은 추가하지 않는다.

참조 대상의 실제 `hitTest` 재정의를 호출하므로 원형·이미지 투명도 등의 사용자 정의 판정도 유지한다. PointerComponent 참조 사슬의 순환 검사는 호출 전에 수행한다.

`onPointerDown`, `onPointerUp`, `onPointerMove` 콜백이 true를 반환하거나 `blockPointer`가 켜져 있으면 입력을 소비한다. 그리는 순서의 역순으로 판정하며 소비되기 전까지 뒤쪽 컴포넌트에도 전달한다. 소비한 down은 버튼별 캡처를 만들고 영역 밖 move/up도 전달한다. 포커스 상실·Play 종료·입력 오류에서는 캡처를 해제한다. 콜백 오류는 호스트의 오류 처리로 전달한다.

Editor Play의 Game View UI 캡처는 런타임에 남아 있는 버튼별 캡처가 모두 끝날 때까지 유지한다. UI의 마지막 단일 버튼 release만으로 다른 버튼의 영역 밖 입력을 끊지 않는다.

World는 PointerInput에 입력 처리를 위임하고 호스트는 화면 좌표를 월드 좌표로 변환한다. 게임 입력은 에디터의 오브젝트 선택을 바꾸지 않는다. `level.pointer` CLI는 같은 런타임 경로로 입력을 검증하며 레벨 파일을 저장하지 않는다.

## 예상 결과

- 긍정: 보이지 않는 버튼 영역과 Sprite 기반 클릭을 같은 계약으로 구현하고 Play·Export·CLI에서 검증한다.
- 부정: 영역 공유 이름은 코드와 Inspector에서 일치시켜야 하며 잘못된 참조는 입력 오류가 된다.
- 중립: 현재 범위는 마우스 down/up/move이다. 키보드·터치·휠·hover 이벤트는 별도 요구가 생길 때 설계한다.
