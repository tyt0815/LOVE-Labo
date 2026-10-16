# 0074. Project·Level·Object에 같은 Script를 부착하고 화면 그리기를 분리한다

> 카메라·화면 공간·입력·배치 계약은 [ADR 0085](0085-public-projection-layout-and-input.md)에서 부분 대체한다.

> 순서 설정·표시는 [ADR 0084](0084-common-script-callback-order.md)에서 확장·부분 대체한다.

- 상태: 승인·구현
- 확장: [0050](0050-attached-scripts-and-unified-assets.md), [0069](0069-script-identity-and-editor-authored-attachments.md), [0071](0071-love-events-on-attached-scripts.md)
- 부분 대체: 0069의 World별 클래스 캐시를 Play 세션별 공유 캐시로 확장한다. 독립 Play·CLI 실행은 캐시를 공유하지 않는다.

## 배경과 제약

프로젝트·레벨마다 여러 관리 스크립트를 사용하고 다른 범위의 관리 인스턴스를 조회해야 한다. 사용자 코드가 기본 update 전파를 대신하는 방식은 채택하지 않는다. Labo의 초기화·자원 정리·렌더링·입력 계약과 Editor/CLI/Export의 실행 일관성을 유지한다. Level은 편집·저장 데이터이고 World는 실행 인스턴스다.

## 대안과 판단 기준

- ComponentScript·ProjectSingleton·LevelSingleton으로 타입을 나누면 같은 행동 정의를 범위별로 재사용하기 어렵다.
- 프로젝트 스크립트가 하위 update를 직접 진행하면 기본 사용에도 등록·제거·중복 실행 관리가 필요하다.
- 단일 draw 안에서 좌표계를 임의 전환하면 변환 복원과 객체 Transform 적용 여부가 불명확해진다.
- 공용 Script 부착과 내장 호출, 별도 drawScreen 콜백을 선택한다.

## 결정 및 근거

project.labo와 레벨 데이터에 선택적 scripts·scriptOverrides를 저장한다. UUID·이름·source와 override 형식은 Object와 같다. 기존 레벨 scriptReference·propertyOverrides와 load/update는 읽기·실행 호환으로 유지한다. 새 GUI에서는 공용 Script를 만들고 부착한다.

ScriptHost는 부착 저장소·조회·초기화·update·정리를 공유하는 모듈이다. LObject·World는 해당 메서드에 의존하고 프로젝트 실행 호스트는 ScriptHost 인스턴스다. LObject와 World 사이에 상속을 만들지 않는다. Script.owner는 실제 등록 대상이다. Script.getProject()는 프로젝트 실행 호스트, getWorld()는 소속 World를 반환하며 Project 부착에서는 현재 World를 동적으로 반환한다. World.getObjects()는 현재 객체의 목록 복사본을 반환한다.

모든 호스트는 getScriptById·getScriptByName·getScriptByClass·getScriptsByClass·getScriptOrder를 제공한다. 조회는 해당 호스트의 부착만 대상으로 하며 하위 범위로 전파하지 않는다. 클래스 비교가 유지되도록 하나의 Play 세션에서 Project·Level·Object·Spawn이 같은 클래스 로더를 사용한다.

Project 부착은 Play 시작부터 Stop까지 유지한다. Level 부착은 World마다 생성·정리한다. load는 Project → Level → Object, update와 일반 이벤트도 같은 범위 순서이며 같은 범위에서는 부착 순서다. 기존 레벨 콜백 update는 새 Level 부착 뒤, Object 앞에서 실행한다. Object는 기존 부모·자손 순서를 유지한다. 종료는 Object → Level → Project이며 각 호스트는 부착 역순으로 정리한다. 레벨 전환은 기존 World만 정리하고 Project를 유지한다. 후보 초기화 실패 시 현재 World와 Project 연결을 복구한다.

Project·Level draw는 카메라가 적용된 월드 원점 기준이다. Object draw는 기존 Transform·Canvas·정렬을 유지한다. drawScreen은 모든 범위에서 게임 영역 왼쪽 위 (0, 0) 기준의 실제 픽셀 좌표이며 카메라·Object Transform을 적용하지 않는다. 순서는 Project.draw → Level.draw → 기존 Object 렌더링(Canvas 포함) → Object.drawScreen → Level.drawScreen → Project.drawScreen이다. Object drawScreen은 기존 객체 렌더링 정렬 규칙을 사용한다. 모든 콜백에서 그래픽 상태와 게임 영역 클리핑을 보호한다.

fixedUpdate 같은 임의 메서드는 자동 호출하지 않는다. Level Script가 시간을 누적하고 대상 Script를 조회해 직접 호출한다. 직접 제어할 Object Script에는 update를 정의하지 않으면 된다. 편집 전용 drawEditor는 초기화 없이 설정값을 가진 미리보기에서 실행한다.

```text
project.labo / Level 데이터 ──저장──> scripts·scriptOverrides
WorldLoader ──생성──> Project 실행 호스트 ──참조──> 현재 World
World ──소유──> Level Script 인스턴스·LObject
LObject ──소유──> Object Script 인스턴스
Project 호스트·World·LObject ──의존──> ScriptHost 공용 메서드
Renderer ──호출──> draw·drawScreen
```

## 예상 결과

- 긍정: 별도 싱글톤 계층 없이 관리 Script를 조합하고, 모든 범위에서 같은 조회·콜백 API를 사용한다.
- 부정: 기존 Script가 self.owner.transform을 가정한다면 Project·Level에 그대로 부착할 수 없다. 장기 보관한 Object·World 참조는 레벨 전환 후 직접 갱신해야 한다.
- 중립: 런타임 부착 변경 API는 공개하지 않는다. 기존 Object·Prefab 데이터와 레거시 레벨 콜백은 유지한다. 기존 바이너리는 새 선택적 필드를 보존하지 못할 수 있다.
