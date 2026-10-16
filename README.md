# LOVE Labo

[사용자 가이드 원본](docs/index.md) · [가이드 사이트](https://tyt0815.github.io/LOVE-Labo/) · [AI 시작 페이지](docs/guide/ai.md)

새 레벨은 빈 상태로 생성됩니다. Camera와 View 스크립트를 부착해 화면 출력을 구성하며 레벨 전용 Main Camera 설정은 없습니다. 메인 화면·미니맵 구성은 [카메라와 화면 UI](docs/guide/camera-ui.md)를 참고하세요. 문서 사이트의 공개 배포 설정은 [문서 유지보수](docs/guide/maintenance.md)를 참고하세요.

LÖVE 11.5 + LuaJIT을 사용하는 2D 제작 에디터다. 현재 외부 프로젝트 생성·탐색은 Windows에서 지원한다.

제품 코드와 번들 리소스는 `src/`, 개발 테스트·샘플 프로젝트는 `tests/`, 문서는 `docs/`, 자동화는 `scripts/`, 생성된 배포물은 `build/`에 둔다. 패키징·CLI·게임 Export 사용법은 [패키징](docs/guide/packaging.md)과 [CLI·Export](docs/guide/cli-and-export.md)를 참고한다.

코드 컨벤션은 [AGENTS.md](AGENTS.md)를 따른다. 클래스·제품 모듈 파일은 PascalCase, 함수·변수는 camelCase, 상수는 UPPER_SNAKE_CASE다. 공개 API는 `require("Engine")`, `beginPlay`, `update`, `draw`, `getLocalBounds`, `spawnLObject`를 사용한다. 이전 대문자 API·소문자 모듈 경로를 사용하는 외부 프로젝트 코드는 새 표기로 갱신한다. 이름·들여쓰기·require 경로 검사: `python scripts/checkConventions.py`.

## 실행과 문서

- 제품 소스: src, 개발 실행: `love src`, 테스트: `love src --test`.
- 사용자 가이드: https://tyt0815.github.io/LOVE-Labo/ (개발 변경은 다음 문서 배포 때 반영).
- 로컬 가이드: [시작](docs/guide/getting-started.md), [Lua API](docs/guide/lua-api.md), [CLI와 Export](docs/guide/cli-and-export.md).
- 예제 프로젝트: tests/TestProject. 재생성: `python scripts/rebuildTestProject.py` (기존 폴더가 있으면 중단).
- 패키징 검증: `scripts/verifyCliExport.ps1`. 문서 빌드: `python -m mkdocs build --strict`.

## 현재 모델

LObject는 Transform과 자손 계층을 소유하며 Lua 스크립트를 여러 개 부착합니다. Prefab은 계층·부착 구성·값을 저장합니다. Prefab Inspector에서 스크립트를 추가·제거·정렬하고 인스턴스에서는 로컬 스크립트를 추가·제거·정렬하고 상속한 구성의 값만 재정의합니다. Lua 파일 자체는 오브젝트 생성 템플릿이 아닙니다.

프로젝트 에셋은 Assets로 통합했습니다. Sources는 충돌이 없을 때 Assets/Scripts로 이동하며 .meta ID를 유지합니다. 이전 컴포넌트 코드·Prefab은 자동 전환하지 않습니다. [ADR 0050](docs/adr/0050-attached-scripts-and-unified-assets.md)에 결정과 호환성 제한을 기록했습니다.

기본 Camera·Sprite·Pointer·Rect·Canvas는 부착 스크립트입니다. CLI는 script.*, prefab.script.*, level.simulate와 기존 계층·에셋 관리 명령을 제공합니다. 테스트의 이전 컴포넌트 계약은 tests/legacy에 보존했습니다.
