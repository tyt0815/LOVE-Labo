local Instructions = {version = require("Version").getInfo().displayVersion, documentationUrl = "https://tyt0815.github.io/LOVE-Labo/"}
function Instructions.files()
    return {
        {name = "AGENTS.md", text = [[# LÖVE Labo 프로젝트 AI 작업 지침

- 실행 계약: LÖVE 11.5 + LuaJIT / Lua 5.1, attached-script 개발 버전.
- 작업 전 https://tyt0815.github.io/LOVE-Labo/guide/ai/ 와 관련 API 문서를 확인한다.
- 웹 문서와 설치 버전이 다르면 Docs/EngineGuide.md, CLI help, 실제 제공 API를 기준으로 한다.
- 게임 동작 코드는 Assets, 게임 시작 설정은 프로젝트 루트 conf.lua, 빌드는 Tools/Build.lua에서 수정한다. 엔진 코어·DLL·배포 파일은 직접 수정하지 않는다.
- 에셋 생성·이동·삭제·배치는 Labo-cli.exe 명령을 우선 사용하고 assets.json의 ID를 보존한다.
- GUI에서 연 문서를 저장한 뒤 CLI로 수정한다. CLI 변경은 GUI Undo에 포함되지 않는다.
- LObject는 Transform과 자손 계층을 소유한다. 같은 Script를 Project·Level·Object에 여러 개 부착하며 self.owner는 해당 등록 대상이다. getProject/getWorld로 실행 범위에 접근한다.
- Prefab에서 스크립트를 추가·제거·정렬한다. 배치 인스턴스에도 로컬 스크립트를 추가한다. 상속한 오브젝트·스크립트의 구조는 고정하고 값만 재정의한다.
- 설정 간 의존성이 있는 프로퍼티는 enabledIf를 적극 활용해 Inspector에서 유효한 조합만 편집하도록 한다. 예: speed = {type = "number", default = 100, enabledIf = {useMovement = true}}. 같은 스크립트 부착의 boolean·number·string 프로퍼티와 비교하며 여러 조건은 모두 일치해야 한다. 비활성 필드는 값을 보존한다. Inspector 편집만 제한하므로 게임 실행 조건은 Lua 로직에서 별도로 처리한다.
- 클래스·파일 이름은 PascalCase, 변수·함수는 camelCase, 상수는 UPPER_SNAKE_CASE, 들여쓰기는 공백 4칸이다.
]]},
        {name = "Docs/EngineGuide.md", text = "# LÖVE Labo 로컬 핵심 안내\n\n생성 엔진: LÖVE Labo " .. Instructions.version .. "\n" .. [[

공식 문서: https://tyt0815.github.io/LOVE-Labo/ — 개발 버전의 실제 CLI help와 함께 확인한다.

## 오브젝트와 스크립트

LObject는 Transform과 부모·자손을 가진다. 스크립트는 오브젝트를 상속하지 않고 독립 인스턴스로 부착된다.
Lua 파일은 properties와 선택적인 configure(), load(world), update(dt), draw(context)를 가진 테이블을 반환한다.
Project → Inspector 메뉴·레벨 에셋 Inspector·Object에서 같은 Script를 부착한다. update는 updateOrder가 작은 순서로 내장 호출하고 동률은 Project → Level → Object 순서다.
Project Script는 Play 동안 유지하고 Level Script는 World마다 새로 생성한다. self:getProject(), self:getWorld()와 각 호스트의 getScriptByName/Id/Class, getScriptsByClass를 사용한다.
Object draw는 유효 Transform과 View 투영을 적용한다. Project·Level draw는 월드 원점이다. 화면 픽셀 출력은 draw 안에서 context:withScreen(fn)을 호출한다. drawScreen 콜백은 제거되었다.
편집 화면 표시는 drawEditor(context)에서 도형을 계산한다. 이때 load/update는 실행되지 않는다.
world.debug:log/screenLog/point/line/circle/rect/polygon은 Editor Play에서만 표시되고 배포에서는 no-op이다.
self는 스크립트이며 self.owner.transform, self.owner:getScriptByName(name), getScriptById(id), getScriptByClass(class), getScriptsByClass(class)로 오브젝트·다른 스크립트를 사용한다.
일반 Lua 필드는 Inspector에 노출되지 않는다. properties에 number/string/boolean/object/script/image/prefab를 선언한다.
group으로 프로퍼티를 묶는다. object 참조는 authoringId, script 참조는 {authoringId=ID, script="부착ID"}로 저장한다.
설정 간 의존성이 있으면 enabledIf = {useMovement = true}처럼 같은 부착의 다른 boolean·number·string 프로퍼티 값과 비교해 Inspector 편집을 제한한다. 모든 조건이 일치할 때 활성화되며 비활성 상태에서도 값은 보존한다. 런타임 동작과 CLI 할당은 제한하지 않으므로 실행 조건은 Lua에서 구현한다.

require("Engine")은 LObject, Script와 공간·바운드 API를 제공한다. Camera, View, Sprite, Pointer, RectBounds, Canvas, RectLayout, Text는 LaboEssentials를 활성화한 경우에만 제공된다. 새 부착에는 RectBounds를 사용하며 기존 Rect 별칭은 읽기 호환성을 유지한다.
사용자·플러그인 부모 상속은 extends에 에셋 UUID를 지정한다. 브라우저 우클릭 Copy ID는 파일 ID이고 Inspector Copy ID는 부착 ID다. 기반 Script는 extends를 생략한다. 기존 공개 이름은 읽기 호환이다. 다른 폴더의 동명 스크립트는 허용한다.
편의 스크립트는 Script를 직접 상속하며 별도의 컴포넌트 계층·루트 컴포넌트는 없다.
Camera의 viewWidth/viewHeight는 월드 가시 범위이며 zoom=2이면 범위가 절반이다. require("Engine.Rendering")의 createView(world, {projection, target})로 출력을 등록한다. Rendering.screen은 실행 환경의 화면, createTarget은 텍스처 출력이다. View가 없으면 게임 장면을 그리지 않는다.
Canvas는 Camera 아래에서 기준 영역과 일반 Transform 배율을 계산해 줌을 상쇄한다. RectLayout의 anchor·pivot은 9방향 선택이고 Transform x/y는 앵커 오프셋이다. Pointer의 boundsSource는 같은 오브젝트의 스크립트 ID다.
Pointer 편의 스크립트의 onPointerDown/up/move에서 true를 반환하면 입력을 소비한다. Core는 이 콜백을 자동 검색하지 않는다. 직접 Input.registerRegion(world,{owner,hitTest,onDown,onUp,onMove})로 등록할 수 있다.
world:spawnLObject(prefab, transform, overrides)로 Prefab 계층을 생성하고 world:removeLObject(object)로 자손까지 제거한다.
world:openLevel(reference)은 프레임 경계에서 레벨을 전환한다. 새 레벨은 Camera를 자동 생성하지 않는다. LaboEssentials의 View 스크립트에 cameraSource를 지정하거나 코드로 View를 등록한다.

Rendering.normalizeProjection(data)는 width·height를 검증하고 생략된 transform을 원점 변환으로 채운 복사본을 반환한다. nil은 비활성 투영으로 유지한다. View와 Canvas는 같은 규칙을 사용한다.

world:openLevel(reference,{carry={object}})는 선택 객체·자손·Script를 같은 인스턴스로 옮긴다. 기존 load/unload는 재호출하지 않고 worldChanged(previousWorld,nextWorld)를 통지한다. 실패 복구 시에는 반대로 통지한다. 캐시한 World를 여기서 갱신한다. owner가 이동하는 View·Input region·RenderTarget도 함께 옮기며 렌더 타깃은 createTarget(world,{owner=self,width=256,height=256})로 소유자를 지정한다. 포인터 캡처는 취소한다. 임시 이동 중 구조 변경·기존 등록 release는 금지한다. 사용자 Lua 필드·파일 부작용까지 복구하지 않는다.
Project Script의 self.owner.id·saveIdentity는 프로젝트의 안정적인 UUID와 저장 폴더 이름이다. 게임 저장은 일반 테이블 직렬화와 love.filesystem.write/read로 구성한다. 예제는 saves/<saveIdentity>/slot1.json을 사용하며 Editor Play와 Export의 물리 저장 위치는 다르다. 전역 setIdentity로 에디터 설정 저장 위치를 바꾸지 않는다.

audio={type="audio", default=false}로 WAV·OGG·MP3·FLAC 참조를 노출한다. world:getAssetData(id)는 직접 소유할 LÖVE FileData를 반환한다. love.audio.newSource(data,"static"/"stream")로 재생한다. 객체 제거·Play 종료·전환·오류 시 Script:unload()가 초기화한 각 부착에 한 번 호출되며 self.owner를 사용할 수 있다. enabled=false도 정리한다. 자원은 unload에서 stop/release하며 self.source는 메타데이터이므로 self.audioSource처럼 별도 필드를 쓴다.

configure에서 Transform.bindLocal(object,{owner,resolve,unresolve})·Bounds.bind(script,provider,{primary=true})를 등록한다. 제공 함수는 부모·참조·프로퍼티를 지연 조회하고 저장 Transform을 덮어쓰지 않는다. Bounds.of/parent는 객체·부모 사각형 조회다. 바인딩·입력은 Script 종료 시 자동 정리한다. configure는 편집·Preview에도 실행하고 게임 동작·입력·자원은 load에서 시작한다. 문자열 프로퍼티 options={"left","right"}는 공통 선택 목록이다.


## 게임 시작 설정

프로젝트 루트 conf.lua에 love.conf(config)를 정의해 게임의 창 제목·크기·VSync·전체화면·아이콘 등 LÖVE 초기화 설정을 변경한다. Project Inspector → Game startup → Open conf.lua로 코드 편집기에서 연다. Export 때 누락된 기본 파일만 생성하고 기존 설정은 덮어쓰지 않는다. 설정 코드는 Export 중 실행하지 않으며 게임 프로세스의 모듈·창 생성 전에 실행한다. Editor Play와 게임 CLI에는 적용하지 않는다. config.identity는 프로젝트 UUID로 관리하므로 변경하지 않는다. config.window.icon은 Assets 경로 또는 에셋 ID를 사용할 수 있다.

## 배포 빌드와 게임 전용 CLI

Tools/Build.lua가 Export 진입점이다. 별도 빌드 도구 설치 없이 Lua로 수정한다. builder:packageGame(), packageCli("Game-cli.exe",{entry="Assets/Tools/GameCli.lua"}), copy("Docs/ContentGuide.md","README.md"), log(message)를 사용한다. 기본 Export는 Windows Game.exe와 DLL·라이선스를 만들며 builder.platform은 "windows"다. packageGame("Game.love")로 기존 아카이브 출력도 유지한다. Project → Open Build Script로 현재 코드 편집기에서 연다.
게임 CLI 모듈은 {summary,commands={명령={summary,parameters={인자={type,required,default,description}},run=function(context,args) ... end}}} 테이블을 반환한다. help/schema와 JSON 요청·응답, 성공 0/실패 1 종료 코드를 제공한다. 게임의 World·창·오디오는 생성하지 않는다. context.workspace는 --workspace 절대 경로를 준 경우에만 제공하며 readJson/writeJson/revision/withLock을 게임 내부 편집기와 공유한다. GUI는 외부 파일을 명시적으로 다시 읽는다. 동기화·Undo는 자동 통합하지 않는다. 문서: https://tyt0815.github.io/LOVE-Labo/guide/game-cli/

## 데이터와 CLI

모든 에셋은 Assets 아래에 있으며 assets.json의 ID로 참조한다. Docs는 자동으로 패키지에 포함하지 않으며 Tools/Build.lua의 builder:copy로 필요한 문서를 배포 폴더에 동봉할 수 있다.
Prefab 형식은 4, 레벨 형식은 3이다. 이전 Sources는 Assets/Scripts로 이동하지만 옛 컴포넌트 코드·Prefab은 수동 전환해야 한다.
부착 Script는 keypressed/keyreleased, textinput/textedited, 마우스·터치·조이스틱·게임패드, focus/mousefocus/visible/resize 콜백을 LÖVE 이름·인자로 구현한다. 전역 love 콜백을 덮어쓰지 않는다. 반환값 소비는 없고 enabled=false는 전달하지 않는다. 마우스·터치는 실제 게임 화면 왼쪽 위 기준 픽셀 좌표다. Editor에서는 Game View 포커스·팝업·Pause·에디터 단축키 경계를 따른다.
스크립트는 별도 선언 없이 상속하는 공통 enabled로 실행을 켜고 끈다. Inspector에서는 헤더의 돋보기 왼쪽 토글로 편집한다. 공통 updateOrder·drawOrder는 기본 0이며 작은 값부터 실행한다. Inspector의 Script 그룹은 맨 위에 표시하고 실제 update·draw 콜백이 있는 순서만 노출한다. 프로퍼티 레이블은 Draw order처럼 표시하고 코드·CLI·저장 키는 drawOrder 등 원래 이름을 사용한다. 런타임 addScript/removeScript는 제공하지 않으며 부착·제거는 편집 작업이다.
Prefab의 scripts는 {id,source,name} 목록, overrides.scripts는 부착 ID별 프로퍼티 재정의다.

Labo-cli.exe --cli help
Labo-cli.exe --cli script create --project <경로> --name Movement
Labo-cli.exe --cli prefab script add --project <경로> --prefab Assets/PF_Player.prefab --source Assets/Movement.lua --script movement
Labo-cli.exe --cli prefab script move --project <경로> --prefab Assets/PF_Player.prefab --script movement --index 1
Labo-cli.exe --cli level simulate --project <경로> --frames 60 --dt 0.0166667
Labo-cli.exe --cli level pointer --project <경로> --space screen --x 640 --y 360
Labo-cli.exe --cli project examples-session --project <경로>
Labo-cli.exe --cli project examples-ui --project <경로> --public-only
Labo-cli.exe --cli project migrate-rendering --project <경로> --dry-run
Labo-cli.exe --cli level view --project <경로>
Labo-cli.exe --cli level render --project <경로> --output <PNG 경로>
Labo-cli.exe --cli config open --project <경로> --dry-run
Labo-cli.exe --cli script open --project <경로> --script <소스 ID 또는 경로> --dry-run

기본 레벨이 없으면 --level을 지정한다. 복잡한 값은 --request <UTF-8 JSON 파일>을 사용한다.
level.events는 events 또는 --events-json 배열의 {name,args}를 같은 Script 이벤트 경로로 전달하고 상태를 반환한다. 문서를 저장하지 않고 기본적으로 draw·update·Pointer 판정은 실행하지 않는다. --step-dt를 지정하면 이벤트마다 update·레벨 전환 경계를 처리한다.
level.simulate는 초기화·업데이트 결과를 반환하며 파일을 수정하거나 draw를 실행하지 않는다. --debug로 로그·도형 기록도 확인한다.
]]}
    }
end
return Instructions
