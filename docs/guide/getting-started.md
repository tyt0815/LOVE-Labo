# 첫 프로젝트와 실행


Camera·Sprite·Pointer·RectBounds·Canvas를 사용하려면 먼저 [플러그인](plugins.md)을 활성화합니다. 새 프로젝트에서는 모두 꺼져 있습니다.

LÖVE Labo는 LÖVE 11.5 기반 2D 작업 환경입니다. 개발 실행은 `love src`, 배포본은 Labo.exe를 사용합니다.

1. 시작 화면의 New project에서 이름과 부모 폴더를 선택합니다. 기존 폴더는 덮어쓰지 않습니다.
2. 프로젝트에는 Assets, AGENTS.md, Docs/EngineGuide.md를 만듭니다. 처음에는 아직 저장하지 않은 빈 레벨을 표시합니다.
3. File → New → Level로 레벨을 만듭니다. 기본 Camera 오브젝트와 Main Camera 지정이 포함됩니다.
4. File → New → Lua Class에서 Script를 부모로 골라 행동 코드를 작성합니다.
5. Prefab을 만들고 Add Script로 행동과 Sprite를 부착합니다. image 스포이드로 이미지를 지정합니다.
6. Prefab을 뷰포트 또는 Hierarchy에 배치하고 Run → Play 또는 F5로 실행합니다.

![에디터 구성](images/editor-overview.svg)

모든 에셋은 Assets 아래에 자유롭게 정리합니다. assets.json의 ID로 참조하므로 이동·이름 변경은 에디터나 CLI로 수행합니다. 이전 Sources 폴더는 충돌이 없을 때 Assets/Scripts로 옮겨집니다. 옛 컴포넌트 코드·Prefab은 수동 전환이 필요합니다.

예제는 tests/TestProject입니다. NewClass의 노출·비노출 프로퍼티, Sprite, 자손, object/script 참조와 런타임 생성 예제를 포함합니다. [스크립트와 Prefab](objects.md), [Lua API](lua-api.md), [CLI](../cli-and-export.md)를 이어서 확인하세요.
