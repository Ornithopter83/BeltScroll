# Player jump motion review gate

## 범위

`scenes/review/player_candidate_motion.tscn`의 jump 항목은 `elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png`를 표시한다. safe 파생 원화는 미승인 검수 후보로만 사용하며 본편 Player, animation manifest, 승인 프레임 레지스트리를 수정하거나 연결하지 않는다.

`tools/capture_player_jump_motion_review.gd`는 독립 GUI Window에서 실제 `player_controller.gd`를 연결한 최소 격리 rig를 만들고, Player의 `_start_jump()`, `_update_jump()`, jump height/velocity, VisualRoot 수직 오프셋, GroundShadow alpha를 사용한다. 프로젝트의 physics tick(기본 60Hz)에 맞춰 물리 업데이트를 진행하고 `RenderingServer.frame_post_draw` 후 화면을 읽는다. 한 번의 점프에서 도약 직전, 상승, 정점, 하강, 착지를 우향과 좌향으로 각각 캡처한다. 좌향은 VisualRoot X scale만 한 번 반전한다.

## 시각 판정 경계

상승 단계에만 safe 후보 원화를 사용한다. 이 후보는 상승 원화 한 장이며, 정점·하강·착지 원화나 루프를 완성하지 않는다. 캡처는 상승 이후에 idle 원화를 절차적 실루엣 proxy로 표시하고 해당 단계가 미구현임을 각 프레임에 표시한다. 착지의 십자 burst는 검수용 절차 표시이며 Player에 착지 팝 동작이 구현됐다는 뜻이 아니다. 검수용 rig는 표시 가능한 크기를 위해 원화와 shadow를 확대/축소하지만 jump height, physics tick, 실제 Player 노드의 shadow alpha 계산은 사용한다.

검수할 항목:

- [ ] 도약 전 idle과 상승 원화의 기준선 변화를 확인한다.
- [ ] 상승 후보에서 양쪽 부츠가 모두 지면에서 떨어져 읽히는지 본다.
- [ ] 상승·정점·하강 동안 원화의 높이와 GroundShadow가 분리되어 읽히는지 확인한다.
- [ ] 무릎과 부츠 방향이 상승 실루엣에서 자연스러운지 확인한다.
- [ ] 우향/좌향 캡처가 단일 수평 미러인지, 좌향에서 표식이 중복 반전되지 않았는지 본다.
- [ ] 착지 시 실제 Player 상태는 지면 높이 0과 shadow alpha 0.42로 복귀하며, 별도 팝은 검수 표식임을 구분한다.

## 캡처와 확인

GUI 환경에서 실행한다. headless 실행은 Window post-draw 증거가 아니다.

```powershell
godot --path . --script res://tools/capture_player_jump_motion_review.gd
godot --headless --path . --script res://tests/player_candidate_motion_smoke.gd
```

캡처 결과: `assets/art/review/player_jump_motion_strip.png` (1920×2000, 10개 실제 Window post-draw 프레임). 각 로그의 `JUMP_SAMPLE`에는 상태, 방향, 물리 시각/틱, jump height, 수직 속도, shadow alpha 및 post-draw 완료 여부가 남는다. `JUMP_MOTION_CAPTURE`의 landing과 총 경과시간은 실제 Player 업데이트가 완료된 경우에만 출력된다.

현재 점프 설정 기준 예상 관측점: 상승 0.100초 / 높이 46.67px, 정점 약 0.450초 / 높이 115.50px, 하강 0.750초 / 높이 57.49px, 착지 0.883초. 이는 캡처 실행값이며 원화 프레임 시간이 아니다. 실제 검수 전에는 캡처와 smoke가 완료돼도 시각 승인 상태는 미정으로 유지한다.