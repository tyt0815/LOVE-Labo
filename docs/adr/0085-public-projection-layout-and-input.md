# 0085. 공개 투영·배치·입력 API로 카메라와 UI를 구성한다

- 상태: 채택·구현
- 날짜: 2026-10-16
- 부분 대체: [0047](0047-level-main-camera-and-default-camera.md), [0049](0049-camera-selection-without-enabled.md), [0046](0046-camera-screen-canvas-and-component-order.md), [0068](0068-camera-letterbox-for-world-and-screen-ui.md), [0074](0074-scoped-scripts-and-screen-drawing.md), [0078](0078-registered-views-and-render-targets.md), [0084](0084-common-script-callback-order.md)
- 유지: 단일 World·LObject 계층, 제공 편의 기능의 플러그인 배치, 명시적인 View 등록, 공통 enabled·updateOrder·drawOrder

## 배경과 제약

Core가 camera/canvas/pointer 표식과 fillParent·inputPriority 같은 제공 스크립트 전용 프로퍼티를 읽어 의미를 부여하면 플러그인 없이 동등한 기능을 만들기 어렵다. 별도 UI World나 필수 UI View 대신 Camera 아래 HUD Prefab을 배치하고 이를 통째로 교체하는 구성을 제공한다. 9방향 Anchor·Pivot과 줌에 무관한 UI 크기·간격, 편집·Play·CLI·Export의 일관성이 필요하다.

## 대안과 판단 기준

- 별도 UI 계층·전용 렌더링 패스는 독립적인 좌표·순서·입력 규칙과 에셋 구성을 추가한다.
- update에서 UI Transform을 덮어쓰면 저장 오프셋을 잃고 실행 순서에 따라 한 프레임 늦어진다.
- drawScreen을 별도 자동 콜백으로 유지하면 그리기 API와 정렬 단계가 둘로 나뉜다.
- 범용 등록 API와 지연 계산을 선택한다. 사용자·제공 스크립트가 같은 기능을 조합할 수 있고 기존 계층·Prefab·렌더러를 공유한다.

## 결정 및 근거

View는 camera 대신 projection 데이터 또는 무인자 제공 함수를 받는다. 데이터는 width·height·transform이며 transform은 역변환 가능한 2D affine 변환이다. 제공 함수가 nil을 반환하면 출력과 입력 캡처를 중단한다. projection 자체를 생략하면 원점·배율 1 출력이다. Core는 특정 스크립트 타입·이름·메서드를 요구하지 않는다. Rendering.normalizeProjection은 투영 검증·복사·생략된 변환의 원점 기본값을 공용으로 제공하며 View와 Canvas가 함께 사용한다. setProjection으로 교체하고 filter(script)로 출력·입력 대상을 명시한다. includeWorld/includeScreen과 Camera 자동 선택·setCamera·World.getActiveCamera/setActiveCamera는 제거한다.

Script.configure()는 인스턴스 생성·부착 때 한 번 실행하여 순수 배치·영역 제공자를 등록한다. 게임 load/update와 별개이며 편집·미리보기에도 실행된다. 이 시점에는 다른 부착·부모·참조 해석이 끝나지 않을 수 있으므로 조회는 제공 함수 안에서 지연한다. 게임 동작·입력·GPU 자원 등록은 load에서 수행한다. 미리보기는 load/update를 실행하지 않고 참조·부모를 연결해 같은 제공 함수를 평가한다.

Transform.bindLocal(object,{owner,resolve,unresolve})는 저장된 Transform을 읽어 유효 로컬 변환을 계산한다. object.transform에는 저작 오프셋을 보존한다. 월드 변환은 부모의 유효 변환을 합성한다. unresolve는 에디터 위치 조작을 저작 오프셋으로 역변환한다. Transform.relative·affine은 사용자 코드에도 제공한다. 중복 등록과 재귀 계산은 오류로 검출하고 계산 실패 후에도 다음 조회를 시도할 수 있다. 저작 배치·참조 그래프는 project.AuthoringLayout으로 분리하며 SpriteAssets와 CLI가 같은 평가기를 사용한다. CLI의 부모 변경·계층 순서 변경도 유효 월드 위치를 보존하고 새 부모 기준 오프셋으로 역산한다. 평가기 종료 시 configure 바인딩을 정리한다.

Bounds.bind(owner,provider,{primary=true})는 스크립트 영역과 선택적인 객체 대표 사각형을 등록한다. Bounds.of·parent로 객체·가장 가까운 부모 영역을 조회한다. fillParent나 다른 스크립트의 메서드를 자동 탐색하는 로직은 Core에서 제거한다. 기존 getLocalBounds는 일반 스크립트의 선택적인 영역 제공 메서드로 유지한다. 제공 스크립트의 영역 공유·늘리기는 플러그인 코드가 결정한다.

Input.registerRegion(world,{owner,hitTest,onDown,onUp,onMove,order,priority,block,filterSource})는 입력 영역을 등록한다. order·priority·block은 값 또는 제공 함수이며 기본 order는 owner.drawOrder다. true 반환은 입력 소비·누름 캡처를 의미한다. 캡처는 영역·View별로 구분하고 영역 밖 move/up도 전달한다. Core는 pointer 표식·포인터 콜백 자동 탐색·플러그인 전용 프로퍼티를 읽지 않는다. Pointer 플러그인이 콜백·boundsSource·inputPriority를 이 API에 연결한다.

바인딩·입력 영역은 Script 소유자와 수명을 공유한다. enabled=false는 등록 효과·입력을 중단하고 재활성화 시 재개한다. 제거·종료는 정리를 자동 수행하며 명시적인 release도 가능하다. 미리보기 폐기에서도 바인딩을 정리한다. 스크립트 비활성화가 자손 스크립트의 enabled를 변경하지는 않는다.

모든 그리기는 draw 하나로 처리하며 공통 drawOrder로 정렬한다. 화면 픽셀 좌표가 필요하면 Rendering.withScreen(context,fn) 또는 context:withScreen(fn)을 사용한다. 카메라·오브젝트 변환을 잠시 해제하고 출력 영역 왼쪽 위를 원점으로 사용하며 오류 시에도 그래픽 상태를 복구한다. 별도 drawScreen 콜백은 제거하고 선언 시 변환 안내 오류를 낸다. 게임 화면이 없는 에셋·Scene 미리보기에서는 withScreen 구간을 실행하지 않는다.

LaboEssentials.Camera는 일반 getProjection 메서드, View는 이를 전달하는 제공 함수·HUD 필터를 구현한다. Canvas는 부모의 투영 제공 스크립트 또는 명시적 cameraSource로 카메라를 찾는 일반 스크립트다. matchCamera=true에서 기준 사각형이 투영 영역에 맞도록 균일 배율을 계산하고 다른 종횡비에서는 논리 영역을 확장한다. 카메라 줌은 Canvas 배율이 상쇄하고 창 크기에 따른 출력 확대는 기준 해상도 정책을 따른다. RectLayout은 부모 사각형의 9방향 anchor에서 object.transform.x/y를 오프셋으로 적용한다. pivot은 자신의 영역·회전·스케일 원점이다. Anchor·Pivot은 공통 문자열 프로퍼티 options 목록으로 Inspector에서 선택한다.

과거 mainCamera·matchViewport·View 좌표계 플래그는 project.migrate-rendering CLI로 저장 데이터를 한 번 변환한다. --dry-run은 변경 목록만 반환한다. 변환 후 Runtime에는 호환 자동 선택을 두지 않으며 미변환 mainCamera에는 명령 안내 오류를 낸다. 사용자 Lua의 drawScreen·카메라 API 호출은 공개 API로 직접 전환한다. project.examples-ui는 제공 플러그인 예제와 API 전용 예제를 만들고 --public-only는 플러그인을 활성화하지 않는다.

```text
World ──소유──> View·RenderTarget·Input region
Script ──수명 관리──> Transform·Bounds 바인딩·Input region
LObject ──합성──> 저장 Transform → 제공자 → 부모의 유효 Transform
RenderView ──의존──> 투영 데이터/제공 함수 (Camera 타입 참조 없음)
Renderer·PointerInput·에디터 ──의존──> 같은 Transform·Bounds
LaboEssentials 및 사용자 스크립트 ──의존──> Engine 공개 API
Camera Object ──부모/자손──> HUD Prefab(Canvas) ──부모/자손──> RectLayout·Sprite/Text/입력
```

## 예상 결과

- 긍정: 플러그인이 없어도 카메라·HUD·입력을 재구현하고 기존 World·Prefab을 재사용한다. 편집 중에도 저장값을 덮어쓰지 않고 배치를 확인한다.
- 부정: 기존 사용자 스크립트의 API 전환이 필요하며, 배치 제공자는 순환 의존성과 잘못된 사각형을 만들지 않도록 작성해야 한다.
- 중립: 레벨·Prefab의 파일 버전은 유지한다. 고급 앵커 스트레치·자동 줄 배치·UI 전용 World·자동 렌더 타깃 의존성 추론은 추가하지 않는다.

Bounds.parent는 사각형의 로컬 x·y·폭·높이와 그 영역을 제공한 조상 오브젝트를 다섯 번째 값으로 반환한다. 중간에 일반 그룹 오브젝트가 있으면 RectLayout은 앵커 점을 실제 부모 좌표로 변환한다.
