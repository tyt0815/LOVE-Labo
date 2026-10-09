# LOVE Labo

LÖVE 11.5 + LuaJIT을 사용하는 2D 제작 에디터다. 현재 외부 프로젝트 생성·탐색은 Windows에서 지원한다.

제품 코드와 번들 리소스는 `src/`, 개발 테스트·샘플 프로젝트는 `tests/`, 문서는 `docs/`, 자동화는 `scripts/`, 생성된 배포물은 `build/`에 둔다. 패키징·CLI·게임 Export 사용법은 [패키징](docs/packaging.md)과 [CLI·Export](docs/cli-and-export.md)를 참고한다.

## 실행

```powershell
love src
love src --test
```

시작하면 프로젝트 시작 화면이 표시된다.

개발 중 특정 프로젝트를 바로 열려면 `--project` 뒤에 프로젝트 폴더 경로를 지정한다. 상대 경로는 명령을 실행한 작업 폴더를 기준으로 해석한다.

```powershell
love src --project "tests/TestProject"
love src --project "C:\Projects\TestProject"
```

프로젝트 열기에 실패하거나 경로를 빠뜨리면 시작 화면에서 오류를 표시한다. `--test`를 함께 지정하면 자동화 테스트만 실행한다.

- **New project**: 프로젝트 이름과 부모 폴더를 지정한 뒤 **Create project**를 누른다. 새 프로젝트에는 빈 `Assets/`·`Sources/`만 만들고, 파일 경로가 없는 빈 레벨 문서를 연다. 초기 Level·Lua 파일은 생성하지 않으며 기존 폴더는 덮어쓰지 않는다.
- **Open project**: `project.labo`가 있는 프로젝트 폴더를 지정하고 **Open project**를 누른다. 프로젝트 폴더를 시작 화면으로 드래그해서 경로를 입력할 수도 있다.
- **Browse**: Windows 기본 폴더 선택 창을 연다. 생성 모드에서는 부모 폴더를, 열기 모드에서는 프로젝트 폴더를 선택한다. 취소하면 기존 경로를 유지한다. 경로 입력 및 `Ctrl+V` 붙여넣기도 가능하다. 시작 화면의 경로는 입력 방식과 관계없이 `/`로 표시한다.

```text
MyProject/
  project.labo
  asset-index.json          # 재생성 가능한 ID → 경로 캐시
  Assets/
  Sources/
```

프로젝트가 열리면 좌측 계층, 중앙 뷰포트, 우측 인스펙터와 하단 프로젝트 브라우저가 표시된다. 왼쪽 폴더 트리에 `Assets/`와 `Sources/`를 별도 루트로 보여준다.

상단의 **File → New** 서브메뉴에서 Class·Prefab·Level을 생성하고, **File** 메뉴에서 Save·Save Level As·Export Game을 실행한다. **Run** 메뉴는 Play·Stop을 제어하며 메뉴 이름과 항목은 영어로 표시한다. 기본 메뉴 버튼에는 배경·테두리가 없으며 호버·열림 상태만 강조한다. **Ctrl+Z / Ctrl+Shift+Z**는 레벨·인스턴스·Prefab의 문서 편집과 에디터에서 실행한 파일·폴더 생성·삭제·이동·이름 변경을 취소/다시 실행한다. 활성 문서 편집과 에셋 작업의 순서를 비교해 한 단계씩 처리하며 드래그나 필드 편집 한 번을 한 단계로 기록한다. 문서별 최대 100개 상태, 에셋 작업 최대 100개를 보관하고 새 편집은 Redo 분기를 제거한다. 저장·Save Level As·Export와 외부 도구/CLI의 파일 변경·Lua 소스 편집은 기록하지 않는다.

파일 작업은 `.meta`와 ID를 함께 복원한다. 삭제 및 생성 취소의 원본은 프로젝트의 `.labo-history/`에 보관하며, 내용의 외부 변경이나 복원 위치의 충돌이 있으면 덮어쓰지 않고 브라우저에 오류를 표시한다. 기록은 현재 에디터 세션에 한정되며 캐시는 자동 삭제하지 않는다. 에디터를 종료한 뒤 필요 없는 `.labo-history/`를 삭제할 수 있지만 삭제 원본도 함께 사라진다. 생성 취소에도 기존 삭제 보호 규칙을 적용하므로 현재 열린 레벨은 다른 레벨을 연 뒤 취소해야 한다.

계층·인스펙터·브라우저는 배경 위에 여백과 둥근 테두리가 있는 독립 패널로 표시한다. 제목은 굵고 큰 글씨와 구분선으로 내용과 구별한다. 창 맨 아래의 상태 표시줄은 패널 밖 배경 위에 표시하며, 버튼·경로·파일·프로퍼티·패널 경계 등에 마우스를 올리면 해당 UI의 사용 힌트가 바뀐다. 드래그 안내와 실제 오류도 이 영역에 표시한다. 상태 표시줄은 문서 편집이나 패널 크기 조절 입력을 소비한다.

- 왼쪽 폴더 트리의 오른쪽·아래쪽 화살표로 펼치거나 접고, 이름을 클릭해서 해당 폴더를 연다.
- 기본 파일 보기는 **Thumbnails**다. 이미지 파일은 실제 미리보기, 폴더는 폴더 아이콘을 표시한다. 파일은 흰 정사각형에 종류 텍스트를 넣는다. Level은 `Lv`, Prefab은 `Pf`, Lua Class는 종류별 `Lv`·`LO`·`Cp`와 우하단 작은 `Lua` 표식을 표시한다. Level·Prefab·Level Class·LObject Class·Component Class는 서로 다른 테마 색을 사용한다. 우측 Refresh 왼쪽의 드롭다운에서 **List**로 전환할 수 있다. 드롭다운은 방향키·Enter·Escape도 지원한다.
- 오른쪽 목록의 폴더는 더블클릭 또는 선택 후 `Enter`로 연다. 파일 영역 위의 경로에서 상위 폴더 이름을 클릭하거나 `Backspace`로 이동한다. Assets·Sources 루트 밖으로 이동하지 않는다.
- 경로는 평소 일반 텍스트로 표시하고, 폴더 이름에 마우스를 올리면 클릭 영역의 배경이 부드럽게 나타난다.
- 빈 공간을 우클릭하면 **New**, 파일·폴더를 우클릭하면 각각 별개인 **New / Move / Rename / Delete** 메뉴를 연다. **New**에는 Assets에서 **Folder / Level / Prefab**, Sources에서 **Folder / Lua Class**만 표시한다. 메뉴가 열린 상태에서 다른 위치를 우클릭하면 해당 위치의 메뉴로 바로 바뀐다. 이름 입력 후 Enter 또는 Create로 생성하며 기존 파일은 덮어쓰지 않는다.
- **Move**는 경로 입력란 아래의 폴더 트리에서 목적지 폴더를 선택한다. 폴더 경로를 직접 입력해도 된다(예: `Sources/Enemies`). 이름은 유지하고 원본과 메타를 함께 옮긴다. 트리는 같은 Assets·Sources 루트만 표시하며 링크와 이동할 폴더 자신·하위 폴더는 제외한다. 화살표로 펼치고 이름을 클릭해서 선택한다. Tab으로 경로·트리 입력을 전환하고 방향키·휠로 탐색할 수 있다.
- **Rename**은 현재 폴더에서 이름만 변경하고 파일 확장자는 유지한다. 이동·이름 변경 모두 기존 파일을 덮어쓰지 않고 ID를 유지한다. 현재 열린 레벨과 Prefab도 ID로 새 저장 위치를 찾는다.
- 파일·폴더를 드래그해서 이동할 수도 있다. 목록↔트리 양방향과 각 영역 내부의 이동을 지원한다. 폴더 위에 놓으면 그 폴더로, 파일 영역의 빈 공간에 놓으면 현재 폴더로 이동한다. 트리 화살표는 펼치기·접기 전용이고 폴더 이름의 일반 클릭은 마우스를 놓을 때 탐색한다. 루트·링크는 드래그하지 않으며 다른 루트·자기 하위·같은 위치·이름 충돌로의 드롭은 막는다. 드래그 중 목적지와 실패 사유를 표시하고 트리의 폴더 위에 잠시 머물면 펼친다. 각 영역 가장자리의 자동 스크롤·휠 스크롤과 Esc 취소를 지원한다.
- **Lua Class / Level / Prefab** 생성은 두 단계다. 첫 창의 상속 트리에서 부모를 선택하고 **Next**를 누르면, 두 번째 창에서 폴더 트리의 저장 위치와 이름을 지정한다. 우클릭한 폴더가 기본 위치이며 빈 공간·파일 우클릭은 현재 폴더를 사용한다. **Back**은 선택한 부모·폴더·이름을 유지한다. 클래스 종류는 부모에서 자동 결정되며 내장 **Level / LObject**를 선택하면 부모 Lua 없이 생성한다. 상속 트리는 Lua 선언을 로드해 `extends` 관계를 읽으며 잘못된 부모는 Invalid로 표시하고 생성을 막는다.
- Prefab의 부모는 LObject 클래스 또는 다른 Prefab이다. 값은 **클래스 기본값 → 부모 Prefab → 자식 Prefab → 배치 인스턴스** 순서로 적용한다. 오브젝트·컴포넌트 프로퍼티 값을 필드별로 override하며 컴포넌트 추가·삭제는 Lua 클래스에서만 한다. 자식에서 바꾸지 않은 값은 부모 변경을 따라가고 Inspector의 롤백은 바로 부모의 값으로 돌아간다. Parent Class 드롭다운에서도 부모 Prefab을 변경할 수 있으며 자신·자손 선택과 순환 상속을 막는다. 깊이는 최대 64단계다. 부모를 외부에서 편집했다면 Refresh로 선언을 다시 읽는다.
- **Delete**는 확인 후 파일이나 폴더의 전체 내용을 캐시로 이동하며 Undo로 복원한다. 프로젝트 루트·기본 레벨·현재 열린 레벨을 포함하는 경로와 파일시스템 링크는 삭제하지 않는다. 저장하지 않은 Prefab도 먼저 저장해야 한다. 레벨에 연결된 Lua나 다른 파일의 참조를 자동으로 정리하지 않는다. 메뉴는 방향키·Enter·Escape로도 조작한다.
- `.level` 파일을 더블클릭하면 해당 레벨을 연다. 현재 레벨에 저장하지 않은 변경이 있으면 유지하고 오류를 표시한다. Lua 코드는 외부 편집기로 수정한다.
- **Refresh** 또는 브라우저에 포커스가 있을 때 `Ctrl+R`로 외부에서 추가·삭제한 파일을 반영한다. 트리와 목록은 각각 마우스 휠로 스크롤한다.
- 계층 오른쪽 경계선과 인스펙터 왼쪽 경계선을 드래그하면 폭을 조절한다. 브라우저 위쪽 경계선을 드래그하면 높이를 조절하며, 경계가 만나는 모서리에서는 두 방향을 함께 조절한다. 헤더의 `-`/`+` 버튼으로 브라우저를 접거나 펼친다.

썸네일은 현재 화면에 보이는 이미지부터 생성하며, 폴더 이동·Refresh에서 캐시를 비운다. 손상된 이미지, 지원하지 않는 형식, 16 MiB를 넘는 파일은 아이콘으로 표시한다. 연결점·심볼릭 링크를 따라 프로젝트 밖 파일을 읽지 않는다.

계층·뷰포트에서 LObject를 선택하면 인스펙터에 Transform을 표시하고, 선택을 해제하면 현재 Level의 부모 클래스·프로퍼티를 표시한다. 브라우저에서 Prefab을 클릭하면 해당 Prefab의 부모 클래스·프로퍼티를 표시한다. 저장하지 않은 Prefab을 다른 Prefab으로 교체하는 선택은 막고 저장 안내를 표시한다.

선택한 LObject의 오른쪽·위쪽 화살표는 각각 X·Y축 이동 기즈모다. 기즈모 원점의 하얀 원을 드래그하면 자유롭게 이동한다. 객체 본체 클릭은 선택만 하며 Escape는 진행 중인 변환을 취소한다. A 키의 빈 객체 생성은 제거했으며 Prefab을 드롭해 배치한다.

**W / E / R** 단축키로 Move / Rotate / Scale 모드를 선택한다. Space 모드 전환은 제거했다. 모드 버튼은 없으며 좌상단에 단축키 힌트를 표시한다. 입력칸 편집 중에는 모드 단축키가 동작하지 않는다. 가로 X축·X 핸들, 세로 Y축·Y 핸들은 같은 테마 색을 사용하며 선은 원점부터 이어진다. 그리드 한 칸은 100 월드 단위이며 줌에 따라 화면 간격만 바뀐다.

뷰포트 우상단의 제목 없는 패널에는 **Move [값] Rot [값] Scale [값]**만 가로로 표시한다. 숫자 입력칸은 세 자리 숫자와 여백에 맞는 폭이다. 각 이름 버튼은 해당 스냅만 On/Off하고 선택 모드는 바꾸지 않는다. 초기값은 모두 꺼짐이며 Move=32 월드 단위, Rot=15도, Scale=0.1 배율 단위다. 양수 값만 입력하고 Enter·다른 입력칸 클릭·앱 종료 시 확정한다. 각 토글과 값은 LÖVE 사용자 저장 폴더의 `viewport-settings.json`에 저장해 재시작 후 복원한다. 레벨과 테마 설정은 수정하지 않는다.

각 스냅은 시작 Transform에서의 변화량에 적용한다. X=20, Move=100이면 120/-80으로 이동하고 반대 축은 유지한다. 회전 350도, Rot=30에서 30도 이동하면 20도로 감싼다. Scale=0.1은 해당 축의 배율 변화량을 0.1 단위로 조절하며 중앙 균등 스케일은 X 변화량을 기준으로 스냅하고 Y 비율을 유지한다. 복제는 원본 위치 기준이며 새 Prefab 드롭은 커서 위치를 사용한다.

회전 기즈모는 위쪽 선·오른쪽 선·두 선을 잇는 우상단 ¼원 호로 표시한다. 위쪽 선을 잡아 세로로 드래그하면 X 회전, 오른쪽 선을 잡아 가로로 드래그하면 Y 회전, 호를 잡아 돌리면 Z 회전이다. 선 드래그 중에는 선택한 축의 지름선만, 호 드래그 중에는 전체 원만 표시한다. X/Y는 화면 1px당 1도이며 위쪽/오른쪽 이동이 증가 방향이다. 세 축 모두 Rot 스냅을 적용하고 Escape는 시작값을 복원한다. Inspector에서도 **Rot X° / Y° / Z°**를 입력한다. X/Y 회전은 스프라이트 평면을 기울여 XY에 직교 투영하며 원근·깊이 정렬은 없다. 스케일 → X → Y → Z 회전 순서다. Z의 양수 각도는 화면에서 시계 방향이고 모든 각도는 편집·저장·로드에서 0 이상 360 미만으로 정규화한다. 정확히 옆면을 향한 평면은 면적이 없어 이미지 클릭으로 선택할 수 있으므로 Hierarchy를 사용한다. 스케일 기즈모의 축 끝 사각형은 투영된 해당 로컬 축만, 중앙 하얀 사각형은 X/Y 비율을 유지하며 확대·축소한다. 중앙을 오른쪽/위로 끌면 확대, 왼쪽/아래로 끌면 축소한다. 기즈모 최소 스케일은 0.01이며 Inspector의 **Scale X/Y**는 양수만 받는다. 회전·스케일은 레벨 저장·복제·Play와 Sprite 렌더링·선택에 반영된다.

인스턴스를 선택하면 그 인스턴스의 각 Sprite 이미지 크기에 맞는 사각형 외곽선을 표시한다. 외곽선은 컴포넌트 상대 위치와 LObject 회전·스케일·뷰포트 줌을 따른다. 투명 픽셀의 윤곽을 추적하지 않고 전체 이미지 범위를 보여준다. Inspector 포커스로 이동해도 선택한 인스턴스가 유지되며 이전 브라우저 프리팹 선택으로 돌아가지 않는다.

인스펙터는 고정 Inspector 제목 아래에 선택 대상 이름을 굵게, 종류를 보조 글씨로 표시한다. 에셋 이름은 확장자를 제외하고 이동·이름 변경 후 현재 ID 경로에서 갱신한다. 저장 전 레벨은 Untitled Level, 이름 없는 인스턴스는 LObject와 authoringId로 표시한다. 그 밖의 에셋·폴더를 선택하면 이름·종류·경로를 읽기 전용으로 표시한다. 다른 레벨은 더블클릭으로 열어 편집하고 현재 열린 레벨을 선택하면 기존 부모·프로퍼티 편집을 유지한다. 브라우저 헤더 우측에는 보기 선택·Refresh·접기 버튼이 차례로 있다.

`Ctrl+S`는 편집 중인 인스펙터 값을 확정하고 해당 문서를 저장한다. 빈 레벨의 첫 저장은 **Save Level** 창에서 `Assets/NewLevel.level` 같은 경로를 입력해 새 파일을 만든다. 부모 폴더는 먼저 생성해야 하며 기존 파일은 덮어쓰지 않는다. 취소·실패 시 편집 내용과 저장 전 상태를 유지한다. 기본 레벨 지정이 없거나 파일이 없으면 빈 문서로 시작한다. 첫 저장을 기본 레벨 지정으로 자동 전환하지는 않는다. `project.labo`에 기본 레벨 ID가 지정된 기존 프로젝트는 해당 레벨을 연다.

텍스트 입력칸은 `|` 커서 위치에서 삽입한다. 편집 중 같은 입력칸을 클릭하면 커서를 옮기고 마우스 드래그 또는 Shift+좌우/Home/End로 문자를 선택한다. 선택 영역이 있을 때는 커서를 숨기며 좌우 화살표로 선택을 해제하면 왼쪽/오른쪽 경계에 커서를 표시한다. 선택 영역에 입력·붙여넣기하면 선택한 문자만 교체한다. 좌우·Home/End로 커서를 이동하고 Backspace/Delete로 앞/뒤 문자 또는 선택 영역을 지운다. Ctrl+A/C/X/V는 전체 선택·선택 복사·잘라내기·붙여넣기이며 Ctrl+좌우는 공백 단위 이동이다. 최초 Inspector·스냅 입력칸 포커스는 빠른 값 교체를 위해 전체 선택한다. 한글 조합은 커서 위치에 밑줄로 표시하고 확인·필드 이동에서 확정한다. 선택 하이라이트는 테마의 `textSelection`, 커서·조합 밑줄은 `focus` 색을 사용한다.

Inspector는 **Transform → 컴포넌트 그룹 → 클래스 이름 그룹** 순서로 모두 접고 펼칠 수 있다. 예를 들어 `Transform`, `sprite (SpriteComponent)`, `NewClass` 헤더를 표시한다. 기본 상태는 Transform·클래스 그룹 펼침, 컴포넌트 그룹 접힘이다. 각 프로퍼티는 한 줄에 왼쪽 절반의 변수 이름과 오른쪽 절반의 값·초기값 복원 아이콘으로 표시한다. 복원 아이콘은 평소 기호만 표시하고 마우스를 올리면 배경이 나타난다. 펼친 그룹은 배경 박스·테두리로 전체 범위를 감싼다. 그룹을 접어도 값은 유지되며 편집 중 접으면 입력을 확정한다.

숫자 입력칸은 편집 전 상태에서 좌우로 드래그하면 값이 실시간으로 증감한다. 일반 숫자·위치·회전은 1px당 1, 스케일과 Scale 스냅은 1px당 0.01이며 Shift는 1/10 감도로 조절한다. 4px 미만의 클릭 흔들림은 무시한다. 숫자 드래그 중에는 상대 마우스 모드로 커서를 숨겨 화면 경계 없이 조절하고, 입력칸의 `|`·문자 선택 하이라이트 없이 테두리만 강조한다. 해제하면 값을 확정하고 Escape·포커스 이탈·팝업 전환은 시작값을 복원한다. 이전 마우스 모드·표시 상태도 복원하며 원래 절대 모드였으면 클릭 위치로 돌아간다. 스냅 설정 저장은 해제 시 한 번만 수행한다. 클릭 후 편집 중인 입력칸에서는 기존 문자 선택 드래그를 유지한다.

인스턴스 종류는 원본 에셋 이름으로 `NewPrefab Instance`처럼 표시하고 Transform 헤더와 간격을 둔다. Prefab 문서는 부모 클래스 이름으로 `NewClass Prefab`처럼 표시한다. 에셋을 이동·이름 변경해도 ID의 현재 경로를 사용한다.

## 레벨 코드 연결

프로젝트 정보 파일의 `defaultLevelReference`는 기본 레벨의 ID를, 레벨 JSON의 `scriptReference`는 실행할 Lua의 ID를 저장한다. ID의 현재 경로는 메타에서 재구성한 프로젝트 인덱스로 찾는다. 새 파일은 버전 2이며 기존 버전 1의 경로 참조도 읽고 가져오기 시 등록된 파일의 ID로 전환한다.

```json
{
  "formatVersion": 2,
  "lobjects": [],
  "scriptReference": "12345678-1234-4234-8234-123456789abc"
}
```

`.level`은 배치 데이터, Lua는 레벨의 동작을 담당한다. 새 Level/LObject Lua는 파일명과 같은 지역 클래스 이름을 사용한다. 예를 들어 StartLevel.lua는 다음 테이블을 반환한다. Lua 식별자로 쓸 수 없는 문자는 밑줄로 보정하며 숫자 시작·예약어에는 Class_를 붙이고 한글만 있는 이름은 Level/LObject로 대체한다.

```lua
-- labo-script: level
local StartLevel = {}

function StartLevel.BeginPlay(world)
    -- Play 시작 시 Runtime World를 초기화한다.
end

function StartLevel.update(world, dt)
    -- 매 프레임 호출되며 dt는 초 단위다.
end

return StartLevel
```

Lua 첫 줄의 `-- labo-script: level` 또는 `-- labo-script: lobject`는 최초 가져오기 때 종류를 결정하는 힌트다. 표식 없는 기존 Lua는 Level Class로 분류한다. 가져온 뒤에는 `.lua.meta`의 `scriptKind`를 사용한다. 호환성을 위해 기존 저장 필드명과 헤더는 유지한다. 기존 클래스의 load·컴포넌트의 Load도 실행되며 새 BeginPlay와 함께 선언하면 BeginPlay만 호출한다. LObject Class 템플릿은 `BeginPlay(self, world)`·`update(self, dt)` 함수를 제공한다.

생성되는 Prefab은 다음 형태다. `definitionReference`는 선택한 LObject Class를 가리키며 부모가 없으면 생략한다. 빈 `overrides`는 원본 기본값을 유지한다. Asset Browser의 Prefab을 Scene View에 드래그해서 배치하면 새 인스턴스가 선택된다. Inspector에서 클래스·컴포넌트 값을 편집하고 Ctrl+S로 레벨을 저장한다. Prefab 자체를 선택하면 Prefab 기본값을 편집한다.

```json
{
  "formatVersion": 2,
  "definitionReference": "abcdef12-1234-4234-8234-123456789abc",
  "overrides": {}
}
```

**F5**는 Play/Stop이다. Play마다 코드 파일을 새로 읽고 Runtime World를 만든다. `BeginPlay`는 한 번, `update`는 매 프레임 LObject 업데이트 전에 호출한다. Stop은 Runtime 변경을 버리며 배치 데이터에 반영하지 않는다. 코드 오류는 에디터에 표시하고 Play를 시작하지 않거나 중지한다. 자동화 테스트 모드에서는 프로젝트 코드를 실행하지 않는다.

## Lua Class 상속과 프로퍼티

컴포넌트와 이미지·객체 참조의 선언 및 편집 예시는 [컴포넌트 사용법](docs/components.md)을 참고한다.

클래스는 일반 Lua 테이블을 반환한다. `extends`에는 같은 종류의 부모 `.lua.meta`의 `id`를 기록한다. ID를 사용하므로 부모 파일 이동·이름 변경에도 상속이 유지된다. 생략한 함수와 프로퍼티는 부모에게서 물려받으며, 자식 함수에서 `Child.super.BeginPlay(world)`처럼 부모 함수를 명시적으로 호출할 수 있다. 순환 상속·다른 종류의 부모·잘못된 선언은 오류다.

```lua
-- labo-script: level
local Child = {
    extends = "12345678-1234-4234-8234-123456789abc",
    properties = {
        speed = { type = "number", default = 100 },
        title = { type = "string", default = "Stage" },
        enabled = { type = "boolean", default = true },
    },
}

function Child.BeginPlay(world)
    if Child.super.BeginPlay then Child.super.BeginPlay(world) end
    print(world.properties.title)
end

return Child
```

인스펙터에서 `number`·`string`은 입력칸, `boolean`은 토글로 편집한다. 되돌리기 화살표 아이콘(↺)은 클래스 기본값으로 되돌린다. 상속받은 프로퍼티도 편집할 수 있고 자식에서 기본값을 재정의할 수 있으나 타입은 유지해야 한다. Level은 `propertyOverrides`, Prefab은 `overrides.properties`에 기본값과 다른 값만 저장한다. 부모 변경 시 새 클래스와 호환되는 값만 유지하고 **None**으로 해제하면 변경값을 비운다. Play에서는 Level의 `world.properties`, LObject의 `self.properties`로 최종 값을 읽는다. Runtime 변경은 에셋에 반영하지 않는다.

클래스 목록은 메타데이터만 읽지만, 프로퍼티 선언을 표시할 때는 선택한 클래스와 부모의 Lua 모듈을 로드한다. 모듈 최상위에는 선언만 두고 실제 게임 동작은 `BeginPlay`·`update`에 작성한다. 인스펙터 로드는 lifecycle 함수를 호출하지 않는다. 외부에서 클래스를 수정한 뒤에는 **Refresh** 또는 대상 문서 다시 열기로 선언을 갱신한다.

## 에셋 ID와 메타데이터

인스펙터의 선택 대상 이름과 Parent Class 라벨은 굵게 표시하고, 그룹 제목·프로퍼티 이름은 본문 글꼴로 표시한다. `-- labo-script: component` 또는 `.lua.meta`의 `scriptKind: "component"`도 가져오기·아이콘 분류에서 인식한다. Component Class의 생성 UI·부착·실행 모델은 아직 제공하지 않으며 Level·Prefab 부모 선택 목록에는 포함하지 않는다.

Assets·Sources의 일반 파일마다 이름 뒤에 `.meta`를 붙인 JSON을 둔다. ID는 여기만 원본으로 보관한다. 예를 들어 `StartLevel.lua.meta`는 다음 형태다.

```json
{
  "version": 1,
  "id": "12345678-1234-4234-8234-123456789abc",
  "scriptKind": "level"
}
```

프로젝트 전체의 경로 목록은 루트의 `asset-index.json` 하나다. `paths`에는 `ID → Assets/... 또는 Sources/...`만 모아 둔다. 파일을 옮겨도 Level·Prefab의 ID 참조는 그대로이며 목록의 경로만 바뀐다. 파일·폴더 이동은 원본과 메타를 함께 처리한다.

열기·Refresh에서 메타를 가져오고 인덱스를 다시 만든다. 캐시를 삭제하거나 손상시켜도 ID는 바뀌지 않는다. 중복·손상된 메타는 오류로 표시하며 새 ID로 덮어쓰지 않는다. 메타는 원본과 함께 Git에 보관하고 `asset-index.json`, 임시 이동 기록 `asset-move.json`은 Git에서 제외한다. 외부 도구로 이동할 때도 원본과 메타를 함께 옮긴 뒤 Refresh한다. 메타와 저장 임시 파일은 브라우저에 표시하지 않는다.

## 에디터 테마

에디터 글꼴은 동봉된 나눔스퀘어 라운드를 사용한다. 본문은 Regular 14px, 패널 제목·라벨은 실제 Bold 파일을 사용한다. 썸네일과 작은 Lua 표식도 같은 글꼴이며 시스템 설치·OS 글꼴 경로에 의존하지 않는다. 원본 글꼴과 저작권·라이선스는 [src/editor/fonts](src/editor/fonts/README.md)에 보관한다. 보기·부모 선택 드롭다운은 텍스트 오른쪽에 구분선과 별도 화살표를 표시한다.

테마는 게임 프로젝트와 별도로 에디터 소스/설치 폴더에서 관리한다. `src/editor/settings.json`의 `theme`를 바꾸고 에디터를 재시작하면 적용된다.

```json
{
  "version": 1,
  "theme": "default"
}
```

- `default`: [LÖVE 공식 홈페이지](https://love2d.org/)의 [CSS](https://love2d.org/style/style.css?b)·[박스 SVG](https://love2d.org/style/box.svg)를 참고한 전체 배경·패널 `#B1E3FA`, 뷰포트 배경 `#E0F4FC`, 짙은 제목 `#1B4D68`, 분홍 `#EA316E`·파랑 `#25AAE1` 강조색이다. `src/editor/theme.lua`에 내장되어 JSON 파일 없이도 동작한다.
- `atom-one-light`: [VS Code Atom One Light](https://github.com/akamud/vscode-theme-onelight/blob/master/themes/OneLight.json) 스타일의 밝은 회색 배경, 짙은 글자와 파란 강조색.

색을 직접 바꾸려면 아래처럼 `src/editor/themes/my-theme.json`을 만들고 설정에서 `"theme": "my-theme"`을 선택한다. 파일의 `colors`는 `#RRGGBB` 또는 알파를 포함한 `#RRGGBBAA` 색을 받는다. 일부 색만 지정해도 나머지는 코드에 내장된 기본 테마를 사용한다. 모든 색 항목은 `atom-one-light.json`을 참고한다.

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
| `viewportBackground` | 편집 뷰포트 패널 내부 바탕 |
| `panel`, `surface`, `button`, `input` | 패널·팝업 표면·버튼·입력칸 |
| `panelBorder`, `panelTitle` | 독립 패널의 외곽선·제목 |
| `text`, `textMuted`, `textDisabled` | 일반·보조·비활성 글자 |
| `border`, `focus`, `hover`, `selection` | 경계·포커스·호버·선택 상태 |
| `textSelection` | 입력칸의 선택 문자 하이라이트 |
| `error`, `overlay` | 오류와 모달 뒤 덮개 |
| `thumbnailBackground`, `iconBackground`, `iconBorder`, `iconText`, `folderTab`, `folderBody` | 썸네일·파일 아이콘·폴더 아이콘 |
| `assetLevel`, `assetPrefab`, `classLevel`, `classLObject`, `classComponent` | Level·Prefab·종류별 Lua Class의 아이콘 테두리와 텍스트 |
| `grid`, `axisX`, `axisY`, `origin`, `object`, `objectSelected`, `gameBackground` | 뷰포트 격자·축·디버그 표시·Game View 바탕 |

설정이나 선택된 테마가 없거나 잘못되면 코드의 기본 테마로 시작한다. 기본 테마 JSON은 읽지 않는다. 이미지 미리보기의 원래 색은 유지한다.

## 에디터 UI 구성

`src/editor/ui/`는 위젯 트리와 입력 전달을 관리한다. Core Runtime 및 LObject 생명주기와 분리된다.

```text
src/editor/ui/
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

기존 `src/editor/ui.lua`는 텍스트·버튼·입력칸 그리기 도우미로 유지한다. 에디터는 루트의 그리기·입력 메서드를 호출하며, 계층·뷰포트·인스펙터는 각각 Canvas 안의 콘텐츠 위젯으로 연결된다. 에셋 브라우저는 내부에 폴더 트리·경로·파일 영역·드롭다운 슬롯을 가진 Canvas다. 폴더 트리와 경로·파일 목록은 간격을 둔 독립 패널로 표시하며, 파일 목록 패널은 뷰포트 배경색을 공유한다. 내부 모듈명은 `asset_browser.lua`를 유지한다. 확장자별 플러그인 등록 API는 아직 제공하지 않는다.
## 패널 여백 조절

일반 버튼의 폭은 텍스트 폭에 `UI.metrics.buttonPaddingX`를 좌우로 더해서 계산한다. 기본은 좌우 각각 10px이며, 버튼 사이 간격은 `buttonGap`(기본 8px)이다. 에셋 브라우저 도구·다이얼로그·프로젝트 시작 화면·인스펙터의 동작 버튼에 적용하며, 드롭다운 메뉴의 선택 행과 입력칸은 목록·필드 폭을 유지한다. 표시와 클릭 영역은 같은 크기를 사용한다.

`src/editor/ui.lua` 상단의 `UI.metrics`를 수정하고 에디터를 다시 실행하면 공통 패널 여백을 바꿀 수 있습니다. `titlePaddingX`·`titlePaddingY`는 패널 경계에서 제목까지의 좌측·상단 거리, `titleFontSize`는 제목 크기입니다. `contentPaddingX`는 본문 좌측 여백이며, `contentPaddingY`는 제목 아래 콘텐츠에 추가하는 상단 여백입니다. 제목과 본문을 맞추려면 두 X 값을 같게 설정하세요. `selectionPaddingX`·`selectionPaddingY`는 선택 박스의 가로·세로 여백, `selectionRadius`는 모서리 반경입니다. 모든 수치는 픽셀 단위입니다.
