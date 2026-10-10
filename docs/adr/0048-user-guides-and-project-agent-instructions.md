# 0048. 사용자 가이드 사이트와 새 프로젝트 AI 안내

- 상태: 채택·구현·공개 배포 완료
- 날짜: 2026-10-10
- 관련: [ADR 0044](0044-expanded-authoring-cli.md), [ADR 0047](0047-level-main-camera-and-default-camera.md)

## 배경과 제약

사용자는 문서 작성을 에이전트에게 맡기고 실제 화면·주석 이미지를 적극 활용하기로 했다. AI는 공식 API를 확인해야 하며 인터넷 없이도 핵심 안내에 접근해야 한다. 커밋 전에 최종 기능과 문서를 함께 갱신한다.

## 대안과 판단 기준

GitHub Wiki는 별도 저장소라 코드와 문서의 같은 커밋 검토가 어렵다. 유료 테마·외부 문서 서비스 없이 기존 Markdown을 MkDocs 기본 테마로 빌드한다. 웹 URL만 제공하는 대신 로컬 안내·CLI help를 함께 제공한다. 임의 UI 그림 대신 실제 재현 가능한 화면 캡처를 사용한다.

## 결정 및 근거

docs/guide에 한국어 가이드를 작성하고 기존 API·CLI·설계 문서와 함께 MkDocs로 빌드한다. URL은 https://tyt0815.github.io/LOVE-Labo/ 이다. docs가 원본이며 build/docs-site는 생성물이다. Actions는 PR strict 빌드와 main push 후 Pages 배포를 구성한다. GitHub Actions 방식의 Pages 설정을 활성화했고 2026-10-10 첫 공개 배포를 검증했다. 이후 문서 변경도 main push의 strict 빌드와 Pages 배포를 거친다.

--capture-guide는 새 폴더의 예제 프로젝트에서 화면 5장을 캡처한다. updateGuideImages.py는 원본을 보관하고 번호·원 표시 SVG를 만든다. UI 변경 시 주석 좌표도 실제 화면을 보고 갱신한다.

새 프로젝트는 AGENTS.md와 Docs/EngineGuide.md를 제공한다. 공식·AI 문서 URL, development 버전과 LÖVE 11.5 계약, CLI 우선 사용, 코어 수정 금지, API 추측 금지를 명시한다. 기존 사용자 지침은 덮어쓰지 않는다. Docs와 AGENTS는 게임 Export에 포함하지 않는다.

## 예상 결과

- 긍정: 사용자와 AI가 실제 화면·API·CLI를 같은 문서 원본에서 확인한다.
- 부정: 이미지·주석도 유지보수 대상이다. development 문서는 실제 배포 엔진의 제공 API와 함께 확인해야 한다.
- 중립: 기본 github.io 주소를 사용하며 고정 버전 문서는 릴리스 정책에 맞춰 확장한다.
