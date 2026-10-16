# 0084. Script 공통 설정으로 업데이트·그리기 순서를 제어한다

> 카메라·화면 공간·입력·배치 계약은 [ADR 0085](0085-public-projection-layout-and-input.md)에서 부분 대체한다.

- 상태: 채택·구현
- 날짜: 2026-10-16
- 부분 대체: [0046](0046-camera-screen-canvas-and-component-order.md)의 제공 렌더러 전용 sortingOrder, [0074](0074-scoped-scripts-and-screen-drawing.md)의 고정 범위별 update·draw 순서
- 표시 확장: [0080](0080-script-header-toggle-and-property-labels.md)

## 배경과 제약

제공 플러그인에 의존하지 않는 사용자 Script도 실행·그리기 순서를 설정할 수 있어야 한다. 스크립트 전체의 enabled는 유지하고 update·draw별 활성 상태는 추가하지 않는다. 기존 계층·부착 순서, 초기화·종료와 좌표계 구분, 편집·CLI·Export의 일관성을 보존한다.

## 대안과 판단 기준

- Rendering.bindOrder 등록 API는 모든 Script에 필요한 단순 순서 설정에 등록·정리 부담을 추가한다.
- 단일 order는 업데이트와 그리기 순서를 불필요하게 결합한다.
- 클래스별 순서 설정은 같은 클래스를 여러 번 부착한 인스턴스별 제어를 제한한다.
- 공통 프로퍼티 두 개는 기존 상속·재정의·저장·Undo·CLI 경로를 재사용한다.

## 결정 및 근거

Script는 enabled 외에 유한 숫자 updateOrder·drawOrder를 기본 0으로 제공한다. 재선언으로 기본값을 바꿀 수 있지만 그룹은 Script로 유지한다. 작은 수부터 실행하고 동률은 기존 순서로 처리한다. enabled는 헤더 토글에 유지한다. Inspector는 update 구현 시 Update order, draw 또는 drawScreen 구현 시 Draw order만 표시하며 상속한 콜백도 포함한다. Script 그룹은 다른 프로퍼티 그룹보다 먼저 표시한다. 이 필터는 표시만 제한하며 저장 스키마·런타임 속성은 공통으로 제공한다.

World는 Project·Level·부모 우선 Object·부착 순서로 모든 update를 수집한 뒤 updateOrder로 정렬한다. 프레임 시작에 값과 목록을 고정하므로 실행 중 순서 변경·새 부착은 다음 프레임에 반영한다. 제거·비활성화는 실행 직전에 검사한다. 레거시 Level update는 순서 0으로 Level 부착 뒤의 동률 위치를 유지한다. load·unload·일반 이벤트 순서는 변경하지 않는다.

Renderer와 Pointer 판정은 공통 drawOrder를 사용한다. 일반 draw의 같은 좌표계 안에서 Project·Level·Object를 함께 정렬한다. Canvas는 월드보다 뒤, drawScreen은 일반 draw 뒤라는 기존 단계는 유지한다. drawScreen은 Canvas 소속과 무관한 단일 화면 좌표 단계이며 동률 기본 순서는 Object → Level → Project다. 각 그리기 단계 시작에 목록·순서를 고정하며 변경은 다음 해당 단계부터 반영한다. inputPriority는 별도 입력 우선순위로 유지하고 boundsSource의 drawOrder를 사용한다. View의 order는 화면 출력 간 순서로 별개다.

Sprite·Text의 sortingOrder 선언은 제거한다. 해당 키를 선언하지 않은 Script의 과거 저장값은 drawOrder로 읽고, 동일 계층에 둘이 함께 저장되면 drawOrder를 우선한다. 각 Prefab 계층과 인스턴스의 저장 키를 정규화한 뒤 병합하여 부모의 새 키가 자식의 이전 키 재정의를 가리지 않게 한다. Inspector 편집 후 저장은 새 키를 사용한다. sortingOrder를 여전히 선언하는 기존 사용자 Script는 기존 정렬의 읽기 호환을 유지하며, 새 drawOrder가 0이 아니면 이를 우선한다. 새 스크립트·예제·코드는 drawOrder를 사용한다.

```text
World ──의존──> ScriptOrder (모든 호스트의 update 스냅샷·정렬)
World ──의존──> ScriptHost (실행 직전 생존·enabled 검사, 콜백 실행)
Renderer·PointerInput ──의존──> ScriptOrder (drawOrder 정렬)
Script ──상속──> 사용자·제공 스크립트 (공통 설정)
ClassInspector ──조회──> Script 콜백·스키마 (조건부 표시)
```

## 예상 결과

- 긍정: 플러그인 없이 순서를 제어하고 인스턴스별 설정과 코드·CLI·Inspector를 공유한다.
- 부정: 순서에 의존하는 게임 로직은 숫자 설정을 함께 관리해야 하며 전역 정렬 비용이 발생한다.
- 중립: 저장 형식 버전과 활성 상태 계약은 유지한다. Canvas·Camera의 특별 취급을 없애는 재설계는 이번 변경에 포함하지 않는다.
