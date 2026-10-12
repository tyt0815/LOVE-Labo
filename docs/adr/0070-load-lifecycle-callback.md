# 0070. 초기화 콜백 이름을 load로 통일한다

- 상태: 승인·구현
- 부분 대체: [0021](0021-begin-play-and-orthographic-rotation.md), [0036](0036-code-conventions-and-module-names.md), [0069](0069-script-identity-and-editor-authored-attachments.md)의 beginPlay 명칭 계약

## 배경과 제약

사용자는 LÖVE의 load·update·draw 흐름과 같은 이름이 더 직관적이라고 판단했다. 기존 초기화 동작과 실행 순서를 바꾸지 않고 이름만 변경한다. 에셋 파일을 읽는 동작과 실행 인스턴스 초기화는 기존처럼 구분한다.

## 대안과 판단 기준

beginPlay 유지와 load 전환을 비교했다. UE의 용어보다 LÖVE 사용자에게 익숙한 명칭을 우선한다. 두 이름을 계속 별칭으로 제공하는 방식은 문서와 재정의 우선순위를 복잡하게 하므로 공개 콜백 이름을 load 하나로 통일한다.

## 결정 및 근거

Script의 load(self, world), 레벨의 load(world), LObject:load(world)를 사용한다. 초기화 상태와 재진입 방지는 hasLoaded·loadingScripts로 이름을 맞춘다. 코어 호출 경로, 클래스 로더의 콜백 검증, 생성 템플릿, 예제, 검증 도구와 사용자 가이드를 함께 변경한다. 기존 프로젝트 코드의 beginPlay 선언과 직접 호출은 load로 수정해야 한다.

초기화는 실행 World에서 인스턴스마다 한 번만 수행한다. Spawn은 생성 시 초기화하며, enabled=false여도 초기화는 수행한다. 다시 활성화해도 초기화하지 않는다. 실행 중인 초기화에 재진입하지 않고 제거된 인스턴스의 후속 초기화를 중단한다. Preview·검증 준비는 load·update를 실행하지 않는다. 레벨 전환의 준비·활성화 경계와 오류 전달은 유지한다.

## 결과

- 긍정: LÖVE의 load·update·draw와 같은 흐름으로 코드를 읽을 수 있다.
- 부정: beginPlay를 사용하던 외부 프로젝트 코드는 이름 변경이 필요하다.
- 중립: 상속, 프로퍼티, 실행 순서, 활성 상태와 에셋 저장 형식은 바뀌지 않는다.
