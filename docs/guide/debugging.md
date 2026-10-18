# 에디터 로그와 디버그 표시

클릭 영역(hitTest)·프레이밍·기즈모 이동 중 사용자 영역·배치 계산이 실패하면 해당 조작을 취소하고 선택·드래그 시작값을 유지합니다. 하단 로그에서 원인을 확인하고 코드를 수정한 뒤 Refresh하여 재시도합니다. Game View·Preview·화면 좌표 그리기는 사용자 코드가 남긴 중첩 그래픽 스택도 복원합니다.

Play 중 투영 제공 함수가 실패하면 크기 갱신·이벤트·휠 입력에서도 실행 World를 정리하고 오류를 표시합니다. 원래 편집 문서는 유지되며 문제를 수정한 뒤 다시 Play할 수 있습니다.

편집 중 Scene View의 스크립트 `draw`·배치 계산이 실패해도 나머지 에디터 UI와 미저장 문서를 유지하고 하단 로그에 오류를 표시합니다. 같은 오류가 계속되는 프레임은 중복 기록하지 않습니다. 외부 코드 편집기에서 스크립트를 수정한 뒤 프로젝트를 새로고침하면 다시 미리보기를 확인할 수 있습니다.

흰색 하단바에는 최신 로그 한 줄이 계속 표시됩니다. 화살표 또는 **백틱(`)** 으로 펼치면 최근 1,000개를 스크롤할 수 있습니다. 내역은 에셋 브라우저·Inspector 위에 겹쳐 표시하며 기존 패널의 위치와 크기는 바뀌지 않습니다. 오류도 빨간 로그로 기록합니다. 팝업·텍스트 편집 중에는 백틱이 해당 입력에 전달됩니다.

접힌 하단바 높이는 36px이며 위 패널과의 간격은 4px입니다. 펼치기·접기 버튼과 최신 로그 한 줄은 항상 같은 하단 위치에 남습니다. 펼친 기록에는 최신 로그를 중복 표시하지 않으며, 바로 이전 로그부터 하단바 위쪽으로 쌓입니다. 기록이 적어도 아래쪽에 붙어서 표시되고 스크롤로 더 오래된 기록을 확인할 수 있습니다.

최신 로그와 이전 기록 사이도 다른 행과 같은 22px 간격입니다. 동일한 내용의 로그·오류를 합치거나 생략하지 않습니다. 오류 한 번에 한 줄을 남기며, 같은 동작이 다시 실패하면 같은 메시지를 새 줄로 기록합니다. 기존 오류가 화면에 계속 표시되는 동안에는 추가 기록이 생기지 않습니다. 최근 1,000개를 유지합니다.

![로그 기록과 화면 로그·도형](images/debugging.png)

![최신 로그 한 줄](images/log-collapsed.png)

## 게임 실행 중 출력

스크립트의 `self.owner.world.debug`, 레벨 스크립트의 `world.debug`를 사용합니다.

```lua
function Example.load(self)
    local debug = self.owner.world.debug
    debug:log("Started", {color = {255, 150, 40}, marker = "!"})
    debug:screenLog("Ready", {key = "state", lifespan = 3})
    debug:line(0, 0, 100, 100, {color = {0, 120, 255}, lifespan = 2})
end
```

`log(text, options)`는 하단 기록, `screenLog(text, options)`는 Game View 좌상단 표시입니다. 화면 로그는 최신 것이 위에 오며 같은 `key`를 지정하면 기존 항목을 교체해 맨 위로 이동합니다. key는 문자열 또는 숫자입니다.

하단 기록의 `marker`는 왼쪽 표시 칸에 나오는 한 글자이며 기본값은 `-`입니다. `!`·`+`·한글 한 글자 등을 지정할 수 있고 여러 글자나 줄바꿈은 허용하지 않습니다. 표시 칸의 폭은 고정되어 로그 본문은 하단 최신 로그와 같은 위치에서 시작합니다. 최신 로그의 표시 칸은 펼치기·접기 화살표로 사용합니다.

색은 RGB 0–255 배열이며 기본 주황색입니다. 화면 로그·도형의 `lifespan` 기본값은 3초, 0이면 한 표시 프레임만 유지합니다. Stop하면 화면 로그·도형을 지우고 하단 기록은 유지합니다.

| 도형 API | 인자 |
|---|---|
| point | x, y, radius, options; radius는 화면 픽셀, 기본 3 |
| line | x1, y1, x2, y2, options |
| circle | x, y, radius, options |
| rect | x, y, width, height, options |
| polygon | {x1, y1, x2, y2, x3, y3, ...}, options |

위치와 점을 제외한 크기는 월드 단위이며 카메라 이동·회전·배율을 따릅니다. 디버그 도형은 게임 렌더링 위에 표시합니다. 옵션은 화면 로그와 동일하게 color·lifespan을 지원합니다.

배포 게임에는 기록·렌더링 구현을 포함하지 않습니다. 같은 메서드 호출은 오류 없이 `false`를 반환하며 아무것도 표시하지 않습니다. 인자를 만드는 Lua 코드는 실행됩니다.

## 편집 중 표시

```lua
function Example.drawEditor(self, context)
    local transform = self.owner:getWorldTransform()
    context:circle(transform.x, transform.y, 100, {
        color = context.selected and {0, 120, 255} or {140, 140, 140}
    })
end
```

`drawEditor`는 Scene View에서만 호출합니다. `context`에는 위 도형 메서드와 `selected`, 테마 RGBA 배열 `color`가 있습니다. 매번 계산하므로 도형의 lifespan은 편집 표시에서 사용하지 않습니다. 게임 초기화가 실행되지 않으므로 `load`에서만 만든 값에 의존하지 마세요. Camera 플러그인의 카메라 범위도 이 방법으로 표시합니다.

LaboEssentials의 Camera·RectBounds·Canvas·Sprite·Pointer는 편집 화면에서 경계를 표시합니다. Pointer는 boundsSource로 지정한 스크립트의 실제 영역을 사용합니다. 이미지가 없는 Sprite나 크기가 0인 영역은 표시하지 않습니다. **PIE의 Game View와 배포 게임에는 이 경계를 표시하지 않습니다.** Play에서 직접 호출한 일시적인 디버그 도형은 별도로 표시됩니다.

![편집 화면의 클릭 영역](images/editor-areas.png)

사용자 스크립트도 `drawEditor`에서 `context:bounds(self)`로 getBounds 영역을 표시할 수 있습니다. Sprite의 이미지 조회를 위한 `context:image(reference)`도 제공됩니다.

## CLI 검증

```powershell
Labo-cli.exe --cli level simulate --project D:/Games/MyGame --level Assets/L_Start.level --frames 60 --debug
```

반환값의 `debug.history`, `debug.screens`, `debug.shapes`에서 실행 결과를 확인합니다. 각 시뮬레이션 프레임을 표시 프레임으로 간주해 수명을 처리하며 실제 렌더링·draw·drawEditor는 실행하지 않습니다. 옵션이 없으면 배포와 같은 no-op 동작입니다.
