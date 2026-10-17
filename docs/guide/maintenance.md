# 문서 빌드와 화면 캡처

`--capture-guide`는 PIE 런타임 Inspector·성능 창·미저장 초안 복구 선택 화면도 재현합니다. 해당 원본과 번호 표시는 [PIE 가이드](play-tools.md)에서 사용합니다.

안내 문서는 `docs/guide/`, 설계 결정 이력은 `docs/adr/`에 둡니다. 루트에는 첫 페이지·ADR 목차·문서 빌드 의존성만 두며 별도 설계 총괄 문서를 누적하지 않습니다. 현재 핵심 원칙은 저장소의 `AGENTS.md`, 구체적인 결정과 대체 관계는 [ADR 목차](../adr.md)에서 확인합니다. 개발 중 임시 동작을 모두 문서화하지 않고, 커밋 전에 사용자 동작·UI·API·CLI가 변경됐는지 확인해 관련 가이드·예제·이미지를 같은 커밋에서 갱신합니다.

## 로컬 미리보기

```powershell
python -m pip install -r docs/requirements.txt
python -m mkdocs build --strict
python -m mkdocs serve
```

기본 테마는 무료 MkDocs readthedocs입니다. 사이드바 목차와 검색을 제공하며 생성 결과는 build/docs-site에 둡니다. 공개 문서는 [LÖVE Labo 사용자 가이드](https://tyt0815.github.io/LOVE-Labo/)에서 확인합니다. 2026-10-10 첫 배포에서 주요 문서·화면 이미지·검색 데이터의 공개 응답을 검증했습니다.

## 사용자 가이드 화면 캡처

`love src --capture-guide <새 절대 경로>`는 임시 예제 프로젝트로 실제 UI를 재현하고 PNG·report.json을 저장한 뒤 종료합니다. Project Browser의 카드·하단 정보, Project → Inspector 메뉴, 기본으로 접힌 그룹과 펼친 그룹, 스크립트 헤더 토글의 켜짐·꺼짐, 배경색 선택기와 편집 뷰포트 배경 예제도 포함합니다. `--theme default` 또는 `--theme atom-one-light`를 붙이면 설정 파일을 수정하지 않고 캡처에 사용할 테마를 선택합니다. 생략하면 현재 테마를 사용합니다. 기존 사용자 프로젝트와 최근 프로젝트 설정은 변경하지 않습니다.

```powershell
love src --capture-guide C:/Temp/LaboGuideCapture
python scripts/updateGuideImages.py C:/Temp/LaboGuideCapture
# 일부 화면만 갱신할 때
python scripts/updateGuideImages.py C:/Temp/LaboGuideCapture --only camera-details view-details script-context
```

두 번째 명령은 캡처 원본과 번호 표시를 추가한 가이드 이미지를 갱신합니다. 결과 화면을 확인한 뒤 관련 안내문과 함께 반영합니다.

## 네이티브 에디터 창 검증

Windows 11에서는 둥근 모서리 설정과 최대화·복원 후 설정 유지도 확인하고 `roundedCornersSupported`에 지원 여부를 기록합니다. `editor.png`는 에디터 콘텐츠 캡처이며 운영체제가 합성하는 외곽 모서리는 포함하지 않습니다.

다이얼로그가 열린 상태에서 창 제어 버튼의 우선 입력과 팝업 유지도 확인합니다. 크기 변경 후 `editor.png`를 현재 렌더링 크기로 저장하고, 저장된 PNG의 가로·세로 크기를 다시 검증합니다. SDL 크기뿐 아니라 실제 Windows 창 외곽과 클라이언트를 확인하며, 연결된 각 모니터에서 최대화·최소화 복원·재최대화 후 작업 표시줄 영역을 덮지 않는지 검사합니다. JSON의 `maximizedNativeBounds`·`maximizeTransitions`에 실제 외곽과 작업 영역을 기록합니다.

```powershell
love src --verify-window C:/Temp/LaboWindowVerification
```

새 출력 폴더에 `report.json`과 `editor.png`를 기록하고 종료합니다. 실제 Windows 창에서 제목 표시줄 제거, 메뉴바 이동 영역·크기 조절 영역·버튼 영역 판별, 최대화와 작업 표시줄 영역 보존, 복원·최소화·크기 변경을 검증합니다. 기존 프로젝트는 열거나 변경하지 않습니다. 배포판에서도 `Labo.exe --verify-window <새 출력 폴더>`로 실행할 수 있습니다.

캡처 원본은 `guide/images/original`, 주석 이미지는 `guide/images`에 보관합니다. 원·번호 표시는 SVG 오버레이로 만들며 원본 픽셀은 변경하지 않습니다. UI 배치가 바뀌면 updateGuideImages.py의 표시 위치와 관련 단계 설명을 실제 화면에 맞춰 함께 갱신합니다.

## 자동 배포

`.github/workflows/docs.yml`은 PR에서 strict 빌드를 검증하고 main에 push되면 GitHub Pages로 배포합니다. 저장소 Settings → Pages의 Source는 GitHub Actions를 사용합니다. 공개 저장소의 기본 github.io 주소에는 별도 도메인이 필요하지 않습니다.

배포 경로는 [GitHub Pages 공식 워크플로 안내](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)를 따릅니다. MkDocs 빌드는 [공식 배포 안내](https://www.mkdocs.org/user-guide/deploying-your-docs/)를 참고합니다.

## build 정리

`scripts/cleanBuild.ps1`은 알려진 테스트 프로젝트·임시 캡처·검증 경로를 미리 보여주고, `-Apply`를 지정하면 삭제합니다. 배포본 build/windows와 최신 검증 요약 build/verification-latest, 문서 캐시는 유지합니다. 조사 중인 결과는 `-Keep window-activation-check`처럼 build 바로 아래 이름으로 보존합니다. 알 수 없는 폴더와 링크가 있는 경로는 자동 삭제하지 않습니다. 커밋 전 검증 결과를 확인한 뒤 실행합니다.

## 게임 CLI 배포 검증

`./scripts/packageEditor.ps1 -verify` 뒤 `./scripts/verifyGameCli.ps1`를 실행합니다. 실제 배포 에디터에서 새 프로젝트·빌드 예제를 만들고 게임 CLI Export, 명령 스키마, 콘텐츠 수정과 실패 종료 코드, 창·오디오·World·Editor 미초기화, 배포 게임 EXE 직접 실행·프로젝트 conf.lua의 창 제목/크기/VSync 적용, Reload/Save와 같은 파일 재조회까지 검사합니다. 결과는 build/verification-game-cli-<고유값>/report.json에 기록합니다. 필요하면 `-editorExecutable <Labo-cli.exe 절대 경로>`를 지정합니다. 해당 배포 폴더의 원본 love.exe로 기존 .love 출력도 실행해 확인합니다.

## 에디터 CLI·게임 Export 검증

유효한 프로젝트를 열 때 Assets가 없으면 생성한다. 같은 이름의 파일·링크, 권한 오류, 손상된 프로젝트 JSON은 덮어쓰지 않고 오류를 반환한다. 삭제된 폴더 안의 에셋·클래스 자체를 복원하지는 않는다. 시작 화면의 프로젝트 열기 콜백 오류도 에디터 전체 종료 대신 화면의 오류로 남긴다.

```powershell
.\scripts\verifyCliExport.ps1
```

위 명령은 에디터를 패키징하고 실제 CLI로 스크립트·Prefab·레벨을 생성한다. 부착 순서, 초기화·업데이트, 포인터, 사용자 draw와 독립 게임 Export를 검증한다. 결과는 `build/cli-export-<고유값>/Game.love`와 `game-report.json`에 남는다.
