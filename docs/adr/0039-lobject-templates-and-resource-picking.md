# 0039. LObject 생성 템플릿과 리소스 스포이드

- 상태: 채택
- 후속: Prefab 계층의 대상 추가와 이후 드래그 요청 검토 지침은 [ADR 0041](0041-inspector-picking-over-drag-exceptions.md)로 확장한다.
- 날짜: 2026-10-09
- 부분 대체: [ADR 0033](0033-prefab-spawn-and-resource-inspector.md)의 Prefab 전용 참조, Inspector 리소스 드롭, 드래그 중 Inspector 유지, 찾기의 선택 동작
- 유지: 단일 LObject Prefab 형식, Core의 파일 해석 금지, authoring/runtime 상태 분리

## 배경과 제약

Lua 클래스의 기본값과 Prefab의 override 모두 런타임 생성의 원본으로 사용할 필요가 있다. 일반 에셋 클릭은 Inspector 탐색이며, 리소스 지정 때문에 드래그에 별도 선택 예외를 두면 폴더 이동·배치와 의미가 충돌한다.

## 대안과 판단 기준

- 클래스마다 디스크 Prefab을 만들면 불필요한 에셋과 동기화 책임이 생긴다.
- 실제 기본 객체를 공유하면 사용자 상태·컴포넌트가 생성 객체 사이에서 공유될 수 있다.
- 리소스 드래그 중 Inspector를 고정하면 일반 클릭의 의미와 달라진다. 지정 모드를 명시하는 스포이드가 더 분명하다.

## 결정 및 근거

`lobjectTemplate`은 LObject Lua 클래스 또는 Prefab의 에셋 ID를 저장한다. 기존 `prefab` 선언은 호환 별칭이다. `world:spawnLObject`와 CLI `instance.add --template`은 두 종류를 지원하며 기존 `--prefab`도 유지한다. 클래스 기본 생성 정의는 World 생성기의 메모리 캐시에 보관하지만 실제 객체·컴포넌트는 매번 새로 구성한다. 캐시는 World마다 분리된다. Level·Component 클래스는 생성 템플릿이 아니다.

이미지·생성 템플릿·Parent Class는 드롭다운과 스포이드를 제공한다. 템플릿은 에셋 또는 배치된 인스턴스의 직접 원본을 사용한다. Parent Class는 해당 종류와 순환을 검증한다. 객체 참조는 현재 레벨 인스턴스만 받는다. 잘못된 선택은 오류를 보여주고 모드를 유지하며 성공·Esc·우클릭·포커스 이탈·Play·문서 전환은 종료한다.

일반 에셋 클릭과 드래그는 클릭한 에셋으로 Inspector를 전환한다. Inspector 필드에 리소스를 드롭하지 않는다. 찾기는 폴더 탐색·스크롤·일시 강조만 수행하고 선택과 Inspector를 바꾸지 않는다. 인스턴스 찾기는 프레이밍과 일시 강조를 수행한다.

```text
WorldLoader → PrefabSpawner → LObjectTemplate → ObjectDefinition  (의존)
World → 새 LObject → 새 컴포넌트                              (포함)
EditorApp → 스포이드 상태 / Inspector / AssetBrowser           (포함)
스포이드 상태 → 검증된 에셋 ID 또는 레벨 인스턴스 ID           (참조)
```

## 예상 결과

- 긍정: Lua 기본값과 Prefab override를 동일한 생성 API로 사용하고, 선택과 리소스 지정의 의미가 분명해진다.
- 부정: 캐시된 정의는 같은 Play 세션 중 소스 파일 변경을 다시 읽지 않는다. 스포이드에는 한 번의 명시적 모드 진입이 필요하다.
- 중립: 계층 전체를 직렬화하는 Prefab 확장은 별도 결정으로 남긴다. 파일 형식과 기존 ID는 유지한다.
