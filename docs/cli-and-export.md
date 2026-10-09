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

Component Class 생성 예: `Labo-cli.exe --cli class create --project D:\Games\MyGame --name Visual --parent SpriteComponent`. 반환한 에셋 ID를 `LObject:addComponent` 또는 `setRootComponent`에 넘긴다. `--type component`만 지정하면 LObjectComponent를 부모로 생성한다. 사용자 Component Class를 `--parent`로 지정하여 재상속할 수도 있다. 부착 계층과 선택적 프로퍼티 `group` 문법은 [컴포넌트 사용법](components.md)에 설명한다.

| 명령 | 주요 인자 | 동작 |
|---|---|---|
| `project create` | `--parent`, `--name` | 프로젝트·필수 폴더 생성 |
| `project info` | `--project` | 에셋 경로·ID·종류, 기본 레벨 조회 |
| `project set-default` | `--project`, `--level` | 기본 레벨 지정 |
| `class create` | `--project`, `--name`, 선택 `--type`/`--parent` | `level`/`lobject`/`component` 템플릿과 메타데이터 생성. `--parent`는 부모 Lua ID·경로 또는 내장 LObjectComponent·SceneComponent·RenderComponent·SpriteComponent이며 종류를 자동 결정한다. 지정한 `--type`이 부모와 다르면 거절한다. |
| `prefab create` | `--project`, `--name`, 선택 `--class` | `--class`에 LObject 클래스 또는 부모 Prefab ID·경로를 지정한다. |
| `prefab get/set` | `--project`, `--prefab` | 프로퍼티·컴포넌트 기본 override 조회/수정 |
| `level create` | `--project`, `--name`, 선택 `--class` | 레벨 생성 |
| `level get/set` | `--project`, 선택 `--level` | 레벨 데이터와 선언 프로퍼티 조회/수정 |
| `instance add` | `--project`, `--prefab`, 선택 `--level`, `--x`, `--y`, `--parent` | 레벨에 배치. 부모 authoring ID 지정 시 X/Y는 부모 기준 상대값이다. |
| `instance get/set` | `--project`, `--instance`, 선택 `--level` | 인스턴스 조회/수정 |
| `instance reparent` | `--project`, `--instance`, 선택 `--level`, `--parent` | 월드 위치를 유지하며 부모 변경. `--parent` 생략 또는 JSON `false`는 최상위로 분리한다. |
| `export` | `--project`, 선택 `--level`, `--output` | 독립 실행 게임 `.love` 생성 |

생성 명령의 `--folder`는 프로젝트 상대 경로이며 기본은 `Sources`/`Assets`이다. `--class`를 생략한 Prefab·레벨은 내장 클래스를 사용한다. 참조 인자는 에셋 ID와 프로젝트 상대 경로를 지원한다. `--level` 생략 시 프로젝트의 기본 레벨을 사용한다. `--output` 생략 시 프로젝트의 `Build/Game.love`를 생성한다.

수정 명령에는 `--property`와 값이 필요하다. 이름은 `speed`, `sprite.x`, `sprite.image` 또는 `transform.x`, `transform.rotationX`, `transform.rotationY`, `transform.rotation`, `transform.scaleX` 등이다. `--value-json`은 숫자·불리언 등 JSON 값을 받는다. 문자열은 `--value`로 그대로 전달할 수 있다. 다른 인스턴스 참조는 같은 레벨의 authoring ID이며 해제 값은 JSON `false`이다. 이미지는 에셋 ID 또는 경로를 사용하며 실제 이미지 디코딩도 검사한다.

`type = "prefab"` 프로퍼티도 `prefab set`·`instance set`·`level set`으로 수정한다. 값은 Prefab ID·상대 경로 또는 해제용 JSON `false`이고, ID로 정규화하며 해당 에셋의 부모 체인을 검증한다. 게임 소스에서 이 값을 [spawnLObject](runtime-spawn.md)에 넘겨 런타임 객체를 만들 수 있다.

## JSON 요청과 응답

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

GUI에서는 **Ctrl+Shift+E**로 현재 레벨을 `.love`로 Export한다. Inspector 편집 값은 확정하며 Prefab에 미저장 변경이 있으면 먼저 저장하도록 안내한다. CLI에서는 기본 레벨이나 지정한 `--level`을 사용한다.

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
