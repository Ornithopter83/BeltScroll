# Raider VisualAnimator 모션 검수

`assets/art/review/raider_motion_states_capture.png`는 기존 `scenes/enemies/forest_raider.tscn`과 `scripts/enemies/raider_visual_animator.gd`를 실제 Window Viewport에서 렌더링한 상태 비교 시트입니다.

## 캡처 내용

- Forest Ruins 배경 위에서 대기, 추적, 공격 준비, 공격 활성, 회복, 피격 경직, KO의 일곱 상태를 각각 렌더링합니다.
- 상태 입력은 검수용 Raider 인스턴스의 기존 전투 상태 변수만 설정합니다. AI와 물리 처리는 실행하지 않습니다.
- 방향을 좌우로 번갈아 배치하고, 원화의 alpha 실루엣 높이를 192 px로 맞춥니다. 각 칸의 기준선은 발 alpha anchor를 확인하기 위한 표시입니다.
- 각 상태는 1920×1080 Window Viewport에서 실제 렌더한 뒤 480×540 칸으로 잘라 한 PNG로 합칩니다. 같은 배경 구간을 각 칸에 반복해 상태 차이를 비교하기 쉽게 합니다.
- 칸 위의 Raider HUD 표식으로 캐릭터와 HUD가 겹치는지 볼 수 있습니다.

이 파일은 **합성된 상태 비교 시트**입니다. 각 칸은 서로 다른 시점에 캡처되었으며 **실제 연속 플레이 영상이 아닙니다**.

## 실행

실제 Window Viewport가 있는 환경에서 프로젝트 루트 기준으로 실행합니다.

```powershell
godot --path . --script res://tools/capture_raider_motion_sheet.gd
```

출력 PNG 경로는 첫 번째 인수로 지정할 수 있습니다. `--headless` 또는 전용 서버에서는 렌더러가 없으므로 오류 코드 1로 종료합니다.

## Smoke 검증

GUI 렌더러 환경에서 다음 독립 smoke를 실행합니다.

```powershell
godot --path . --script res://tests/raider_motion_capture_smoke.gd
```

Smoke는 192 px 표시 높이, 발 anchor 고정, 회복 후 중립 복귀, KO 정지, Window Viewport 캡처 PNG의 크기·상태별 픽셀 차이·내용, 저장 후 재열기, 그리고 headless 캡처의 비정상 종료를 확인합니다.
