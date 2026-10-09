# LÖVE Labo Development Notes

- Target: LÖVE 11.5 + LuaJIT / Lua 5.1.
- Product source and bundled resources live in `src/`; run with `love src`.
- Run tests with `love src --test` (repository `tests/` is loaded only in test mode).
- `docs/LOVE_Labo_Design.md` is the source of truth for architectural direction and invariants.

## 코드 컨벤션

- 클래스 역할의 테이블과 파일 이름: `PascalCase`
- 변수와 함수: `camelCase`
- 상수: `UPPER_SNAKE_CASE`
- 들여쓰기: 공백 4칸
- 한 파일은 한 가지 책임만 가진다.

Lua 클래스·모듈 이름과 require 경로는 파일명의 대소문자를 일치시킨다. 함수형 모듈도 제품 소스에서는 PascalCase 파일명을 사용한다. 테스트 사례 모음과 작업 스크립트는 camelCase 파일명을 사용한다.
LÖVE가 요구하는 `main.lua`·`conf.lua`, 프레임워크 콜백·메타메서드, 표준 라이브러리·FFI·외부 API의 이름과 계약은 예외로 유지한다. 변경할 수 없는 외부 이름에 프로젝트 컨벤션을 강제로 적용하지 않는다.

## Inspector 대상 지정

Inspector 필드나 Prefab 계층에 에셋·인스턴스를 드래그앤드롭하자는 요청이 나오면, 일반 선택에 따른 Inspector 대상 전환 충돌을 먼저 설명하고 명시적인 스포이드 선택 모드를 제안한다. 드래그 중 Inspector 고정·이전 대상 복원 같은 예외를 바로 추가하지 않는다. [ADR 0041](docs/adr/0041-inspector-picking-over-drag-exceptions.md)을 확인하며, 사용자가 그 차이를 이해하고 다른 방식을 명시적으로 선택하면 결정을 재검토한다.
