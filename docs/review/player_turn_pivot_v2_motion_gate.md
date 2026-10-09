# Player turn pivot v2 motion gate

## 캡처 조건

- Godot 4.7.2, OpenGL Compatibility, windowed 실행. 메인 Player 씬을 그대로 instantiate하고 실제 render framebuffer 1920×1080을 `RenderingServer.frame_post_draw` 뒤에 캡처했다.
- `PlayerArt`와 기존 `VisualAnimator`만 검수 장면에서 제어했다. Player 본편 상태, 물리, manifest는 수정하지 않았다. turn 시계는 본편 값 0.13초이며 방향 flip 경계는 windup 0.040초 + compression 0.025초다.
- 8개 샘플: idle, anticipation, 0.055초 mid, 0.065초 flip, 0.13초 settle, 반대 방향 전환, turn 중 역입력, `receive_hit` 피격 취소.
- v1은 `elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png` 원본을 mid 컷의 검수용 Player Sprite에만 잠시 표시했다. 같은 이름의 safe 파생물은 사용하지 않았다. turn v2 원본 파일은 확보되지 않아 v2 컷은 생략했다.
- 노랑 십자/수평 기준선은 Player 위치와 지면 기준, 청록 표식은 v1 골반 추정점, 산호색은 두 부츠 추정점, 노랑 점은 본편 combat foot anchor다. 골반 및 부츠 위치는 원본 이미지에서 지정한 검수 landmark이며 자동 관절 추적값이 아니다.

## 측정

alpha는 원본 texture에서 α≥0.05인 바운딩 박스로 측정했다. 월드 좌표와 스케일은 본편 Sprite/Animator 값이다.

| 샘플 | Turn 진행 | alpha bounds (px) | Sprite scale | 회전축 원점 (px) | combat foot anchor (px) | 방향 / Sprite flip_h |
|---|---:|---:|---:|---:|---:|---|
| Idle 우향 | 1.000 | 333,148 · 652×965 | 0.4469, 0.4469 | 960.0, 550.0 | 960.0, 790.0 | 우 / false |
| Anticipation | 0.154 | 333,148 · 652×965 | 0.4392, 0.4557 | 965.9, 545.4 | 960.0, 790.0 | 우 / false |
| Mid v1 원본 | 0.423 | 321,43 · 735×1160 | 0.4186, 0.4738 | 857.0, 516.7 | 960.0, 790.0 | 우 / false |
| Flip 경계 | 0.500 | 333,148 · 652×965 | 0.4337, 0.4592 | 962.9, 543.4 | 960.0, 790.0 | 좌 / false |
| Settle | 1.000 | 333,148 · 652×965 | 0.4474, 0.4464 | 961.7, 550.3 | 960.0, 790.0 | 좌 / false |
| 방향 전환 좌→우 | 0.577 | 333,148 · 652×965 | 0.4484, 0.4454 | 968.3, 551.0 | 960.0, 790.0 | 우 / false |
| 역입력 좌→우→좌 | 0.269 | 333,148 · 652×965 | 0.4228, 0.4743 | 947.5, 535.6 | 960.0, 790.0 | 좌 / false |
| 피격 취소 | 1.000 | 333,148 · 652×965 | 0.4371, 0.4546 | 960.5, 545.9 | 960.0, 790.0 | 좌 / false |

기본 idle alpha 크기는 원본 1254px 캔버스 대비 52.0%×77.0%, v1 mid는 58.6%×92.5%다. source shape 차이만으로 v1 alpha 높이가 20.2% 커진다. 본편 scale은 turn 중 x축 최저 −6.3%, y축 최고 +6.1%까지 변해 squash/stretch가 보이며, combat anchor는 모든 상태에서 고정됐다. Sprite 노드 원점은 회전 보정으로 움직이고, 특히 v1 texture 교체 때에는 추정 지지발 정렬 때문에 이동하므로 이를 고정 회전축으로 오해하지 않도록 표에 따로 기록했다.

v1 수동 landmark 결과는 골반 (861.7, 551.4), 부츠 A (813.3, 758.0), 부츠 B (960.0, 790.0), 본편 foot anchor (960.0, 790.0)이다. 부츠 B를 지지발로 정렬했을 때 부츠 A는 32px 위에 남는다. 자세도 팔을 들고 다리를 앞뒤로 벌린 달리기/보폭 형태다. 따라서 v1은 idle↔turn mid 연결 원화로 **미수용**이며, v2 원본이 없어 v2는 **미검수**다. 지지발 고정은 본편 절차에서 유지되지만, 후보 원화 자체의 지지발 일관성을 충족하지 못한다.

## 판정 및 산출물

- 캡처: [player_turn_pivot_v2_window.png](../../assets/art/review/player_turn_pivot_v2_window.png)
- 본편 방향 전환, 역입력 재타깃, `receive_hit`의 hitstun 취소가 turn timer에 반영됨을 확인했다. flip은 parent `VisualRoot`에서만 적용되며 `PlayerArt.flip_h=false`라 중복 mirror는 없다.
- v2 미확보: `assets/art/player/elven_fighter_turn_rear_mid_v2_candidate_1254x1254.png`가 없다. v1 및 기존 procedural 절차만 기록했다.
- #115 safe 산출물은 참조하지 않았다. 검수용 파일 외 본편 상태/물리/manifest 변경은 없다.
