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

- **New project**: 프로젝트 이름과 부모 폴더를 지정한 뒤 **Create project**를 누른다. 새 프로젝트에는 기본 레벨 `Assets/Levels/Default.level`과 연결된 코드 `Sources/Levels/Default.lua`를 만든다. 기존 폴더는 덮어쓰지 않는다. `.level` 파일의 내용은 JSON이다.
- **Open project**: `project.labo`가 있는 프로젝트 폴더를 지정하고 **Open project**를 누른다. 프로젝트 폴더를 시작 화면으로 드래그해서 경로를 입력할 수도 있다.
- **Browse**: Windows 기본 폴더 선택 창을 연다. 생성 모드에서는 부모 폴더를, 열기 모드에서는 프로젝트 폴더를 선택한다. 취소하면 기존 경로를 유지한다. 경로 입력 및 `Ctrl+V` 붙여넣기도 가능하다. 시작 화면의 경로는 입력 방식과 관계없이 `/`로 표시한다.

```text
MyProject/
  project.labo
  Assets/
    Levels/
      Default.level
  Sources/
    Levels/
      Default.lua
```

프로젝트가 열리면 좌측 계층, 중앙 뷰포트, 우측 인스펙터와 하단 프로젝트 브라우저가 표시된다. 왼쪽 폴더 트리에 `Assets/`와 `Sources/`를 별도 루트로 보여준다.

- 왼쪽 폴더 트리의 오른쪽·아래쪽 화살표로 펼치거나 접고, 이름을 클릭해서 해당 폴더를 연다.
- 기본 파일 보기는 **Thumbnails**다. 이미지 파일은 실제 미리보기, 레벨은 정사각형 `Lv`, 폴더와 일반 파일은 종류 아이콘을 표시한다. 우측 Refresh 왼쪽의 드롭다운에서 **List**로 전환할 수 있다. 드롭다운은 방향키·Enter·Escape도 지원한다.
- 오른쪽 목록의 폴더는 더블클릭 또는 선택 후 `Enter`로 연다. 파일 영역 위의 경로에서 상위 폴더 이름을 클릭하거나 `Backspace`로 이동한다. Assets·Sources 루트 밖으로 이동하지 않는다.
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
  "scriptReference": "Sources/Levels/Default.lua"
}
```

`.level`은 배치 데이터, Lua는 레벨의 동작을 담당한다. 생성되는 Lua 파일은 다음 형태의 테이블을 반환한다.

```lua
local Level = {}

function Level.load(world)
    -- Play 시작 시 Runtime World를 초기화한다.
end

function Level.update(world, dt)
    -- 매 프레임 호출되며 dt는 초 단위다.
end

return Level
```

**F5**는 Play/Stop이다. Play마다 코드 파일을 새로 읽고 Runtime World를 만든다. `load`는 한 번, `update`는 매 프레임 LObject 업데이트 전에 호출한다. Stop은 Runtime 변경을 버리며 배치 데이터에 반영하지 않는다. 코드 오류는 에디터에 표시하고 Play를 시작하지 않거나 중지한다. 자동화 테스트 모드에서는 프로젝트 코드를 실행하지 않는다.

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
  editor_layout.lua   # 에디터 패널 배치·경계선 크기 조절
```

기존 `editor/ui.lua`는 텍스트·버튼·입력칸 그리기 도우미로 유지한다. 에디터는 루트의 그리기·입력 메서드를 호출하며, 계층·뷰포트·인스펙터는 각각 Canvas 안의 콘텐츠 위젯으로 연결된다. 프로젝트 브라우저는 내부에 폴더 트리·경로·파일 영역·드롭다운 슬롯을 가진 Canvas다. 내부 모듈명은 `asset_browser.lua`를 유지한다. 확장자별 플러그인 등록 API는 아직 제공하지 않는다.
