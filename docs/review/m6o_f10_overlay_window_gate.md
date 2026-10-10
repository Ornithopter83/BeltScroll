# M6O F10 충돌 오버레이 실제 Window 게이트

## 구현 및 보정

`CombatCollisionOverlay`는 실제 `CollisionShape2D.shape`와 현재 노드 변환을 읽어 별도 최상위 `CanvasLayer`에 표시한다. 충돌 shape, 충돌 레이어/마스크, monitoring, 피해값, HUD 노드는 변경하지 않는다. Shape의 캔버스 transform을 오버레이 캔버스 로컬 좌표로 변환해 카메라 transform이 중복 적용되지 않도록 했다. 화면 투영은 실제 body outline의 Window 픽셀과 `get_global_transform_with_canvas()` 및 Viewport 최종 transform 결과를 비교한다.

Area2D 라벨에는 `MON`과 `MONABLE`을 함께 표시한다. Raider/Boss ReceiveArea처럼 `monitoring=false`인 채 `monitorable=true`로 공격 감지를 받는 영역 상태를 오해하지 않도록 했다. 표시 OFF는 입력 전 OFF 픽셀과 실제 body 외곽 위치를 대조해 확인했다.

## 실제 Window 자동 캡처

실행 명령:

```text
godot.exe --path . --script res://tests/m6o_f10_overlay_window_smoke.gd
```

2026-10-10, Godot 4.7.2, Windows DisplayServer, AMD Radeon RX 6900 XT OpenGL Compatibility 렌더러에서 비-headless Window로 실행했다. Window와 Viewport는 각각 `2560×1440`이었다. 각 OFF/ON 캡처는 실제 게임 Viewport 이미지에서 뽑은 뒤 960×540 셀로 축소해 한 장에 붙였다. 시트 왼쪽은 OFF, 오른쪽은 ON이다.

| 행 | 장면 상태 |
|---:|---|
| 1 | Player 기본 1타, 해당 실제 hitbox monitoring ON |
| 2 | Player 기본 2타, 해당 실제 hitbox monitoring ON |
| 3 | Player 기본 3타, 해당 실제 hitbox monitoring ON |
| 4 | Player Num4, 해당 실제 hitbox monitoring ON |
| 5 | Player Num5, 해당 실제 hitbox monitoring ON |
| 6 | Raider 몸체·ReceiveArea·AttackArea 실제 shape |
| 7 | Boss slash 반경 67 원 교체 후 실제 AttackArea monitoring ON |
| 8 | Boss slam 반경 125 원 교체 후 실제 AttackArea monitoring ON |
| 9 | 카메라 줌·스크롤 및 Player 좌우 방향 전환 |
| 10 | Raider와 Boss KO 후 남은 몸체/피격 shape 및 비활성 판정 상태 |

재시작은 별도 프레임에서 확인했다. overlay의 `enabled=false`와 restart scene 상태를 검사했다. 각 쌍에서 ON 픽셀 변화, OFF/ON body 외곽점, Player/Raider/Boss 몸체 외곽선의 projected 위치(4 Window 픽셀 이내), 실제 충돌 레이어/마스크/monitoring/monitorable, 세 actor의 HP, 일반 CombatHUD 표시를 확인했다. 자동 검사는 전체 캡처 시트 저장과 함께 통과했다.

캡처 파일: [m6o_f10_overlay_alignment_sheet.png](../../assets/art/review/m6o_f10_overlay_alignment_sheet.png)

## 입력과 사람 검수 구분

- 픽셀 캡처는 실제 비-headless Godot Window에서 완료했다.
- F10 전환은 테스트가 만든 synthetic `InputEventKey`를 오버레이 입력 callback에 전달한 자동 검사다. OS 키보드의 실제 F10 키 입력은 **테스트하지 않았다**.
- 사람의 화면 승인/시각 검수는 **기록되지 않았다**. 픽셀 시트와 좌표 자동 검증 결과만 남겼다.

실행 중 Godot가 기존 `user://logs` 로그 파일과 Windows 루트 인증서 저장소 접근 경고를 출력했지만, Window 픽셀 스모크는 성공 종료했다. 이는 테스트가 생성한 오버레이 동작이나 씬 코드 수정과 무관한 환경 경고다.
