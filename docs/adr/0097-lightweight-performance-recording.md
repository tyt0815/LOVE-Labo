# 0097. 가벼운 성능 기록과 이동 가능한 내부 창

- 상태: 채택·구현

## 배경과 제약

고정 패널을 늘리지 않고 느린 프레임·Script를 조사해야 한다. GUI와 CLI는 같은 기록기를 사용하고 Core는 Editor에 의존하지 않는다. LÖVE 11.5의 단일 기본 창을 유지한다.

## 대안과 판단 기준

OS 보조 창은 별도 호스트·프로세스 전달이 필요하다. 화면 통계만으로는 느린 구간을 조사하기 어렵다. 이동·크기 조절 가능한 내부 창과 선택적인 통계 표시를 먼저 제공한다.

## 결정 및 근거

runtime.Performance는 수집·집계만 담당한다. EditorApp은 프레임·Update·뷰포트 Draw·나머지 UI Draw와 객체·Script 수, 프로세스 Lua 메모리·공유 텍스처 메모리·렌더 통계를 기록한다. 최근 프레임은 300개, 상세 Script 항목은 약 2048개로 제한하고 초과 항목은 합산한다. Script 상세 측정은 기본으로 끄고 선택적으로 켠다.

Core의 업데이트·렌더러는 선택적인 profiler 객체의 sample 계약만 사용한다. 시간은 CPU 측 wall time이며 GPU 실행 시간으로 표현하지 않는다. Script 통계는 Clear 이후의 누계이고 프레임 선택은 해당 프레임의 기본 통계를 표시한다. 프레임 기록 정지는 게임 Pause와 독립적이다.

PerformanceWindow는 표시·기록 토글·프레임 선택·스크롤·JSON Export를 맡는다. CLI level.simulate의 profile 옵션은 같은 기록기를 사용하되 실제로 실행하는 Update만 측정한다. CLI의 측정 프레임 시간은 시뮬레이션 한 번의 실행 소요 시간이며 GUI의 실제 프레임 간격과 구분한다.

```text
EditorApp·CliSimulation ──포함──> Performance
Core ScriptHost·Renderer ──선택적 의존──> profiler.sample 계약
PerformanceWindow ──조회──> Performance
```

## 예상 결과

- 긍정: 기존 화면 배치를 유지하고 GUI·CLI에서 같은 측정 결과 형식을 얻는다.
- 부정: 상세 측정과 성능 창도 실행 비용을 더하며 배포 게임의 성능과 같지 않다.
- 중립: 게임 API·데이터 형식은 유지한다. GPU 타이머·함수별 샘플링·외부 OS 창은 추가하지 않는다.
