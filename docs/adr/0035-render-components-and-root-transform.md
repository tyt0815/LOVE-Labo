# 0035. Draw 오버라이드와 루트 Transform 통일

- 상태: 채택
- 후속: Draw·GetLocalBounds·모듈 이름은 [ADR 0036](0036-code-conventions-and-module-names.md)의 draw·getLocalBounds·PascalCase 파일명으로 대체한다.
- 날짜: 2026-10-09
- 부분 대체: [ADR 0017](0017-components-instance-properties-and-prefab-placement.md)의 Sprite 전용 렌더러
- 부분 대체: [ADR 0034](0034-component-hierarchy-and-inspector-tree.md)의 독립 Actor Transform·루트 로컬 위치·위치만 합산하는 계층
- 유지: Core의 Editor 비의존, 코드 구성 원본, 공용 Scene/Game 렌더링, authoring/runtime 상태 분리

## 배경과 제약

사용자는 컴포넌트별 Draw 오버라이드와 루트 Transform이 곧 인스턴스 Transform인 UE 형태를 요청했다. Prefab의 루트 Transform은 Inspector에서 숨기되 자손의 상대 Transform은 편집한다. 기존 LObject.transform·properties.x/y·저장 위치 필드와 사용자 프로젝트를 유지하면서 회전·스케일도 계층에 적용해야 한다.

## 대안과 판단 기준

- SpriteRenderer에 모든 렌더링 종류를 추가하면 사용자 컴포넌트를 만들 때 엔진을 수정해야 한다. RenderComponent가 Draw를 제공하고 SpriteComponent가 구현한다.
- 컴포넌트가 카메라·줌·그래픽 복구까지 담당하면 Scene/Game의 코드가 중복된다. 공용 Renderer가 순회·좌표 적용·그래픽 상태 복구를 처리한다.
- 클릭·외곽선을 Sprite 타입으로 판별하면 사용자 Draw는 편집기에서 선택하기 어렵다. 선택적 GetLocalBounds로 같은 로컬 사각형을 공유한다.
- LObject와 루트 Transform을 두 벌 저장하고 동기화하면 두 Inspector와 코드의 수정 경로가 충돌한다. 실제 값은 루트에만 두고 LObject.transform은 루트로 위임한다.
- 루트를 교체하며 새 컴포넌트의 초기 Transform을 적용하면 인스턴스가 이동한다. 기존 인스턴스 Transform을 새 루트에 복사하고 기존 루트를 자손으로 보존할 때는 로컬 Transform을 단위 변환으로 바꾼다.
- 과거 루트 offset을 다시 배치 위치에 더하면 위치 기준이 두 개로 남는다. 기존 파일을 읽되 루트의 컴포넌트 override Transform은 적용하지 않는다. 배치의 transform을 단일 원본으로 사용한다.

## 결정 및 근거

1. 상속은 LObjectComponent → SceneComponent → RenderComponent → SpriteComponent다. SceneComponent는 x/y, rotationX/Y/rotation, scaleX/Y를 갖는다. RenderComponent는 Draw(context)와 선택적 GetLocalBounds(context)를 제공한다. Component Class 부모 트리와 CLI는 RenderComponent를 지원하며 로더가 두 콜백의 함수 타입을 검사한다.
2. 공용 Renderer는 루트 우선 순회로 RenderComponent의 Draw를 호출한다. 각 호출은 해당 컴포넌트의 월드 좌표·카메라·줌을 적용한 로컬 좌표계에서 실행한다. context:image(reference)는 주입받은 이미지 로더를 사용한다. Draw의 false는 미표시, false/오류 문자열 또는 예외는 기존 호스트 오류 경계로 전달한다. nil 반환은 그리기 수행으로 취급한다. 성공·실패 모두 그래픽 상태를 복원한다.
3. SpriteComponent.Draw는 이미지를 중앙 원점에 그린다. GetLocalBounds는 x/y/width/height를 반환한다. 공용 hit와 outline은 이 범위와 동일한 월드 변환을 사용한다. 범위를 제공하지 않는 사용자 Draw는 표시되지만 이미지 영역 클릭·외곽선은 없고 기존 객체 원점/Hierarchy 선택을 사용한다. 기존 core.sprite_renderer 경로는 공용 Renderer 별칭으로 유지한다.
4. SceneComponent.transform은 위치·회전·스케일의 실제 값이다. 기존 component.properties의 Transform 필드는 같은 값으로 위임한다. properties를 pairs로 순회할 때 Transform 필드는 포함하지 않으므로 Transform 순회는 component.transform을 사용한다. setter는 유한 수·양수 스케일을 검사하고 각도를 0 이상 360 미만으로 정규화한다.
5. LObject.transform은 rootComponent.transform을 반환하고 대입도 루트 setter에 위임한다. 루트는 부모 없는 월드 Transform, 자손은 가장 가까운 SceneComponent 부모에 대한 상대 Transform이다. 비공간 조상은 건너뛰고 부모와 자손의 2D affine 행렬을 합성한다. 각 로컬 변환은 기존 스케일 → X/Y/Z 회전 → XY 직교 투영을 사용한다. 실제 3D 깊이·원근은 추가하지 않는다.
6. 루트 교체는 인스턴스 Transform을 유지한다. 새 루트의 생성 override Transform은 배치 위치에 추가하지 않는다. 기존 사용자 루트를 새 루트의 자식으로 보존할 경우 기존 루트 로컬 Transform은 단위 변환이 된다. 실패 복구는 부착 관계와 기존 Transform도 복원한다.
7. Prefab 스키마와 Inspector에서는 루트 Transform을 제외한다. 루트 이미지·일반 프로퍼티는 편집 가능하다. 자손의 Transform은 Prefab·인스턴스 모두 편집한다. 인스턴스 객체 노드의 Actor Transform과 루트 노드의 Transform은 같은 배치 데이터를 편집한다. 루트 필드의 변경은 레벨 transform에 저장하고 componentOverrides에는 중복 저장하지 않으며 기존 Undo/Redo를 사용한다.
8. 레벨·Prefab 버전은 유지한다. 저장된 루트 Transform componentOverride는 이전 로컬 offset 계약으로 읽되 적용하지 않는다. 루트의 새 위치는 레벨 transform 또는 SpawnLObject transform으로 지정한다. 자손 컴포넌트 override는 기존 이름별 계약으로 유지한다. 기존 파일은 자동 덮어쓰지 않는다.


## 관계

```text
상속: LObjectComponent
      └─ SceneComponent
         └─ RenderComponent
            └─ SpriteComponent

소유: LObject → rootComponent → 자손 Components
위임: LObject.transform → rootComponent.transform (단일 값)
의존: Scene/Game View → Renderer → RenderComponent.Draw / GetLocalBounds
주입: Renderer context:image → 호스트 이미지 로더
```

## 예상 결과

- 긍정: 사용자 렌더링 컴포넌트가 엔진 수정 없이 동작하며 Scene/Game/Export가 같은 Draw를 사용한다. 인스턴스 위치와 루트 위치의 편집·기즈모·저장이 일치한다. 자손의 회전·스케일도 렌더링·클릭·외곽선에 동일하게 적용한다.
- 부정: 과거 루트 로컬 offset으로 이동시킨 프로젝트는 배치 transform 또는 자손 Transform으로 값을 옮겨야 한다. 사용자 Draw는 에디터에서도 실행되므로 부작용을 피해야 한다. 사용자 렌더링의 선택 범위는 직접 선언해야 한다.
- 중립: 컴포넌트 구성·부착은 코드에서 유지한다. 실제 3D 변환·깊이 정렬·새 렌더링 백엔드·렌더 순서 변경 UI는 추가하지 않는다.
