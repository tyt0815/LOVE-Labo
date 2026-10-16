# 0078. 레벨 전용 카메라 설정 대신 View와 RenderTarget을 등록한다

- 상태: 채택·구현
- 날짜: 2026-10-16
- 부분 대체: [0047](0047-level-main-camera-and-default-camera.md)의 레벨 전용 설정·자동 생성, [0049](0049-camera-selection-without-enabled.md)의 단일 카메라 선택
- 확장: [0068](0068-camera-letterbox-for-world-and-screen-ui.md)의 비율·입력 계약, [0074](0074-scoped-scripts-and-screen-drawing.md)의 출력별 draw 실행

## 배경과 제약

레벨의 내장 Main Camera 필드는 플러그인으로 제공하는 카메라를 편집 데이터에서 특별 취급한다. 메인 화면과 미니맵에 같은 World를 서로 다른 카메라로 출력하려면 카메라와 출력 대상도 분리해야 한다. 새 프로젝트에는 활성 플러그인이 없으며 기존 Script 부착·참조·Export 계약을 재사용한다.

## 대안과 판단 기준

- 기존 Main Camera와 보조 카메라 API를 병행하면 메인·보조 출력의 구성 방식이 다르다.
- draw context로 전역 카메라를 변경하거나 Script.getView를 추가하면 특정 출력과 일반 스크립트가 결합한다.
- 새 render 콜백은 매 프레임 같은 구성을 반복 작성해야 한다.
- 초기화 시 View를 등록하면 기존 load/update/draw 생명주기를 유지하고 일반 참조 프로퍼티로 구성할 수 있다.

## 결정과 근거

공개 API는 require("Engine.Rendering") 및 require("Engine").Rendering으로 제공한다. Camera는 투영·변환, RenderTarget은 픽셀 출력 자원, RenderView는 World·Camera·타깃·영역·필터·순서를 연결한다. 새 render 콜백이나 Script.getView는 추가하지 않는다. World는 View·텍스처 타깃을 소유하며 종료 시 해제한다. owner 스크립트를 지정하면 비활성·제거된 소유자의 출력은 중단된다. 실행 중 명시적인 release도 가능하다.

createView는 즉시 등록하며 활성 View를 order 오름차순, 동률이면 등록 순서로 매 프레임 렌더링한다. 렌더 타깃 생산 View를 소비 View보다 먼저 배치하는 것은 구성 스크립트의 책임이다. 자동 의존성 추론은 하지 않는다. Rendering.screen은 실행 환경별 화면을 지정하는 토큰이며 전역 화면 상태를 저장하지 않는다. 텍스처 타깃은 처음 사용할 때 GPU 자원을 만들어 창 없는 CLI 초기화를 허용한다.

화면 출력은 직접 표시되고 텍스처 출력은 별도 그리기로 합성한다. clearColor=false는 기존 내용을 보존하며 기본은 불투명 검정이다. viewport는 타깃 내 픽셀 사각 영역이고 바깥으로 넘는 부분은 잘린다. 카메라 비율은 영역 안에서 레터박스로 유지한다. 카메라 nil은 명시적인 원점·배율 1 출력이다. 등록된 View가 없으면 게임 장면을 그리지 않으며 편집·에셋 미리보기에는 별도의 표시 경로를 유지한다.

includeWorld/includeScreen과 filter(script)로 출력 대상을 제한한다. drawScreen·Canvas는 화면 공간으로 분류하며 draw는 View마다 호출한다. update·일반 이벤트는 World당 한 번이다. context에는 해당 View·Camera·RenderTarget을 전달한다. 타깃 쓰기 중 getTexture로 자신을 읽는 것은 오류이며 그래픽 상태를 복원한다.

화면 View의 Pointer 입력은 표시 역순으로 처리하고 각 View의 카메라·필터·영역을 사용한다. 텍스처 View는 직접 화면 입력 대상이 아니다. View마다 캡처를 분리하며 영역 밖 release도 같은 출력에 전달한다. 소유자 비활성·제거, 카메라 제거 등으로 View가 비활성이 되면 캡처를 취소하며 재활성화해도 복원하지 않는다. 일반 LÖVE 화면 이벤트·resize와 디버그 오버레이는 대표 화면 View의 좌표계를 사용한다. 텍스처를 표시하는 UI에 입력을 재투영하는 기능은 별도 명시적 구현이 필요하다.

LaboEssentials의 View 스크립트는 일반 cameraSource 참조 프로퍼티로 화면 View를 등록한다. 새 레벨은 Camera를 자동 생성하지 않고 전용 Main Camera 필드를 표시하지 않는다. 기존 mainCamera 데이터는 왕복 저장하고, 초기화 후 명시적으로 등록된 활성 View가 없을 때만 호환 View로 해석한다. 호환 View는 실행 중에도 World의 자동 대체 선택과 동기화하며 카메라가 모두 사라지면 원점·배율 1을 사용한다. 일반 View는 제거된 카메라의 출력만 중단하고, 제공 View 스크립트는 참조가 변경될 때만 setCamera로 검증한다. getActiveCamera/setActiveCamera와 level.set-camera는 과거 코드·데이터를 위한 호환 API로 남기며 새 코드는 View를 사용한다. 예제의 welcome은 공통 Level 부착 프로퍼티로 옮긴다.

```text
World ──소유──> RenderView·RenderTarget
RenderView ──참조──> Camera Script·RenderTarget
RenderPipeline ──의존──> Viewport·Renderer
LaboEssentials.View ──의존──> Rendering 공개 API
```

## 예상 결과

- 긍정: 레벨 전용 기능 없이 메인 화면·미니맵을 같은 API로 구성하고 CLI·Play·Export가 공유한다.
- 부정: 새 게임은 출력 구성을 명시해야 하며 타깃 생산·소비 순서도 관리해야 한다.
- 중립: 카메라 줌은 가시 범위를 나누며 출력 해상도를 바꾸지 않는다. 같은 타깃의 이전 프레임을 읽는 효과는 별도 타깃 두 개로 구현해야 한다.
