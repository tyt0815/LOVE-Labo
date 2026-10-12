# 직접 검수하는 API 예제

저장소의 `tests/TestProject`를 열고 **Assets/L_ApiExamples.level**을 엽니다. 기본 제공 스크립트는 LaboEssentials, 예제 Lua·Prefab·이미지는 프로젝트의 **Assets/Examples**에 있습니다. 테스트 프로젝트에는 검수에 필요한 예제 에셋만 남겨 두었습니다.

Scene View 위의 ▶로 실행합니다. 화면의 두 열 버튼은 Canvas 아래에 있어 카메라를 확대해도 위치를 유지합니다.

![API 예제 실행 화면](images/api-examples.png)

| 버튼·오브젝트 | 확인하는 동작 |
|---|---|
| Motion and Property References | beginPlay·update, number·boolean·string·object·script 프로퍼티, getWorldPosition/getWorldTransform |
| Inherited Transform Child | 부모의 이동·Z 회전이 자손 Sprite에 합성됨 |
| Spawn | Prefab 템플릿 참조와 spawnLObject로 Sprite·Motion 오브젝트 생성 |
| Raw | World.addLObject, addScript, beginPlay로 빈 오브젝트부터 구성 |
| Bounds | Bounds.hitTest/getBounds, CoordinateSpace, Viewport의 월드·화면 좌표 변환 |
| Remove | 마지막으로 생성한 오브젝트 제거 |
| Attach | 생성한 오브젝트를 움직이는 부모에 부착·분리 |
| Scripts | 생성한 오브젝트에 Motion 스크립트를 추가·제거. 먼저 Spawn |
| Properties | 실행 중 프로퍼티를 바꿔 움직임을 켜고 끄며 Transform.point 결과 기록 |
| Camera | getActiveCamera/setActiveCamera와 zoom 변경. 화면 좌표 버튼은 이동하지 않음 |
| Debug | point·line·circle·rect·polygon, screenLog·log·marker |
| Next / Back | openLevel로 L_ApiNext·L_ApiExamples 사이 전환 |
| 모든 버튼 | Pointer 상속, down/up/move, blockPointer, inputPriority, sortingOrder, 영역 판정 |
| Screen Space Text | Text 스크립트의 줄바꿈·정렬·크기, Canvas 기반 화면 공간 텍스트 |
| Screen Space Text | Text 스크립트의 줄바꿈·정렬·크기, Canvas 기반 화면 공간 텍스트 |
| Screen Space Text | Text 스크립트의 줄바꿈·정렬·크기, Canvas 기반 화면 공간 텍스트 |
| Screen Space Text | Text 스크립트의 줄바꿈·정렬·크기, Canvas 기반 화면 공간 텍스트 |
| 편집 화면 | Camera·RectBounds·Canvas·Sprite·Pointer의 drawEditor 영역 표시 |
| LevelDemo.lua | 레벨 beginPlay/update와 world.properties, 레벨 전환 시 새 초기화 |

Spawn을 누른 뒤 Attach·Scripts·Remove를 순서대로 확인합니다. 화면 바깥으로 드래그해서 놓아도 Pointer capture가 up 이벤트를 전달합니다. ⏸로 멈추면 Update·게임 입력·일시적 디버그 표시 수명이 멈추고, ▶는 같은 Runtime World를 이어서 실행합니다. ■는 편집 모드로 복귀합니다.

소스는 `Assets/Examples/Motion.lua`, `Actions.lua`에서 확인합니다. **Assets/Examples/PF_Spawned.prefab**을 수정하면 이후 Spawn의 기본값을 바꿀 수 있습니다. 레벨 인스턴스의 프로퍼티와 로컬 스크립트도 Inspector에서 편집할 수 있습니다.

다른 프로젝트에는 다음 명령으로 같은 예제를 생성할 수 있습니다. Assets/Examples나 예제 레벨이 이미 있으면 덮어쓰지 않습니다. 예제 생성은 LaboEssentials만 활성화하며 별도 예제 플러그인을 만들지 않습니다.

```powershell
Labo-cli.exe --cli project examples --project D:/Games/MyGame
```

새 게임 기능을 개발할 때는 관련 예제 오브젝트·레벨과 검수 방법도 함께 갱신합니다.

`Text`는 일반 게임 텍스트 렌더링 스크립트입니다. `text`, `fontSize`, `width`, `align`(`left`·`center`·`right`), RGBA 색과 `sortingOrder`를 Inspector에서 설정합니다. LObject의 이동·회전·스케일을 따르며 Canvas 아래에 두면 화면 공간에 표시됩니다. `screenLog`는 일시적인 디버그 메시지용 API입니다. 기본 LÖVE 폰트를 사용하므로 별도 글꼴 리소스 선택은 제공하지 않습니다.

`Text`는 일반 게임 텍스트 렌더링 스크립트입니다. `text`, `fontSize`, `width`, `align`(`left`·`center`·`right`), RGBA 색과 `sortingOrder`를 Inspector에서 설정합니다. LObject의 이동·회전·스케일을 따르며 Canvas 아래에 두면 화면 공간에 표시됩니다. `screenLog`는 일시적인 디버그 메시지용 API입니다. 기본 LÖVE 폰트를 사용하므로 별도 글꼴 리소스 선택은 제공하지 않습니다.

`Text`는 일반 게임 텍스트 렌더링 스크립트입니다. `text`, `fontSize`, `width`, `align`(`left`·`center`·`right`), RGBA 색과 `sortingOrder`를 Inspector에서 설정합니다. LObject의 이동·회전·스케일을 따르며 Canvas 아래에 두면 화면 공간에 표시됩니다. `screenLog`는 일시적인 디버그 메시지용 API입니다. 기본 LÖVE 폰트를 사용하므로 별도 글꼴 리소스 선택은 제공하지 않습니다.

`Text`는 일반 게임 텍스트 렌더링 스크립트입니다. `text`, `fontSize`, `width`, `align`(`left`·`center`·`right`), RGBA 색과 `sortingOrder`를 Inspector에서 설정합니다. LObject의 이동·회전·스케일을 따르며 Canvas 아래에 두면 화면 공간에 표시됩니다. `screenLog`는 일시적인 디버그 메시지용 API입니다. 기본 LÖVE 폰트를 사용하므로 별도 글꼴 리소스 선택은 제공하지 않습니다.
