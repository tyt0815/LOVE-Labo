# LOVE Labo

LÖVE 11.5 + LuaJIT을 사용하는 2D 제작 에디터다. 현재 외부 프로젝트 생성·탐색은 Windows에서 지원한다.

## 실행

```powershell
love .
love . --test
```

시작하면 프로젝트 시작 화면이 표시된다.

개발 중 특정 프로젝트를 바로 열려면 `--project` 뒤에 프로젝트 폴더 경로를 지정한다. 상대 경로는 명령을 실행한 작업 폴더를 기준으로 해석한다.

```powershell
love . --project "tests/TestProject"
love . --project "C:\Projects\TestProject"
```

프로젝트 열기에 실패하거나 경로를 빠뜨리면 시작 화면에서 오류를 표시한다. `--test`를 함께 지정하면 자동화 테스트만 실행한다.

- **New project**: 프로젝트 이름과 부모 폴더를 지정한 뒤 **Create project**를 누른다. 새 프로젝트에는 기본 레벨 `Assets/Levels/StartLevel.level`과 연결된 코드 `Sources/Levels/StartLevel.lua`를 만든다. 기존 폴더는 덮어쓰지 않는다. `.level` 파일의 내용은 JSON이다.
- **Open project**: `project.labo`가 있는 프로젝트 폴더를 지정하고 **Open project**를 누른다. 프로젝트 폴더를 시작 화면으로 드래그해서 경로를 입력할 수도 있다.
- **Browse**: Windows 기본 폴더 선택 창을 연다. 생성 모드에서는 부모 폴더를, 열기 모드에서는 프로젝트 폴더를 선택한다. 취소하면 기존 경로를 유지한다. 경로 입력 및 `Ctrl+V` 붙여넣기도 가능하다. 시작 화면의 경로는 입력 방식과 관계없이 `/`로 표시한다.

```text
MyProject/
  project.labo
  Assets/
    Levels/
      StartLevel.level
  Sources/
    Levels/
      StartLevel.lua
```

프로젝트가 열리면 좌측 계층, 중앙 뷰포트, 우측 인스펙터와 하단 프로젝트 브라우저가 표시된다. 왼쪽 폴더 트리에 `Assets/`와 `Sources/`를 별도 루트로 보여준다.

- 왼쪽 폴더 트리의 오른쪽·아래쪽 화살표로 펼치거나 접고, 이름을 클릭해서 해당 폴더를 연다.
- 기본 파일 보기는 **Thumbnails**다. 이미지 파일은 실제 미리보기, 폴더는 폴더 아이콘을 표시한다. 파일의 기본 아이콘은 정사각형에 종류 텍스트를 넣는 형태로 통일한다(`Lv`, `Lua`, `TXT` 등). 우측 Refresh 왼쪽의 드롭다운에서 **List**로 전환할 수 있다. 드롭다운은 방향키·Enter·Escape도 지원한다.
- 오른쪽 목록의 폴더는 더블클릭 또는 선택 후 `Enter`로 연다. 파일 영역 위의 경로에서 상위 폴더 이름을 클릭하거나 `Backspace`로 이동한다. Assets·Sources 루트 밖으로 이동하지 않는다.
- 경로는 평소 일반 텍스트로 표시하고, 폴더 이름에 마우스를 올리면 클릭 영역의 배경이 부드럽게 나타난다.
- 빈 공간을 우클릭하면 **New**, 파일·폴더를 우클릭하면 **New / Delete** 메뉴를 연다. **New**에는 Assets에서 **Folder / Level / Prefab**, Sources에서 **Folder / Lua Script**만 표시한다. 메뉴가 열린 상태에서 다른 위치를 우클릭하면 해당 위치의 메뉴로 바로 바뀐다. 이름 입력 후 Enter 또는 Create로 생성하며 기존 파일은 덮어쓰지 않는다.
- **Lua Script** 생성 시 **Level Script / LObject Script**를 고른다. **Level** 생성은 기존 Level Script를, **Prefab** 생성은 기존 LObject Script를 선택한다. Sources의 하위 폴더까지 종류에 맞는 소스만 표시하며 선택 목록은 클릭·방향키·휠을 지원한다. Tab으로 이름과 목록 사이를 전환한다. 해당 종류의 소스가 없으면 먼저 Sources에서 만든다. 선택한 소스는 수정하지 않으며 여러 에셋이 같은 코드를 참조할 수 있다.
- **Delete**는 확인 후 파일이나 폴더의 전체 내용을 영구 삭제한다. 프로젝트 루트·기본 레벨·현재 열린 레벨을 포함하는 경로와 파일시스템 링크는 삭제하지 않는다. 레벨에 연결된 Lua나 다른 파일의 참조를 자동으로 정리하지 않는다. 메뉴는 방향키·Enter·Escape로도 조작한다.
- `.level` 파일을 더블클릭하면 해당 레벨을 연다. 현재 레벨에 저장하지 않은 변경이 있으면 유지하고 오류를 표시한다. Lua 코드는 외부 편집기로 수정한다.
- **Refresh** 또는 브라우저에 포커스가 있을 때 `Ctrl+R`로 외부에서 추가·삭제한 파일을 반영한다. 트리와 목록은 각각 마우스 휠로 스크롤한다.
- 계층 오른쪽 경계선과 인스펙터 왼쪽 경계선을 드래그하면 폭을 조절한다. 브라우저 위쪽 경계선을 드래그하면 높이를 조절하며, 경계가 만나는 모서리에서는 두 방향을 함께 조절한다. 헤더의 `-`/`+` 버튼으로 브라우저를 접거나 펼친다.

썸네일은 현재 화면에 보이는 이미지부터 생성하며, 폴더 이동·Refresh에서 캐시를 비운다. 손상된 이미지, 지원하지 않는 형식, 16 MiB를 넘는 파일은 아이콘으로 표시한다. 연결점·심볼릭 링크를 따라 프로젝트 밖 파일을 읽지 않는다.

파일 선택은 인스펙터를 변경하지 않는다. 새 프로젝트는 저장된 기본 레벨을 자동으로 연다. 기본 레벨 지정이 없는 기존 프로젝트는 빈 메모리 Level로 시작하며, Sources가 없어도 열 수 있다.

## 레벨 코드 연결

프로젝트 정보 파일의 `defaultLevelReference`는 기본 레벨을, 레벨 JSON의 `scriptReference`는 실행할 Lua 코드를 가리킨다. 모두 프로젝트 기준 `/` 상대 경로다.

```json
{
  "formatVersion": 1,
  "lobjects": [],
  "scriptReference": "Sources/Levels/StartLevel.lua"
}
```

`.level`은 배치 데이터, Lua는 레벨의 동작을 담당한다. 생성되는 Lua 파일은 다음 형태의 테이블을 반환한다.

```lua
-- labo-script: level
local Level = {}

function Level.load(world)
    -- Play 시작 시 Runtime World를 초기화한다.
end

function Level.update(world, dt)
    -- 매 프레임 호출되며 dt는 초 단위다.
end

return Level
```

종류 표식은 Lua 첫 줄의 `-- labo-script: level` 또는 `-- labo-script: lobject`다. 표식이 없는 기존 Lua는 Level Script로 분류한다. 목록을 만들 때 코드를 실행하지 않는다. LObject Script 템플릿은 `load(self, world)`·`update(self, dt)` 함수를 제공한다.

생성되는 Prefab은 다음 형태다. `definitionReference`는 선택한 LObject Script를 가리키며 빈 `overrides`는 원본 기본값을 유지한다. 현재는 에셋 생성과 참조 저장을 지원한다. Prefab 편집·배치와 LObject Definition의 Runtime 연결은 후속 구현 범위다.

```json
{
  "formatVersion": 1,
  "definitionReference": "Sources/Enemy.lua",
  "overrides": {}
}
```

**F5**는 Play/Stop이다. Play마다 코드 파일을 새로 읽고 Runtime World를 만든다. `load`는 한 번, `update`는 매 프레임 LObject 업데이트 전에 호출한다. Stop은 Runtime 변경을 버리며 배치 데이터에 반영하지 않는다. 코드 오류는 에디터에 표시하고 Play를 시작하지 않거나 중지한다. 자동화 테스트 모드에서는 프로젝트 코드를 실행하지 않는다.

## 에디터 테마

테마는 게임 프로젝트와 별도로 에디터 소스/설치 폴더에서 관리한다. `editor/settings.json`의 `theme`를 바꾸고 에디터를 재시작하면 적용된다.

```json
{
  "version": 1,
  "theme": "atom-one-light"
}
```

- `default`: `editor/theme.lua`에 내장된 어두운 배경과 파란 강조색. JSON 파일 없이도 동작하는 기본 선택이다.
- `atom-one-light`: [VS Code Atom One Light](https://github.com/akamud/vscode-theme-onelight/blob/master/themes/OneLight.json) 스타일의 밝은 회색 배경, 짙은 글자와 파란 강조색.

색을 직접 바꾸려면 아래처럼 `editor/themes/my-theme.json`을 만들고 설정에서 `"theme": "my-theme"`을 선택한다. 파일의 `colors`는 `#RRGGBB` 또는 알파를 포함한 `#RRGGBBAA` 색을 받는다. 일부 색만 지정해도 나머지는 코드에 내장된 기본 테마를 사용한다. 모든 색 항목은 `atom-one-light.json`을 참고한다.

```json
{
  "version": 1,
  "colors": {
    "panel": "#20242C",
    "selection": "#405C85",
    "focus": "#80B4FF"
  }
}
```

글자·경계·선택 등 공통 색은 공유하고, 버튼·입력칸·아이콘 등 독립적으로 조절할 부분은 용도별 색을 제공한다. 새 UI에서 별도 색이 필요하면 코드의 기본 테마와 제공하는 테마 JSON에 항목을 함께 추가한다. 기존 사용자 테마에 새 항목이 없으면 기본값을 상속하므로 파일을 즉시 수정할 필요는 없다.

| 역할 | 용도 |
|---|---|
| `background` | 화면 바탕 |
| `panel`, `surface`, `button`, `input` | 패널·팝업 표면·버튼·입력칸 |
| `text`, `textMuted`, `textDisabled` | 일반·보조·비활성 글자 |
| `border`, `focus`, `hover`, `selection` | 경계·포커스·호버·선택 상태 |
| `error`, `overlay` | 오류와 모달 뒤 덮개 |
| `thumbnailBackground`, `iconBackground`, `iconBorder`, `iconText`, `folderTab`, `folderBody` | 썸네일·파일 아이콘·폴더 아이콘 |
| `grid`, `axisX`, `axisY`, `origin`, `object`, `objectSelected`, `gameBackground` | 뷰포트 격자·축·디버그 표시·Game View 바탕 |

설정이나 선택된 테마가 없거나 잘못되면 코드의 기본 테마로 시작한다. 기본 테마 JSON은 읽지 않는다. 이미지 미리보기의 원래 색은 유지한다.

## 에디터 UI 구성

`editor/ui/`는 위젯 트리와 입력 전달을 관리한다. Core Runtime 및 LObject 생명주기와 분리된다.

```text
editor/ui/
  widget.lua          # 공통 위젯과 이벤트 처리
  panel.lua           # 자식 위젯·그리기 순서·클리핑
  slot.lua            # 부모 기준 배치 정보
  canvas.lua          # 슬롯 배치와 중첩 Canvas
  root.lua            # 입력 소비·포커스·드래그 캡처·팝업
  dropdown.lua        # 재사용 가능한 보기 선택 컨트롤
  breadcrumb.lua      # 클릭 가능한 프로젝트 상대 경로
  context_menu.lua    # 하위 메뉴와 항목별 동작을 받는 공통 우클릭 메뉴
  dialog.lua          # 이름 입력·삭제 확인 팝업
  editor_layout.lua   # 에디터 패널 배치·경계선 크기 조절
```

기존 `editor/ui.lua`는 텍스트·버튼·입력칸 그리기 도우미로 유지한다. 에디터는 루트의 그리기·입력 메서드를 호출하며, 계층·뷰포트·인스펙터는 각각 Canvas 안의 콘텐츠 위젯으로 연결된다. 프로젝트 브라우저는 내부에 폴더 트리·경로·파일 영역·드롭다운 슬롯을 가진 Canvas다. 내부 모듈명은 `asset_browser.lua`를 유지한다. 확장자별 플러그인 등록 API는 아직 제공하지 않는다.
