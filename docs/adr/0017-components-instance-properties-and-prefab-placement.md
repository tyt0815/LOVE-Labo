# 0017. 컴포넌트 구성·인스턴스 프로퍼티와 Prefab 배치

- 상태: 채택
- 후속: Sprite 전용 렌더링은 [ADR 0035](0035-render-components-and-root-transform.md)의 RenderComponent Draw 오버라이드로 대체한다.
- 후속: 평면 부착·상대 위치·계층 제외 범위는 [ADR 0034](0034-component-hierarchy-and-inspector-tree.md)로 부분 대체한다.
- 날짜: 2026-10-09
- 확장: [ADR 0012](0012-lua-classes-properties-and-unsaved-levels.md)의 프로퍼티 선언·런타임 분리, [ADR 0013](0013-browser-drag-moves-and-asset-colors.md)의 드래그 전달

## 배경과 제약

Prefab을 뷰포트에 배치하고, 코드로 부착한 컴포넌트 및 인스턴스 프로퍼티를 편집해야 한다. 기본 자료형뿐 아니라 같은 레벨의 다른 LObject와 이미지도 참조해야 한다. LÖVE 11.5/Lua 5.1을 유지하며 Core는 Editor 파일시스템에 의존하지 않는다. Edit 상태에서 Load/Update를 실행하지 않고도 컴포넌트 구성을 알 수 있어야 한다.

## 대안과 판단 기준

- Load를 실행해 구성을 발견하면 게임 동작과 에디터 선언을 분리할 수 없다. 별도의 `build(self)`에서 이름이 고정된 컴포넌트를 부착한다.
- 컴포넌트를 Inspector에서 추가하면 코드가 정의한 구성이 데이터와 불일치한다. 추가·제거 UI 없이 코드 구성을 표시하고 노출된 값만 수정한다.
- Lua 객체 테이블을 그대로 저장하면 순환 참조와 편집/런타임 공유가 발생한다. 레벨 authoringId를 저장하고 Runtime에서 2단계로 해석한다.
- 이미지의 물리 경로를 저장하면 이동에 취약하다. 기존 에셋 ID를 저장하고 Editor 파일시스템 어댑터로 LÖVE Image를 로드한다.

## 결정 및 근거

1. 공개 `require("engine")` API로 `LObjectComponent`, `SceneComponent`, `SpriteComponent`를 제공한다. SceneComponent는 LObjectComponent를, SpriteComponent는 SceneComponent를 상속한다. 인터페이스 구현 관계는 없다.
2. `LObject:addComponent(name, class, values)`로 이름이 유일한 컴포넌트를 소유한다. 컴포넌트는 `properties`와 owner를 가지며 `Load(world)`, `Update(dt)`를 지원한다. 코드의 `build`에서 부착하면 Inspector에 나타난다. `load`에서 동적으로 부착한 컴포넌트는 Runtime 전용이다.
3. SceneComponent의 `properties.x/y`는 owner의 transform에 대한 상대 위치다. SpriteComponent의 `properties.image`는 이미지 ID이며 이미지는 원본 크기, 중앙 원점으로 그린다. Scene View의 줌과 Game View의 1:1 표시만 적용한다.
4. 기존 `{type, default}` 프로퍼티 선언을 유지하고 `object`, `image`를 추가한다. `false`는 참조 없음이다. object 값은 같은 레벨의 authoringId이며 이미지 값은 에셋 ID다. Inspector는 선택 목록과 기본값 복원을 제공한다.
5. Prefab의 `overrides.properties/components`, 배치 객체의 `propertyOverrides/componentOverrides`를 합친다. 기본값 → Prefab → 배치 객체 순서이며 이름으로 컴포넌트를 식별한다. 기존 버전 1/2 데이터는 새 필드 없이도 읽는다. 기존 저장 파일에 빈 필드를 추가하지 않는다.
6. 모든 Runtime 객체를 구성한 뒤 object 참조를 연결하고 컴포넌트 Load → LObject load → Level load 순서로 초기화한다. 참조 대상이 없으면 Play를 실패시키고 원본 데이터를 보존한다. 순환·전방 참조는 허용한다.
7. Asset Browser의 기존 포인터 캡처를 사용한다. Prefab을 Scene View에 드롭하면 카메라/줌을 적용한 월드 위치에 새 authoringId로 배치·선택한다. 브라우저 폴더 드롭은 기존 이동 동작을 유지한다. Play 중 배치, 잘못된 에셋, 저장 전 Prefab 배치는 거부한다.
8. Core SpriteRenderer는 이미지 조회·좌표 변환 함수를 받으며 Scene/Game View가 공유한다. Editor의 SpriteAssets는 파일 읽기·이미지 캐시·Load 없는 편집 미리보기를 담당하고 Refresh에서 캐시를 비운다.

## 예상 결과

- 긍정: 코드 구성을 유지하면서 Prefab·인스턴스·컴포넌트 데이터를 편집할 수 있다. 파일 이동에도 이미지 참조가 유지되고 순환 참조도 런타임 객체로 연결된다. Play의 값 변경은 원본에 반영되지 않는다.
- 부정: `build`는 Inspector와 미리보기에서도 실행되므로 부작용 없이 선언 중심으로 작성해야 한다. 코드의 컴포넌트 이름 변경은 저장된 override를 마이그레이션해야 하며 알 수 없는 이름은 Play 오류로 남는다. 삭제된 객체 참조는 None 또는 다른 객체로 사용자가 수정해야 한다.
- 중립: 컴포넌트 transform 계층, 회전·스케일, 이미지 애니메이션, 레벨 간 참조, 참조 자동 복구는 포함하지 않는다. Prefab 상속과 ECS 프레임워크를 도입하지 않는다.
