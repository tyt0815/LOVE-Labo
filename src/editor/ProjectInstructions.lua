local Instructions = {version = "development", documentationUrl = "https://tyt0815.github.io/LOVE-Labo/"}
function Instructions.files()
    return {
        {name = "AGENTS.md", text = [[# LÖVE Labo 프로젝트 AI 작업 지침

- 실행 계약: LÖVE 11.5 + LuaJIT / Lua 5.1, attached-script 개발 버전.
- 작업 전 https://tyt0815.github.io/LOVE-Labo/guide/ai/ 와 관련 API 문서를 확인한다.
- 웹 문서와 설치 버전이 다르면 Docs/EngineGuide.md, CLI help, 실제 제공 API를 기준으로 한다.
- 게임 코드는 Assets에서 수정한다. 엔진 코어·DLL·배포 파일은 직접 수정하지 않는다.
- 에셋 생성·이동·삭제·배치는 Labo-cli.exe 명령을 우선 사용하고 assets.json의 ID를 보존한다.
- GUI에서 연 문서를 저장한 뒤 CLI로 수정한다. CLI 변경은 GUI Undo에 포함되지 않는다.
- LObject는 Transform과 자손 계층을 소유한다. Lua 스크립트를 여러 개 부착하며 self.owner가 오브젝트다.
- Prefab에서 스크립트를 추가·제거·정렬한다. 배치 인스턴스에도 로컬 스크립트를 추가한다. 상속한 오브젝트·스크립트의 구조는 고정하고 값만 재정의한다.
- 클래스·파일 이름은 PascalCase, 변수·함수는 camelCase, 상수는 UPPER_SNAKE_CASE, 들여쓰기는 공백 4칸이다.
]]},
        {name = "Docs/EngineGuide.md", text = [[# LÖVE Labo 로컬 핵심 안내

공식 문서: https://tyt0815.github.io/LOVE-Labo/ — 개발 버전의 실제 CLI help와 함께 확인한다.

## 오브젝트와 스크립트

LObject는 Transform과 부모·자손을 가진다. 스크립트는 오브젝트를 상속하지 않고 독립 인스턴스로 부착된다.
Lua 파일은 properties와 선택적인 load(world), update(dt), draw(context)를 가진 테이블을 반환한다.
편집 화면 표시는 drawEditor(context)에서 도형을 계산한다. 이때 load/update는 실행되지 않는다.
world.debug:log/screenLog/point/line/circle/rect/polygon은 Editor Play에서만 표시되고 배포에서는 no-op이다.
self는 스크립트이며 self.owner.transform, self.owner:getScriptByName(name), getScriptById(id), getScriptByClass(class), getScriptsByClass(class)로 오브젝트·다른 스크립트를 사용한다.
일반 Lua 필드는 Inspector에 노출되지 않는다. properties에 number/string/boolean/object/script/image/prefab를 선언한다.
group으로 프로퍼티를 묶는다. object 참조는 authoringId, script 참조는 {authoringId=ID, script="부착ID"}로 저장한다.

require("Engine")은 LObject, Script와 공간·바운드 API를 제공한다. Camera, Sprite, Pointer, RectBounds, Canvas는 LaboEssentials를 활성화한 경우에만 제공된다. 새 부착에는 RectBounds를 사용하며 기존 Rect 별칭은 읽기 호환성을 유지한다.
편의 스크립트는 Script를 직접 상속하며 별도의 컴포넌트 계층·루트 컴포넌트는 없다.
Camera의 viewWidth/viewHeight는 논리 화면 크기이고 zoom은 배율이다. World의 setActiveCamera로 전환한다.
Canvas는 화면 중심을 원점으로 하는 픽셀 좌표계를 시작한다. Pointer의 boundsSource는 같은 오브젝트의 스크립트 ID다.
onPointerDown/up/move에서 true를 반환하면 입력을 소비한다. 직접 hitTest/getLocalBounds를 구현할 수도 있다.
world:spawnLObject(prefab, transform, overrides)로 Prefab 계층을 생성하고 world:removeLObject(object)로 자손까지 제거한다.
world:openLevel(reference)은 프레임 경계에서 레벨을 전환한다. Camera 플러그인이 활성화된 프로젝트의 새 레벨에만 기본 Camera와 Main Camera 지정을 포함한다.

## 데이터와 CLI

모든 에셋은 Assets 아래에 있으며 assets.json의 ID로 참조한다. Docs는 게임 Export에 포함하지 않는다.
Prefab 형식은 4, 레벨 형식은 3이다. 이전 Sources는 Assets/Scripts로 이동하지만 옛 컴포넌트 코드·Prefab은 수동 전환해야 한다.
스크립트는 공통 enabled로 실행을 켜고 끈다. 런타임 addScript/removeScript는 제공하지 않으며 부착·제거는 편집 작업이다.
Prefab의 scripts는 {id,source,name} 목록, overrides.scripts는 부착 ID별 프로퍼티 재정의다.

Labo-cli.exe --cli help
Labo-cli.exe --cli script create --project <경로> --name Movement
Labo-cli.exe --cli prefab script add --project <경로> --prefab Assets/PF_Player.prefab --source Assets/Movement.lua --script movement
Labo-cli.exe --cli prefab script move --project <경로> --prefab Assets/PF_Player.prefab --script movement --index 1
Labo-cli.exe --cli level simulate --project <경로> --frames 60 --dt 0.0166667
Labo-cli.exe --cli level pointer --project <경로> --space screen --x 640 --y 360

기본 레벨이 없으면 --level을 지정한다. 복잡한 값은 --request <UTF-8 JSON 파일>을 사용한다.
level.simulate는 초기화·업데이트 결과를 반환하며 파일을 수정하거나 draw를 실행하지 않는다. --debug로 로그·도형 기록도 확인한다.
]]}
    }
end
return Instructions
