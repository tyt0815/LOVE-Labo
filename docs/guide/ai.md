# AI 에이전트의 시작 절차

프로젝트 문서와 코드 주석은 기본적으로 한국어로 작성하고, UI 이름과 API 이름은 영어로 유지합니다.

## 작업 순서

1. 프로젝트 루트의 `AGENTS.md`, `project.labo`, 로컬 안내를 읽습니다.
2. 엔진의 관련 [Lua API](lua-api.md)·[CLI 계약](../cli-and-export.md)을 확인합니다. 문서에 없는 API를 추측하지 않습니다.
3. `Labo-cli.exe --cli help`와 `project info`로 실제 제공 명령·에셋 ID를 조회합니다.
4. 클래스·Prefab·레벨·에셋 작업은 CLI를 우선 사용합니다. 긴 코드와 여러 인자는 UTF-8 JSON 요청 파일을 사용합니다.
5. GUI의 문서는 저장한 뒤 CLI를 실행하고, 수정 후 project validate 및 필요한 입력·Export 검증을 수행합니다.

## 재현 가능한 첫 레벨

```powershell
Labo-cli.exe --cli project create --parent D:/Games --name MyGame
Labo-cli.exe --cli level create --project D:/Games/MyGame --name L_Start
Labo-cli.exe --cli project set-default --project D:/Games/MyGame --level Assets/L_Start.level
Labo-cli.exe --cli level get --project D:/Games/MyGame
Labo-cli.exe --cli project validate --project D:/Games/MyGame
```

level create는 기본 Camera를 포함합니다. 자동화에서 빈 레벨이 필요하면 `--empty` 또는 JSON 요청의 `"empty": true`를 사용합니다. Main Camera는 다음처럼 변경하고 조회합니다.

```powershell
Labo-cli.exe --cli level set-camera --project D:/Games/MyGame --instance 1 --component camera
Labo-cli.exe --cli level view --project D:/Games/MyGame --width 1280 --height 720
Labo-cli.exe --cli level pointer --project D:/Games/MyGame --space screen --x 640 --y 360
```

set-camera의 instance를 생략하면 Auto로 초기화합니다. 여러 CameraComponent가 있으면 component 이름이 필수입니다. level view는 beginPlay 없이 구성·조회하고, level pointer는 beginPlay 후 입력을 실행합니다. 입력 콜백의 카메라 변경은 다음 이벤트에 반영됩니다.

## 작업 경계

프로젝트 Sources와 Assets를 수정하며 엔진 코어·배포 파일은 직접 수정하지 않습니다. .meta를 임의로 생성하거나 ID를 교체하지 않습니다. CLI 수정 응답의 revision을 후속 수정에 사용하면 외부 변경 충돌을 감지할 수 있습니다. GUI Undo는 CLI 변경을 되돌리지 않습니다.

웹 문서가 접근되지 않으면 프로젝트 `Docs/EngineGuide.md`와 CLI help를 사용합니다. 문서는 개발 버전이므로 배포 폴더의 엔진 버전 정보와 제공 API를 함께 확인합니다.
