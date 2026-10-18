# Windows 에디터 패키징

PowerShell과 LÖVE 11.5 Windows 런타임이 필요하다. 저장소 루트에서 실행한다.

```powershell
.\scripts\packageEditor.ps1 -verify
```

다른 LÖVE 설치 경로나 출력 폴더를 사용할 수 있다.

```powershell
.\scripts\packageEditor.ps1 -loveDirectory 'D:\Tools\LOVE' -outputDirectory '.\build\windows' -verify
```

## 결과물

- `build/windows/Labo.exe`: LÖVE 실행 파일과 에디터 `.love` 패키지를 바이트 스트림으로 결합한 Windows 실행 파일
- `build/windows/Labo-cli.exe`: 같은 에디터 패키지의 콘솔 실행 파일. `--cli`에서 창 없이 JSON을 반환한다.
- `build/windows/love.exe`, `lovec.exe`: 게임·게임 CLI Export에 재사용하는 원본 런처. Labo.exe·Labo-cli.exe와 별개이며 함께 배포합니다.
- `build/windows/*.dll`: 같은 LÖVE 배포판의 런타임 라이브러리
- `build/windows/settings.json`, `themes/*.json`: 외부에서 수정 가능한 설정·테마
- `build/windows/license-love.txt`, `license-fonts.txt`: 런타임·폰트 라이선스

`Labo.exe` 단독 대신 `build/windows` 폴더를 함께 배포한다. 결합용 ZIP은 성공·실패 시 자동 삭제하며, 이전 빌드의 `Labo.love`와 `package-manifest.json`도 다시 패키징할 때 제거한다. 사용자 파일은 자동 삭제하지 않는다. 테스트·샘플 프로젝트·개발 문서는 패키지에 들어가지 않는다. 에디터·Core Lua, 클래스 템플릿, 폰트는 패키지에 들어가며 Lua 원문을 바이너리로 컴파일하거나 암호화하지 않는다.

## 실행과 설정

```powershell
.\build\windows\Labo.exe
.\build\windows\Labo.exe --project 'D:\Games\MyProject'
```

배포된 실행 파일은 작업 디렉터리에 관계없이 실행 파일 옆의 `settings.json`과 `themes/<이름>.json`을 읽는다. 수정 후 재시작하면 반영된다. 설정이 없거나 잘못된 경우 코드에 내장된 기본 테마로 돌아간다. 다시 패키징할 때 기존 외부 설정·테마는 덮어쓰지 않는다. 개발 중에는 `src/editor/settings.json`, `src/editor/themes/`를 사용한다. 스크립트는 `src` 내용물을 패키지 루트에 넣으므로 패키지 내부 모듈·리소스 경로는 그대로 유지한다.

스냅 설정은 기존 방식대로 LÖVE 사용자 저장 폴더의 `viewport-settings.json`에 저장한다. 설치 폴더에 쓰기 권한이 없어도 스냅 설정을 저장할 수 있다. LÖVE의 fused 실행에서는 소스 실행과 사용자 저장 폴더 위치가 다를 수 있다.

## 검증

`-Verify`는 생성한 `Labo.exe`를 소스 루트와 다른 작업 디렉터리(출력 폴더의 부모)에서 실행한다. `--verify-package <새 폴더>` 진단 모드가 외부 임시 프로젝트를 만들고 다음을 검사한다.

- fused 실행, 테스트·설정 제외, 폰트 포함, 외부 테마 적용
- 한글 프로젝트 경로에서 클래스·메타데이터·Prefab·레벨 생성, 시작 화면과 `--project` 열기
- 외부 이미지 로딩, 인스턴스 배치, Inspector 프로퍼티 수정·저장·재로딩
- 프로젝트 코드의 load, Play/Stop, Ui 그리기

검증 결과는 출력 폴더 옆 `verification-<고유값>/report.json`에 남고, 화면은 `preview.png`로 저장한다. 실패하거나 60초 안에 종료하지 않으면 스크립트가 오류를 반환한다. 기존 사용자 프로젝트·설정은 수정하지 않는다. 검증 프로젝트를 배포 폴더에 포함하지 않도록 출력 폴더의 부모에 보관한다.

AI용 CLI와 게임 EXE·.love Export 사용법은 [CLI와 게임 Export](cli-and-export.md)를 참고한다.

검증·캡처 후 커밋 전에는 `scripts/cleanBuild.ps1`로 대상을 확인하고 `-Apply`로 임시 산출물을 정리합니다. 실패 조사 중 결과는 `-Keep`으로 보존합니다. 최종 build/windows는 유지합니다.
