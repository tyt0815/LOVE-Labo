# LÖVE Labo 로컬 핵심 안내

공식 문서: https://tyt0815.github.io/LOVE-Labo/ — 개발 버전의 실제 CLI help와 함께 확인한다.

## 오브젝트와 스크립트

LObject는 Transform과 부모·자손을 가진다. 스크립트는 오브젝트를 상속하지 않고 독립 인스턴스로 부착된다.
Lua 파일은 properties와 선택적인 load(world), update(dt), draw(context), drawScreen(context)를 가진 테이블을 반환한다.
Project → Inspector 메뉴·레벨 에셋 Inspector·Object에서 같은 Script를 부착한다. update는 Project → Level → Object 순서로 내장 호출한다.
Project Script는 Play 동안 유지하고 Level Script는 World마다 새로 생성한다. self:getProject(), self:getWorld()와 각 호스트의 getScriptByName/Id/Class, getScriptsByClass를 사용한다.
Object draw는 기존 Transform·카메라·Canvas를 적용한다. Project·Level draw는 월드 좌표이며 drawScreen은 모든 범위에서 게임 영역 왼쪽 위 (0, 0) 기준 픽셀 좌표다.
편집 화면 표시는 drawEditor(context)에서 도형을 계산한다. 이때 load/update는 실행되지 않는다.
world.debug:log/screenLog/point/line/circle/rect/polygon은 Editor Play에서만 표시되고 배포에서는 no-op이다.
self는 스크립트이며 self.owner.transform, self.owner:getScriptByName(name), getScriptById(id), getScriptByClass(class), getScriptsByClass(class)로 오브젝트·다른 스크립트를 사용한다.
일반 Lua 필드는 Inspector에 노출되지 않는다. properties에 number/string/boolean/object/script/image/prefab를 선언한다.
group으로 프로퍼티를 묶는다. object 참조는 authoringId, script 참조는 {authoringId=ID, script="부착ID"}로 저장한다.

require("Engine")은 LObject, Script와 공간·바운드 API를 제공한다. Camera, View, Sprite, Pointer, RectBounds, Canvas, Text는 LaboEssentials를 활성화한 경우에만 제공된다. 새 부착에는 RectBounds를 사용하며 기존 Rect 별칭은 읽기 호환성을 유지한다.
사용자·플러그인 부모 상속은 extends에 에셋 UUID를 지정한다. 브라우저 우클릭 Copy ID는 파일 ID이고 Inspector Copy ID는 부착 ID다. 기반 Script는 extends를 생략한다. 기존 공개 이름은 읽기 호환이다. 다른 폴더의 동명 스크립트는 허용한다.
편의 스크립트는 Script를 직접 상속하며 별도의 컴포넌트 계층·루트 컴포넌트는 없다.
Camera의 viewWidth/viewHeight는 월드 가시 범위이며 zoom=2이면 범위가 절반이다. require("Engine.Rendering")의 createView(world, {camera, target})로 출력을 등록한다. Rendering.screen은 실행 환경의 화면, createTarget은 텍스처 출력이다. View가 없으면 게임 장면을 그리지 않는다.
Canvas는 화면 중심을 원점으로 하는 픽셀 좌표계를 시작한다. Pointer의 boundsSource는 같은 오브젝트의 스크립트 ID다.
onPointerDown/up/move에서 true를 반환하면 입력을 소비한다. 직접 hitTest/getLocalBounds를 구현할 수도 있다.
world:spawnLObject(prefab, transform, overrides)로 Prefab 계층을 생성하고 world:removeLObject(object)로 자손까지 제거한다.
world:openLevel(reference)은 프레임 경계에서 레벨을 전환한다. 새 레벨은 Camera를 자동 생성하지 않는다. LaboEssentials의 View 스크립트에 cameraSource를 지정하거나 코드로 View를 등록한다.

audio={type="audio", default=false}로 WAV·OGG·MP3·FLAC 참조를 노출한다. world:getAssetData(id)는 직접 소유할 LÖVE FileData를 반환한다. love.audio.newSource(data,"static"/"stream")로 재생한다. 객체 제거·Play 종료·전환·오류 시 Script:unload()가 초기화한 각 부착에 한 번 호출되며 self.owner를 사용할 수 있다. enabled=false도 정리한다. 자원은 unload에서 stop/release하며 self.source는 메타데이터이므로 self.audioSource처럼 별도 필드를 쓴다.

## 데이터와 CLI

모든 에셋은 Assets 아래에 있으며 assets.json의 ID로 참조한다. Docs는 게임 Export에 포함하지 않는다.
Prefab 형식은 4, 레벨 형식은 3이다. 이전 Sources는 Assets/Scripts로 이동하지만 옛 컴포넌트 코드·Prefab은 수동 전환해야 한다.
부착 Script는 keypressed/keyreleased, textinput/textedited, 마우스·터치·조이스틱·게임패드, focus/mousefocus/visible/resize 콜백을 LÖVE 이름·인자로 구현한다. 전역 love 콜백을 덮어쓰지 않는다. 반환값 소비는 없고 enabled=false는 전달하지 않는다. 마우스·터치는 실제 게임 화면 왼쪽 위 기준 픽셀 좌표다. Editor에서는 Game View 포커스·팝업·Pause·에디터 단축키 경계를 따른다.
스크립트는 별도 선언 없이 상속하는 공통 enabled로 실행을 켜고 끈다. Inspector에서는 헤더의 돋보기 왼쪽 토글로 편집한다. 공통 updateOrder·drawOrder는 기본 0이며 작은 값부터 실행한다. Inspector의 Script 그룹은 맨 위에 표시하고 실제 update·draw/drawScreen 콜백이 있는 순서만 노출한다. 프로퍼티 레이블은 Draw order처럼 표시하고 코드·CLI·저장 키는 drawOrder 등 원래 이름을 사용한다. 런타임 addScript/removeScript는 제공하지 않으며 부착·제거는 편집 작업이다.
Prefab의 scripts는 {id,source,name} 목록, overrides.scripts는 부착 ID별 프로퍼티 재정의다.

Labo-cli.exe --cli help
Labo-cli.exe --cli script create --project <경로> --name Movement
Labo-cli.exe --cli prefab script add --project <경로> --prefab Assets/PF_Player.prefab --source Assets/Movement.lua --script movement
Labo-cli.exe --cli prefab script move --project <경로> --prefab Assets/PF_Player.prefab --script movement --index 1
Labo-cli.exe --cli level simulate --project <경로> --frames 60 --dt 0.0166667
Labo-cli.exe --cli level pointer --project <경로> --space screen --x 640 --y 360
Labo-cli.exe --cli level view --project <경로>
Labo-cli.exe --cli level render --project <경로> --output <PNG 경로>
Labo-cli.exe --cli script open --project <경로> --script <소스 ID 또는 경로> --dry-run

기본 레벨이 없으면 --level을 지정한다. 복잡한 값은 --request <UTF-8 JSON 파일>을 사용한다.
level.events는 events 또는 --events-json 배열의 {name,args}를 같은 Script 이벤트 경로로 전달하고 상태를 반환한다. 문서를 저장하지 않고 draw·update·Pointer 판정은 실행하지 않는다.
level.simulate는 초기화·업데이트 결과를 반환하며 파일을 수정하거나 draw를 실행하지 않는다. --debug로 로그·도형 기록도 확인한다.
