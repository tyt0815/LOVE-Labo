# 0089. 가이드와 ADR로 문서를 일원화한다

- 상태: 채택
- 날짜: 2026-10-16
- 확장: [ADR 0048](0048-user-guides-and-project-agent-instructions.md)의 사용자 가이드
- 대체: 삭제한 LOVE_Labo_Design.md를 단일 설계 기준으로 지정하던 문서 정책

## 배경과 제약

기능 설명이 docs 루트와 guide에 나뉘고 초기 Design에 폐기한 Component 구조와 최신 계약이 함께 남았다. 사용자와 AI가 서로 다른 문서를 현재 기준으로 오해할 수 있다. 사용법은 가이드, 설계 이유와 변경 이력은 ADR에 기록한다는 원래 구분으로 정리한다.

## 대안과 판단 기준

- Design을 계속 갱신하면 ADR·가이드와 같은 내용을 반복하고 현재/과거 모델이 다시 섞인다.
- 별도 architecture.md와 development 디렉터리를 만들면 문서 종류와 진입점이 늘어난다. 별도 총괄 문서를 만들지 않는다.
- 초기 설계를 통째로 보존하기 위해 archive를 추가하면 오래된 설명이 검색에 남는다. 과거 원문은 Git 이력으로 보존하고 현재 문서에서는 제거한다.

## 결정 및 근거

1. 사용자·API·CLI·빌드·검증·문서 유지보수 안내는 모두 docs/guide에 둔다. 개발자 안내도 가이드의 한 종류다. ADR 본문은 docs/adr, 목차는 docs/adr.md, 사이트 첫 페이지는 docs/index.md에 둔다. requirements.txt와 이미지·스타일 등 사이트 빌드 자료는 유지한다.
2. components 설명은 현재 lua-api·objects 가이드에, selection-and-hierarchy는 editor·assets 가이드에 통합한다. 실제 API 이름과 동작을 확인하고 sortingOrder, matchViewport, 루트 SceneComponent, Script의 build 등 폐기한 설명을 현재 계약으로 고친다.
3. LOVE_Labo_Design.md는 삭제한다. Lua의 게임 동작 책임, Core → Editor 의존 금지, 편집/실행 상태 분리, 공용 로딩·검증, 데이터 보존 원칙은 AGENTS.md에 보존한다. 구체적인 설계 계약은 아래 관련 ADR과 최신 대체 결정을 따른다.
4. 가이드는 현재 사용하는 법을 설명하고 ADR은 당시 배경·대안·결정·결과를 기록한다. 이전 ADR의 폐기된 API 설명을 현재처럼 다시 쓰지 않으며 상태·후속 대체 관계로 구분한다. 이동한 링크와 사이트 목차는 함께 갱신한다.

## 현재 원칙을 구체화하는 결정

- [0050 부착 Script와 Assets](0050-attached-scripts-and-unified-assets.md): LObject는 Transform·자손·부착 Script를 소유한다.
- [0058 플러그인](0058-plugins-and-mounted-assets.md): 제공 편의 기능도 일반 플러그인으로 구현한다.
- [0028 공용 로딩](0028-agent-cli-and-standalone-game-export.md): GUI·CLI·게임은 공용 프로젝트/런타임 계약을 사용하고 Editor를 게임에 포함하지 않는다.
- [0040 초안과 저장](0040-prefab-drafts-and-save-all-review.md): 초안과 Runtime 상태를 구분하고 명시적으로 저장한다.
- [0085 공개 투영·배치·입력](0085-public-projection-layout-and-input.md): Core는 제공 카메라·UI 스크립트의 전용 표식을 해석하지 않는다.
- [0086 프로젝트 저장 ID](0086-project-save-identity.md), [0087 객체 유지 전환](0087-carried-objects-across-levels.md), [0088 Lua 빌드·게임 CLI](0088-project-lua-build-and-game-cli.md): 최근 외부 API·저장·배포 계약을 따른다.

## 예상 결과

- 긍정: 현재 사용법과 결정 이력을 구분하고 중복·폐기 API 설명을 줄인다. 문서 추가 위치가 명확하다.
- 부정: 기존 공개 문서 URL의 일부가 바뀐다. 저장소의 링크와 목차는 새 위치로 갱신하지만 외부 북마크는 새 가이드 경로로 변경해야 한다.
- 중립: 제품 코드·API·데이터 형식은 바꾸지 않는다. 삭제한 초기 설계의 원문은 Git 이력에 남는다.
