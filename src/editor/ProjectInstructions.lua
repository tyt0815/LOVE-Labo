local Instructions = {version = "development", documentationUrl = "https://tyt0815.github.io/LOVE-Labo/"}
function Instructions.files()
    return {
        {name = "AGENTS.md", text = [[# LÖVE Labo 프로젝트 AI 작업 지침

- 엔진 버전: development (LÖVE 11.5 + LuaJIT / Lua 5.1).
- 게임 코드 작성·수정 전 공식 문서의 관련 항목을 확인한다.
- 공식 문서: https://tyt0815.github.io/LOVE-Labo/
- AI 시작 페이지: https://tyt0815.github.io/LOVE-Labo/guide/ai/
- 웹 문서가 접근되지 않으면 Docs/EngineGuide.md와 실제 CLI help를 사용한다.
- 클래스·Prefab·레벨·에셋 작업은 제공되는 Labo-cli.exe 명령을 우선 사용한다.
- 프로젝트의 Sources·Assets를 수정하고 엔진 코어·DLL·배포 파일은 직접 수정하지 않는다.
- .meta와 에셋 ID는 CLI·에디터로 관리한다. 파일 이동·삭제도 CLI를 사용한다.
- 문서에 없는 API를 추측하지 말고 CLI help와 실제 제공 API를 확인한다.
- GUI에 열린 문서를 저장한 뒤 CLI로 변경한다. CLI 변경은 GUI Undo에 포함되지 않는다.
- 클래스 테이블·파일은 PascalCase, 변수·함수는 camelCase, 상수는 UPPER_SNAKE_CASE, 들여쓰기는 4칸이다.
- 새 레벨은 기본 Camera와 Main Camera 지정을 포함한다. 빈 레벨이 필요하면 level create --empty를 사용한다.
]]},
        {name = "Docs/EngineGuide.md", text = [[# LÖVE Labo 로컬 핵심 안내

엔진 버전: development. 실행 계약: LÖVE 11.5, LuaJIT/Lua 5.1.
공식 문서: https://tyt0815.github.io/LOVE-Labo/
이 파일은 프로젝트 생성 시 복사한 안내다. 배포 엔진의 CLI help와 공식 문서도 함께 확인한다.

## 프로젝트

Sources에는 Lua Class, Assets에는 이미지·Prefab·레벨이 있다. project.labo는 프로젝트 설정이며 .meta의 ID로 참조를 유지한다. Docs는 게임 Export에 포함하지 않는다.

## 코드

`local Engine = require("Engine")`로 기본 컴포넌트를 가져온다. LObject Class의 properties에 number/string/boolean/object/image/lobjectTemplate 필드를 선언한다. group은 Inspector 그룹이다. 일반 Lua 필드는 노출되지 않는다.

build(self)는 에디터에서도 실행하는 구성 함수다. self:addComponent(name, class, overrides, parent), self:setRootComponent(name, class, overrides)로 컴포넌트를 붙인다. beginPlay(self, world)는 런타임 초기화, update(self, dt)는 게임 진행이다.

LObjectComponent → SceneComponent → BoundsComponent를 상속한다. RenderComponent와 PointerComponent는 BoundsComponent를 상속한다. SpriteComponent는 RenderComponent, RectComponent는 BoundsComponent, CanvasComponent는 RectComponent, CameraComponent는 SceneComponent를 상속한다.

루트 Transform은 인스턴스 Transform이며 자손은 부모 변환을 합성한다. CameraComponent의 viewWidth/viewHeight/zoom이 게임 화면을 결정하고 world:setActiveCamera(component)로 전환한다. Canvas는 화면 중심 원점의 픽셀 좌표계이며 카메라 영향을 받지 않는다.

PointerComponent의 onPointerDown/onPointerUp/onPointerMove에서 true를 반환하면 입력을 소비한다. boundsSource는 같은 오브젝트의 Bounds 컴포넌트 이름이다. Sprite.image는 이미지 에셋 ID다.

world:spawnLObject(template, transform, overrides)로 Class 또는 Prefab을 생성한다. world:openLevel(reference)는 프레임 경계에서 레벨을 전환한다.

## CLI

Labo-cli.exe --cli help
Labo-cli.exe --cli project info --project <프로젝트 경로>
Labo-cli.exe --cli project validate --project <프로젝트 경로>
Labo-cli.exe --cli level view --project <프로젝트 경로>
Labo-cli.exe --cli level set-camera --project <프로젝트 경로> --instance <ID> --component <이름>
Labo-cli.exe --cli level pointer --project <프로젝트 경로> --space screen --x 640 --y 360

기본 레벨이 없으면 --level을 지정한다. level create는 기본 Camera를 만들고 --empty는 빈 레벨을 만든다. 복잡한 작업은 --request <UTF-8 JSON 파일>을 사용한다. 명령별 인자와 revision 계약은 공식 CLI 문서와 help를 읽는다.
]]}
    }
end
return Instructions
