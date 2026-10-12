# 0073. 오디오 에셋은 LÖVE 데이터로 연결하고 Script unload에서 정리한다

- 상태: 승인·구현
- 관련: [0050](0050-attached-scripts-and-unified-assets.md), [0058](0058-plugins-and-mounted-assets.md), [0067](0067-fixed-play-pause-stop-controls.md), [0070](0070-load-lifecycle-callback.md), [0071](0071-love-events-on-attached-scripts.md)

## 배경과 제약

게임 기능은 LÖVE로 작성하고 Labo는 편집 데이터와 실행 구조를 연결한다. 사용자 요청은 audio 프로퍼티의 에셋 지정과 부착 Script 종료 콜백이다. LÖVE 가상 파일 시스템과 에디터의 외부 프로젝트 경로가 달라 같은 문자열 경로를 그대로 재생에 사용할 수 없다. 자원 정리는 객체 제거뿐 아니라 Play 종료·레벨 전환·실행 실패도 포함해야 한다.

## 대안과 판단 기준

AudioPlayer·믹서·자동 일시정지 시스템은 사용자 요구보다 넓다. 물리 파일 경로를 반환하면 Export와 에디터 코드가 달라진다. 참조를 네이티브 Source로 자동 변환하면 에셋 데이터와 재생 인스턴스의 소유권이 섞인다. FileData를 반환하고 일반 LÖVE API로 처리하면 기존 에셋 ID 계약과 자원 소유권을 명확히 유지한다.

## 결정 및 근거

audio 프로퍼티는 false 또는 에셋 참조를 저장하고 Inspector·CLI에서 WAV·OGG·MP3·FLAC의 확장자와 실제 LÖVE 디코더를 검증한다. 일반 에셋 목록·플러그인 마운트·이동·참조 보호·Export 계약을 재사용한다. AssetData는 FileData 읽기와 오디오 검증을 담당하고 WorldLoader가 World.getAssetData에 프로젝트별 읽기 함수를 연결한다. FileData와 Source는 게임 코드가 소유한다. 재생·반복·볼륨·탐색·Pause 정책은 LÖVE로 처리한다. 새 오디오 편의 플러그인은 추가하지 않는다.

Script의 unload()는 load(world)와 짝을 이루되 종료 인자는 전달하지 않는다. 종료 중 실행 환경은 self.owner.world로 접근하므로 같은 World를 중복 전달하지 않는다. load를 시작한 각 부착에 한 번, enabled와 무관하게 호출한다. 제거하는 객체의 자손부터 부모, 같은 객체는 부착 역순으로 종료하며 owner·world 참조를 끊기 전에 호출한다. 콜백 예외가 있어도 나머지 정리와 객체 제거를 계속하고 오류를 반환한다. 재진입은 중복 종료하지 않는다. 반환값은 무시한다.

World.dispose는 남은 객체를 종료하고 Spawn·레벨 전환·update를 막는다. 성공적으로 초기화한 레벨로 전환한 뒤 이전 World를 정리한다. 전환 실패는 후보의 부분 자원을 정리하고 기존 World를 유지한다. 초기화·런타임 오류, Editor Stop·문서 교체·종료, Export 종료, 임시 CLI 세션도 같은 정리 경계를 사용한다. Preview와 정적 검증은 load/unload를 실행하지 않는다. 레벨 스크립트의 콜백 종류는 이번 요청에서 확장하지 않는다.

## 예상 결과

- 긍정: LÖVE 재생 API를 직접 쓰면서 에디터·플러그인·Export가 같은 오디오 참조와 종료 계약을 공유한다.
- 부정: 게임 코드가 FileData·Source의 해제와 Pause 동작을 명시적으로 작성해야 한다. unload 오류는 종료를 취소하지 않는다.
- 중립: 파일 형식·객체 구성·Script 상속·네이티브 LÖVE 오디오 제어는 유지한다.
