# Gameplay Window 렌더 런타임 게이트

`gameplay_window_render_smoke.gd`는 suite의 window renderer 단계에서 bounded runner(240초 제한)로 실행됩니다. 게이트는 현재 Godot 프로세스의 Window Viewport에 `scenes/game/main.tscn`을 직접 인스턴스화하고, 각 상태를 `RenderingServer.frame_post_draw` 다음에 읽습니다. Godot을 내부에서 다시 실행하지 않습니다.

기본 1920×1080 Viewport에서 실제 Forest Ruins 배경, Player v8 Sprite, 세 Forest Raider Sprite, Combat HUD, YSort 설정, 활성 Player 카메라를 확인합니다. idle, 오른쪽 이동, 실제 Player 공격 시작, `receive_hit`의 네 프레임을 수집하고 렌더된 픽셀 차이를 확인합니다. 결과는 4분할 1920×1080 비교 이미지 [gameplay_window_render_gate.png](../../assets/art/review/gameplay_window_render_gate.png)입니다.

## 실패 코드

| 코드 | 의미 |
| --- | --- |
| GWR-001 | Window renderer 대신 headless/dedicated display가 활성화됨 |
| GWR-002 | Godot renderer 설정이 미지원이거나 식별되지 않음 |
| GWR-003 | main scene을 로드하거나 인스턴스화하지 못함 |
| GWR-004 | 배경, YSort, Player, 카메라, HUD 또는 Raider 3명 조건 불일치 |
| GWR-005 | Forest Ruins, Player 또는 Raider 텍스처가 없거나 무효 |
| GWR-006 | YSort 또는 현재 카메라가 활성화되지 않음 |
| GWR-007 | 프레임이 비어 있거나 크기가 다르거나 검정/빈 렌더임 |
| GWR-008 | 이동 상태에서 Player 위치가 변하지 않음 |
| GWR-009 | 공격 상태 또는 공격 시각 효과가 나타나지 않음 |
| GWR-010 | 피격 상태 적용 또는 프레임 캡처 실패 |
| GWR-011 | 대표 상태 간 렌더 차이가 확인되지 않음 |
| GWR-012 | 비교 PNG를 저장하거나 다시 읽을 수 없음 |
| GWR-013 | 비교 PNG 크기가 1920×1080이 아님 |

## 로그 판정

`Shader cache` 생성/로드/컴파일 지연의 `WARNING`은 렌더 실패 자체가 아니며 경고만으로 게이트를 실패 처리하지 않습니다. 반면 Godot 스크립트/런타임 오류, 렌더러 초기화 실패, `GWR-*` 검사 실패, 성공 마커 누락 또는 0이 아닌 종료 코드는 실제 실패입니다. smoke runner가 `user://logs` 생성 불가나 Windows root certificate store 읽기 실패를 환경 경고로 출력할 수 있습니다. 이번 실행에서도 이 환경 경고만 있었고, Window renderer는 정상 초기화되어 네 프레임 PNG와 PASS 마커를 생성했습니다. suite의 기존 PASS 마커, 종료 코드, 이미지 판정 조건은 변경하지 않았습니다.

직접 실행은 프로젝트 루트에서 `godot.exe --path . --script res://tests/gameplay_window_render_smoke.gd`로 합니다. GUI/window renderer가 필요합니다. `tools/smoke_suite.cmd`는 이를 240초 bounded window smoke로 실행합니다.
