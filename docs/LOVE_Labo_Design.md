# LÖVE Labo — Design

- 상태: **개발 Baseline**
- 목적: 구현 세부사항을 미리 고정하지 않고, 프로젝트의 장기적인 방향과 책임 경계만 유지한다.
- 세부 API, 파일 구조, 자료구조, edge case는 실제 기능을 구현할 때 현재 repository를 보고 결정한다.

---

# 1. 제품 정의

LÖVE Labo는 LÖVE를 대체하는 게임 엔진이 아니라, **LÖVE 위에 얹는 가벼운 범용 2D game authoring environment**다.

```text
AI / 개발자
→ Lua gameplay code 작성·수정

사용자
→ Viewport / Inspector / Prefab / Level에서 시각적 데이터 편집

LÖVE Labo
→ Lua code와 authoring data 연결
→ Play / Debug / Export 지원

LÖVE
→ 실제 runtime / graphics / input / audio
```

첫 실사용 대상은 현재 제작 중인 리듬게임이다.

Beat Timeline, BPM, Rhythm Event 등 특정 게임에만 필요한 기능은 처음부터 Core에 넣지 않는다. Project Lua 또는 Plugin에서 먼저 구현하고, 여러 프로젝트에서 반복되는 필요가 확인된 기능만 Core/Editor로 승격한다.

---

# 2. 핵심 설계 원칙

## 2.1 Lua gameplay code가 Source of Truth다

LObject의 동작과 게임별 로직은 Lua에 존재한다.

```text
LObject의 behavior
→ Project Lua

공간 배치 / 시각적 값 / instance data
→ Editor authoring data
```

Editor는 범용 Visual Scripting으로 코드를 대체하지 않는다.

## 2.2 LObject는 composition 중심으로 구성한다

LObject는 **LÖVE Labo에서 사용하는 기본 게임 객체 개념**이다.

기본 방향은 다음과 같다.

```text
LObject Definition
+ Runtime LObject
+ Component composition
```

Lua에는 언어 차원의 class 문법이 없으며, LÖVE Labo도 깊은 class inheritance hierarchy를 기본 모델로 삼지 않는다.

LObject Definition의 정확한 module/API 형태는 실제 객체 모델을 구현할 때 결정한다.

## 2.3 Core는 범용 기능만 가진다

```text
Editor → Core    O
Core → Editor    X
```

게임별 기능은 Core에 하드코딩하지 않는다.

공통 World/LObject lifecycle, rendering, Level loading처럼 여러 게임에서 반복되는 기능은 Core 후보가 될 수 있다. 특정 게임에서만 필요한 기능은 Project Lua 또는 Plugin에 둔다.

## 2.4 필요한 만큼만 설계한다

현재 기능에 필요하지 않은 다음 사항은 미리 확정하지 않는다.

```text
세부 API 이름/signature
ID 형식
JSON 세부 semantics
module cache 방식
Hot Reload 구현 전략
Plugin precedence
startup API
세부 파일/module 분리
```

실제 구현에서 요구가 드러난 뒤 결정한다.

---

# 3. 기본 아키텍처

```text
                         LÖVE Labo Host
                              │
                 ┌────────────┴────────────┐
                 │                         │
               Editor                  Core Runtime
                 │                         │
      Viewport / Inspector       LObject / Component
      Prefab / Level             World / Renderer
      Hierarchy / Assets         Level / Spawn
      Play / Console                    │
                 │                  Public API
                 │                require("engine")
                 │                         │
                 └─────────────── Project Lua
                                           │
                              Prefab / Level / Assets
```

Plugin은 Core/Editor를 직접 수정하지 않고 기능을 확장하기 위한 경로다.

---

# 4. LObject / Component 방향

## 4.1 LObject Definition

LObject Definition은 Project Lua에 존재하며 개념적으로 다음을 정의한다.

```text
기본 Component 구성
Component 기본 authoring 값
LObject-specific gameplay behavior
```

정확한 declaration API는 구현 시 결정한다.

## 4.2 Runtime LObject

Runtime LObject는 World가 소유하는 실제 실행 instance다.

개념적으로 다음 정보를 가진다.

```text
runtime identity
LObject Definition reference
Component instance data
필요한 runtime state
```

Runtime LObject의 mutable data가 Definition, Prefab, Level 원본과 의도치 않게 공유되면 안 된다.

## 4.3 Component

Component는 LObject의 구조화된 state/capability data다.

초기 구현에서는 실제 authoring에 필요한 최소 Component부터 시작한다. Transform과 기본적인 2D rendering data가 우선 후보지만 정확한 schema는 구현 중 결정한다.

Project-defined Component를 지원하는 방향을 유지한다. 모든 Component field가 자동으로 저장 대상인 것은 아니며 authoring/serialized state와 runtime-only state를 구분할 수 있어야 한다.

Generic ECS System/Query/Scheduler framework는 기본 전제로 두지 않는다.

---

# 5. Authoring Data 흐름

```text
Component Schema
        ↓
LObject Definition
        ↓
Prefab
        ↓
Level LObject Instance
        ↓
Runtime Initial State
```

구체적인 override semantics는 Prefab과 Level을 실제 구현할 때 결정한다.

중요한 원칙은 하위 단계의 수정이 상위 원본 데이터를 의도치 않게 mutate하지 않는 것이다.

---

# 6. Prefab

Prefab은 LObject Definition의 **데이터 기반 variation**이다.

초기에는 단순하게 시작한다.

```text
LObject Definition
→ LObject 구조와 기본 구성

Prefab
→ 이미 정의된 authoring data의 기본값 variation
```

Prefab inheritance나 복잡한 composition 기능은 실제 필요가 확인되기 전에는 구현하지 않는다.

`.prefab`은 사람이 읽고 Git/AI가 다루기 쉬운 text asset을 기본 방향으로 한다.

---

# 7. Level / Authoring Model

Level은 visual placement와 instance override의 Source of Truth다.

Level 전체의 동작은 프로젝트 Lua에 둘 수 있다. `.level`은 `Sources/` 아래 코드의 프로젝트 상대 참조를 저장하며, 배치 데이터와 실행 동작의 책임을 분리한다. 현재 기본 레벨·소스 생성 및 callback 계약은 [ADR 0007](adr/0007-sources-and-level-scripts.md)을 따른다.

Level LObject Instance는 개념적으로 다음을 가진다.

```text
LObject Definition 또는 Prefab source
stable authoring identity
Transform을 포함한 instance data/override
필요한 hierarchy 관계
```

`.level`도 사람이 읽을 수 있는 text asset을 기본 방향으로 한다.

Editor의 핵심 authoring workflow:

```text
Level 생성/열기
→ LObject 또는 Prefab 배치
→ 선택 / 이동
→ Inspector 수정
→ hierarchy 편집
→ duplicate / delete
→ save / load
```

세부 hierarchy나 identity 규칙은 실제 구현 시 결정한다.

---

# 8. Edit State와 Runtime State 분리

중요한 invariant다.

```text
Edit / Authoring State
≠
Play Runtime State
```

Play 시 authoring data에서 별도의 Runtime World를 만든다.

Runtime에서 변경된 위치, HP, temporary spawn, transient state 등이 Prefab/Level 원본에 자동 write-back되면 안 된다.

완전한 process/VM sandbox는 초기 목표가 아니다.

---

# 9. Editor 방향

초기 Editor가 궁극적으로 제공해야 할 핵심 기능은 다음과 같다.

```text
Scene View
Hierarchy
Inspector
Asset Browser
Prefab / Level authoring
Transform editing
Undo / Redo
Play / Stop / Restart
Game View
Console
Plugin extension
```

한 번에 모두 만들지 않는다. 현재 사용 흐름에 필요한 기능부터 작은 단위로 구현한다.

Scene View는 authoring state를 보여주고 Game View는 Runtime World 결과를 보여준다.

LÖVE `love.graphics`는 stateful API이므로 Viewport와 Editor UI 사이에서 graphics state가 새지 않도록 한다.

---

# 10. Filesystem / Serialization / Asset

Project는 LÖVE Labo 설치 폴더 밖에 있을 수 있다.

따라서 외부 Project filesystem과 exported `.love` 내부 filesystem을 같은 물리 경로라고 가정하지 않는다.

Prefab/Level/Project metadata는 사람이 읽고 Git diff가 가능한 text data를 우선한다. 초기 저장 형식은 JSON-backed asset을 기본 후보로 유지하되 library와 세부 semantics는 실제 serialization 구현 시 결정한다.

필수 방향:

```text
잘못된 data validation
실패한 save에서 기존 정상 파일 보존
의미 없는 저장 churn 최소화
canonical project-relative reference
```

asset path를 runtime drawable 자체로 취급하지 않는다. Rendering 전에 실제 LÖVE asset object로 resolve되어야 한다.

---

# 11. Project Loader / Public API

Project Lua가 Core 내부 파일 경로에 직접 의존하지 않도록 Public facade를 둔다.

```lua
local Engine = require("engine")
```

Editor Play와 exported `.love`에서 같은 Project Lua가 가능한 한 같은 의미로 동작하도록 한다.

Project loading은 장기적으로 다음을 담당한다.

```text
Project metadata
Project Lua discovery/load
LObject/Component registration
Project switch/reload
load error containment
```

정확한 discovery 규칙과 module cache 정책은 구현 시 결정한다.

Project load 실패가 Editor process 전체를 crash시키거나 반쯤 적용된 Project state를 조용히 남겨서는 안 된다.

Host는 `love.load`, `love.update`, `love.draw` 같은 top-level LÖVE callback lifecycle을 소유한다.

---

# 12. Runtime / Rendering

Runtime World는 Level authoring data에서 Runtime LObject를 생성한다.

```text
love.update(dt)
→ Host
→ Runtime World
→ LObject behavior

love.draw()
→ Host
→ Runtime World / Renderer
→ Component data
```

Project Lua는 필요한 경우 `love.keyboard`, `love.audio`, `love.math`, `love.timer` 등 일반 LÖVE subsystem을 직접 사용할 수 있다.

공통 rendering 의미는 Scene View와 Runtime에서 가능한 한 공유하되 lifecycle/state는 분리한다.

Runtime callback 오류는 가능하면 Editor 전체 종료 대신 recoverable error로 전달한다.

---

# 13. Reload 방향

Project Lua를 외부 AI나 editor에서 수정한 뒤 빠르게 확인할 수 있어야 한다.

```text
간단한 behavior 변경
→ Hot Reload 후보

schema / 구조 변경
→ Runtime Restart 후보

완벽한 Hot Reload
→ 목표 아님
```

처음부터 복잡한 Hot Reload 시스템을 만들지 않는다. 실제 개발 흐름에서 단순 file change → Runtime Restart만으로 충분하면 그것도 유효한 구현이다.

---

# 14. Plugin

게임별 또는 전문 authoring 기능은 Plugin으로 확장할 수 있는 방향을 유지한다.

예:

```text
Rhythm Timeline
Tilemap Tool
Custom Asset Editor
Importer
Profiler
Specialized Viewport Tool
```

Plugin API는 실제 확장 요구가 생긴 뒤 최소 extension point부터 만든다.

---

# 15. Export

초기 export 목표는 standalone executable이 아니라 LÖVE가 실행할 수 있는 `.love` package다.

Exported runtime은 Editor 코드에 의존하지 않고 Project Lua/data/assets를 package 내부에서 읽을 수 있어야 한다.

startup 방식과 packaging 세부사항은 export를 실제 구현할 때 결정한다.

---

# 16. Undo / Dirty / Documents

Authoring mutation은 가능한 한 Undo/Redo 가능한 경계를 고려한다.

Prefab/Level 같은 document는 dirty/save 상태를 잃지 않아야 한다.

다른 document나 Project로 전환할 때 unsaved data를 조용히 폐기하지 않는 방향을 유지한다.

세부 Command API와 document lifecycle은 실제 필요가 생겼을 때 결정한다.

---

# 17. AI / 개발 Workflow

LÖVE Labo 자체는 작은 기능 단위로 개발한다.

```text
현재 repository 확인
→ 지금 필요한 문제 하나 선택
→ 세부 설계 논의
→ AI가 수정 코드 제공
→ 사용자가 로컬에 적용
→ 실행 / 테스트
→ 문제 수정
→ 정상 동작 확인
→ 다음 기능 선택
```

현재 구현 상태는 별도의 상태 문서가 아니라 최신 repository와 실제 코드를 기준으로 판단한다.

미래 기능 전체의 구현 계획을 별도 문서로 고정하지 않는다.

게임 제작 시 핵심 역할 분담:

```text
AI
→ Project Lua 작성 / 수정 / 디버깅

사용자
→ Viewport / Inspector / Prefab / Level authoring

LÖVE Labo
→ code와 visual data 연결
```


---

# 18. 초기 범위에서 의도적으로 하지 않는 것

```text
범용 Visual Scripting
깊은 게임 객체 class inheritance
Generic ECS framework
Prefab inheritance
UE급 Level Streaming
완전한 Hot Reload
완전한 process/VM sandbox
온라인 Plugin registry/package manager
대규모 animation/physics/network framework
standalone executable packaging
```

필요성이 실제 게임 제작 과정에서 확인된 뒤 다시 판단한다.

---

# 19. 설계 결정 방식

이 문서는 방향과 invariant만 고정한다.

구체적인 기능은 실제 repository 상태와 현재 요구를 기준으로 하나씩 결정한다.

```text
현재 문제 확인
→ 필요한 선택지만 비교
→ 구현
→ 테스트
→ 결과에서 다음 요구 발견
```

기존 결정이 실제 사용에서 불편하거나 잘못된 것으로 드러나면 수정할 수 있다.

다만 `Lua code가 gameplay behavior의 Source of Truth`, `Core → Editor 의존 금지`, `Edit/Runtime 분리`, `게임 특화 기능을 Core에 넣지 않음` 같은 핵심 경계를 변경할 때는 의도적으로 설계를 재검토한다.
