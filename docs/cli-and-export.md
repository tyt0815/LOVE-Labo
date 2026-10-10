# AI 작업용 CLI와 게임 Export

## 실행

먼저 `scripts/packageEditor.ps1`로 배포물을 만든다. 콘솔 출력과 종료 코드를 받는 자동화에서는 `Labo-cli.exe`를 사용한다. `--cli`는 창·폰트·에디터 UI를 초기화하지 않는다.

```powershell
.\build\windows\Labo-cli.exe --cli help
.\build\windows\Labo-cli.exe --cli project create --parent D:\Games --name MyGame
.\build\windows\Labo-cli.exe --cli class create --project D:\Games\MyGame --name Enemy --type lobject
.\build\windows\Labo-cli.exe --cli prefab create --project D:\Games\MyGame --name EnemyPrefab --class Sources/Enemy.lua
.\build\windows\Labo-cli.exe --cli level create --project D:\Games\MyGame --name StartLevel
.\build\windows\Labo-cli.exe --cli project set-default --project D:\Games\MyGame --level Assets/StartLevel.level
.\build\windows\Labo-cli.exe --cli instance add --project D:\Games\MyGame --prefab Assets/EnemyPrefab.prefab --x 100 --y 200
.\build\windows\Labo-cli.exe --cli instance get --project D:\Games\MyGame --instance 1
.\build\windows\Labo-cli.exe --cli instance set --project D:\Games\MyGame --instance 1 --property transform.x --value-json 120
.\build\windows\Labo-cli.exe --cli export --project D:\Games\MyGame --output D:\Games\MyGame\Build\Game.love
```

CLI가 만든 클래스 파일에 게임 코드를 직접 작성한다. Sprite 등의 컴포넌트 부착은 기존처럼 클래스의 `build`에서 `self:addComponent(...)`로 선언한다. CLI는 생성·메타데이터·배치·저장 규칙을 처리하고 별도의 게임 코드 언어를 도입하지 않는다.

## 명령 계약

`level view --project D:\Games\MyGame --width 800 --height 600 --x 100 --y 50`은 기본 카메라와 Canvas 범위 및 해당 월드 좌표의 화면 위치를 반환한다. `--space screen`은 화면 좌표를 월드 좌표로 변환한다. beginPlay에서 지정하는 카메라 전환까지 검증하려면 런타임을 실행하는 `level pointer`를 사용한다.

`level pointer`에도 `--space screen --width 800 --height 600`을 지정할 수 있다. 이때 X/Y는 뷰포트 좌측 상단을 (0, 0)으로 하는 화면 좌표이며 카메라와 Canvas를 함께 판정한다. 기본 `--space world`는 기존 월드 좌표 입력을 유지한다. width/height 기본값은 1280/720이다. `class create --parent CameraComponent`, `RectComponent`, `CanvasComponent`도 지원하며 일반 컴포넌트처럼 코드로 부착한다. 위치·카메라 zoom·정렬 순서·fillParent는 기존 `instance set`과 `prefab set`으로 수정한다.

게임 클릭을 파일 변경 없이 검증하려면 `level pointer --project D:\Games\MyGame --event down --x 0 --y 0`을 사용한다. X/Y는 월드 좌표이고 버튼 기본값은 1이다. 여러 입력은 `--events-json '[{"kind":"down","x":0,"y":0},{"kind":"up","x":1000,"y":1000}]'`으로 전달한다. JSON 요청에서는 `events` 배열을 사용할 수 있다. 임시 런타임의 beginPlay 이후 입력을 전달하며 update는 자동 실행하지 않는다. 이미지 기반 영역도 판정하며 결과의 `events`에서 소비 여부·대상을, `instances`에서 최종 프로퍼티를 확인한다. 명령이 종료되면 캡처를 해제하고 원본 레벨은 유지한다.

Component Class 생성 예: `Labo-cli.exe --cli class create --project D:\Games\MyGame --name Visual --parent SpriteComponent`. 반환한 에셋 ID를 `LObject:addComponent` 또는 `setRootComponent`에 넘긴다. `--type component`만 지정하면 LObjectComponent를 부모로 생성한다. 사용자 Component Class를 `--parent`로 지정하여 재상속할 수도 있다. 부착 계층과 선택적 프로퍼티 `group` 문법은 [컴포넌트 사용법](components.md)에 설명한다.

| 명령 | 주요 인자 | 동작 |
|---|---|---|
| `project create` | `--parent`, `--name` | 프로젝트·필수 폴더 생성 |
| `project info` | `--project` | 에셋 경로·ID·종류, 기본 레벨 조회 |
| `project set-default` | `--project`, `--level` | 기본 레벨 지정 |
| `class create` | `--project`, `--name`, 선택 `--type`/`--parent` | `level`/`lobject`/`component` 템플릿과 메타데이터 생성. `--parent`는 부모 Lua ID·경로 또는 내장 LObjectComponent·SceneComponent·BoundsComponent·RectComponent·CanvasComponent·CameraComponent·RenderComponent·SpriteComponent·PointerComponent이며 종류를 자동 결정한다. 지정한 `--type`이 부모와 다르면 거절한다. |
| `prefab create` | `--project`, `--name`, 선택 `--class` 또는 `--instance`/`--level` | `--class`에 LObject 클래스 또는 부모 Prefab ID·경로를 지정한다. `--instance`는 지정 레벨(생략 시 기본 레벨)의 루트와 자손을 현재 값으로 캡처한다. 외부 객체 참조는 거절한다. |
| `prefab get/set` | `--project`, `--prefab` | 프로퍼티·컴포넌트 기본 override 조회/수정 |
| `level create` | `--project`, `--name`, 선택 `--class` | 레벨 생성 |
| `level get/set` | `--project`, 선택 `--level` | 레벨 데이터와 선언 프로퍼티 조회/수정 |
| `level pointer` | `--project`, 선택 `--level`, `--event`, `--x`, `--y`, `--button`, `--dx`, `--dy`, `--events-json` | beginPlay를 실행한 임시 런타임에 월드 좌표 포인터 입력을 전달하고 소비 여부·대상·최종 객체 프로퍼티를 반환한다. 레벨 파일은 변경하지 않는다. |
| `level view` | `--project`, 선택 `--level`, `--width`, `--height`, `--space`, `--x`, `--y` | 카메라·Canvas 범위와 투영 배율을 조회한다. 좌표가 있으면 world→screen 또는 screen→world 변환 결과도 반환한다. beginPlay는 실행하지 않는다. |
| `instance add` | `--project`, `--template` (호환: `--prefab`), 선택 `--level`, `--x`, `--y`, `--parent` | LObject Lua 클래스 또는 Prefab을 레벨에 배치. 부모 authoring ID 지정 시 X/Y는 부모 기준 상대값이다. |
| `instance get/set` | `--project`, `--instance`, 선택 `--level` | 인스턴스 조회/수정 |
| `instance reparent` | `--project`, `--instance`, 선택 `--level`, `--parent` | 월드 위치를 유지하며 부모 변경. `--parent` 생략 또는 JSON `false`는 최상위로 분리한다. |
| `export` | `--project`, 선택 `--level`, `--output` | 독립 실행 게임 `.love` 생성 |

생성 명령의 `--folder`는 프로젝트 상대 경로이며 기본은 `Sources`/`Assets`이다. `--class`를 생략한 Prefab·레벨은 내장 클래스를 사용한다. 참조 인자는 에셋 ID와 프로젝트 상대 경로를 지원한다. `--level` 생략 시 프로젝트의 기본 레벨을 사용한다. `--output` 생략 시 프로젝트의 `Build/Game.love`를 생성한다.

수정 명령에는 `--property`와 값이 필요하다. 이름은 `speed`, `sprite.x`, `sprite.image` 또는 `transform.x`, `transform.rotationX`, `transform.rotationY`, `transform.rotation`, `transform.scaleX` 등이다. `--value-json`은 숫자·불리언 등 JSON 값을 받는다. 문자열은 `--value`로 그대로 전달할 수 있다. 다른 인스턴스 참조는 같은 레벨의 authoring ID이며 해제 값은 JSON `false`이다. 이미지는 에셋 ID 또는 경로를 사용하며 실제 이미지 디코딩도 검사한다.

`type = "prefab"` 프로퍼티도 `prefab set`·`instance set`·`level set`으로 수정한다. 값은 Prefab ID·상대 경로 또는 해제용 JSON `false`이고, ID로 정규화하며 해당 에셋의 부모 체인을 검증한다. 게임 소스에서 이 값을 [spawnLObject](runtime-spawn.md)에 넘겨 런타임 객체를 만들 수 있다.

## 추가 편집 명령

`help`는 명령 목록, JSON 요청 예제, Prefab 경로와 다중 선택 입력 안내를 반환한다. 아래 명령도 공통 `--project`를 받는다.

| 명령 | 인자·동작 |
|---|---|
| `project validate` | 모든 클래스·Prefab·레벨을 검사. `valid`, `checked`, 에셋별 `errors` 반환. 오류가 있어도 진단 요청 자체의 JSON `ok`는 true다. |
| `class list` | 선택 `--type lobject/level/component` |
| `class get` | `--class`: 원본 소스, 종류, 스키마, 부모, revision 조회 |
| `class set-source` | `--class`, `--source`: 전체 Lua 소스를 검증 후 교체. 기존 메타의 클래스 종류는 유지. 긴 코드는 JSON 요청 파일 권장 |
| `folder create` | `--folder`, `--name` |
| `asset list` | 선택 `--folder`(기본 Assets): 폴더·파일 목록 |
| `asset get` | `--asset`: 경로·ID·메타·파일 revision |
| `asset move` | `--asset`, `--destination`: 이름을 포함한 최종 상대 경로 |
| `asset rename` | `--asset`, `--name`: 확장자는 자동 유지 |
| `asset delete` | `--asset`: 폴더면 자손 전체 삭제. 프로젝트 루트·기본 레벨 보호. CLI Undo는 없음 |
| `asset copy` | `--asset`, 선택 `--folder`, `--name`: 단일 파일 복사·새 ID. 같은 Assets/Sources 루트 안에서 사용 |
| `asset import` | `--input` 외부 파일 경로, 선택 `--folder`, `--name`: 단일 파일 가져오기. 기존 파일·메타는 덮어쓰지 않음 |
| `instance list` | 선택 `--level`: 전체 계층의 레코드·깊이·월드 Transform |
| `instance duplicate/delete` | `--instance` 또는 `--instances 1,2,3`. 선택 루트와 자손에 적용, 부모·자식 동시 선택은 중복 처리하지 않음 |
| `instance rename` | `--instance`, `--name` |
| `instance reset` | `--instance`, `--property`: 현재 유효 기본값으로 초기화. `transform.x` 등도 지원 |
| `level reset` | `--property`: 레벨 선언 기본값으로 초기화 |
| `level set-parent` | `--parent`: Level Lua ID/경로 또는 `None` |
| `level validate` | build·참조 구성까지 검사. beginPlay는 실행하지 않음 |
| `prefab tree` | `--prefab`: 노드 경로·부모·원본·Transform 목록 |
| `prefab get/set/reset` | `--prefab`, 선택 `--node`(기본 root). set/reset은 `--property` 추가. object 값은 `root/o1` 같은 노드 경로도 지원 |
| `prefab set-parent` | `--prefab`, 선택 `--node`, `--parent` 또는 `None`. None은 기본 LObject |
| `prefab child add` | `--prefab`, 선택 `--node`(추가할 부모), `--template`(클래스/Prefab) 또는 `--instance`/`--level`. 원본 생략은 기본 LObject |
| `prefab child rename` | `--prefab`, `--node`, `--name` |
| `prefab child remove` | `--prefab`, `--node`: 자손 포함 제거. 계층 밖에서 해당 가지를 참조하면 참조 수정 전까지 거절 |

`instance add`의 원본도 생략하면 기본 LObject가 된다. `instance reparent`는 다중 `instances`도 받으며 부모 생략 또는 JSON false는 분리한다. 다중 IDs는 JSON의 `"instances": [1, 2]`로 전달할 수 있다. Prefab 변경 응답의 `node`는 새로 추가하거나 편집한 경로이고 `nodes`의 가상 ID는 해당 조회에서만 사용한다. 지속적인 참조 입력은 노드 경로를 사용한다.

문서·소스·파일 수정은 선택적인 `revision`을 검사한다. 폴더에는 바이트 revision을 제공하지 않는다. 검증에 실패한 레벨·Prefab·소스 편집은 파일을 저장하지 않는다. GUI에 열린 문서는 먼저 저장하고 닫는다. CLI 명령은 GUI Undo/Redo 기록과 연결되지 않는다. 프로젝트 검증에서는 사용자 클래스의 모듈 로드와 build가 실행되므로 해당 코드 자체의 부수 효과까지 복구한다는 의미는 아니다.

```json
{"command":"prefab.child.add","project":"D:/Games/MyGame","prefab":"Assets/PF_Enemy.prefab","node":"root","template":"Sources/Weapon.lua"}
```

```json
{"command":"prefab.set","project":"D:/Games/MyGame","prefab":"Assets/PF_Enemy.prefab","property":"target","value":"root/o1"}
```

## JSON 요청과 응답 형식

복잡한 문자열·한글·쉘 인용 문제를 피하려면 에이전트가 UTF-8 JSON 요청 파일을 작성하는 방식이 적절하다.

```json
{
  "command": "instance.set",
  "project": "D:/Games/MyGame",
  "instance": 1,
  "property": "title",
  "value": "AI가 만든 적 오브젝트"
}
```

```powershell
.\build\windows\Labo-cli.exe --cli --request request.json --result response.json
```

표준 출력에는 `{"version":1,"ok":true,"result":...}` 또는 `{"version":1,"ok":false,"error":"..."}`를 반환한다. 성공 종료 코드는 0, 실패는 1이다. 선택적 `--result`는 동일한 응답을 파일에도 쓴다. JSON 요청의 명령은 `instance.set`처럼 점으로 연결한다. 값은 문자열·숫자·불리언의 실제 JSON 타입을 사용한다.

문서 조회 결과에는 SHA-256 `revision`을 제공한다. 수정 요청에 같은 `revision`을 보내면 오래된 조회 결과로 덮어쓰는 작업을 거부한다. 실패한 검증은 원본 레벨을 저장하지 않는다. Cli 작업은 프로젝트 루트의 `.labo-cli.lock`으로 서로 직렬화하며 종료 시 해제한다. 강제 종료로 남은 잠금은 실행 중인 CLI가 없는지 확인한 후 제거한다.

현재 CLI와 열린 GUI 문서 사이의 자동 동기화는 없다. GUI에서 해당 문서를 저장하고 닫은 뒤 CLI로 수정하고, 작업 후 다시 열어야 한다. Cli 잠금은 다른 CLI와의 충돌을 막으며 GUI의 미저장 메모리 상태를 보호하지 않는다.

## 게임 Export

GUI에서는 **Ctrl+Shift+E**로 현재 레벨을 `.love`로 Export한다. Inspector 편집 값은 확정하며 미저장 Prefab 초안도 패키지에 포함하여 Play와 같은 값으로 실행한다. Export는 편집용 원본 파일을 저장하거나 dirty 상태를 변경하지 않는다. CLI에서는 디스크의 기본 레벨이나 지정한 `--level`을 사용한다.

게임 패키지에는 `core/`, `project/`, `runtime/`, 공개 `Engine.lua`, 프로젝트 Sources·Assets, ID/경로/종류 매니페스트와 게임 전용 `main.lua`·`conf.lua`만 포함한다. 에디터·테스트·사용자 설정은 포함하지 않는다. 편집용 메타데이터 파일은 복사하지 않고 매니페스트에서 ID 매핑을 유지한다. 초기 Export는 의존 에셋만 추려내지 않고 등록된 프로젝트 파일 전체를 담는다.

```powershell
& 'C:\Program Files\LOVE\love.exe' D:\Games\MyGame\Build\Game.love
```

게임은 LÖVE 11.5가 필요하다. 독립 실행 게임 EXE·설치 프로그램은 이번 범위에 포함하지 않는다. 게임 호스트는 시작·update·렌더링 오류를 잡아 오류 화면을 표시하고, Editor Play와 같은 클래스·컴포넌트·참조·beginPlay 초기화 로직을 사용한다. 운영체제·드라이버나 네이티브 라이브러리 오류까지 복구한다는 계약은 아니다.

## 복구와 검증

유효한 프로젝트를 열 때 Assets·Sources가 없으면 생성한다. 같은 이름의 파일·링크, 권한 오류, 손상된 프로젝트 JSON은 덮어쓰지 않고 오류를 반환한다. 삭제된 폴더 안의 에셋·클래스 자체를 복원하지는 않는다. 시작 화면의 프로젝트 열기 콜백 오류도 에디터 전체 종료 대신 화면의 오류로 남긴다.

```powershell
.\scripts\verifyCliExport.ps1
```

위 명령은 에디터를 패키징하고 CLI로 임시 프로젝트·클래스·Prefab·레벨·인스턴스를 생성한다. 숫자·불리언·문자열·다른 인스턴스 참조·컴포넌트 값을 수정하고 게임을 Export한다. 게임 호스트를 실행해 beginPlay·update·이미지 렌더링과 참조 해석, 에디터 미포함을 검사한다. beginPlay·update·렌더링에 의도적인 오류를 넣은 패키지도 실행하여 오류가 격리되는지 확인한 뒤 예제 프로젝트 코드를 복원한다. 결과는 `build/cli-export-<고유값>/Game.love`, `game-report.json`과 오류별 보고서에 남는다.
