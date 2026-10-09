# Player 점프 전환 검수 게이트

## 결과와 후보 확보 상태

`tools/capture_player_jump_transition_gate.gd`는 독립 review rig에서 실제 `scripts/player/player_controller.gd`의 `_start_jump()`와 `_update_jump()`를 사용해 한 번의 연속 점프를 진행한다. Player physics process만 끄고 프로젝트 tick(60Hz)에 맞춰 해당 점프 함수를 직접 한 번씩 갱신한다. 각 phase는 실제 1920×1080 Window에서 `RenderingServer.frame_post_draw` 이후 읽었다. 좌향은 동일한 `VisualRoot.scale.x`만 반전했다.

실행에서 후보 존재 여부는 독립 확인됐다.

| 원화 | 경로 | 상태 | 검수 rig 표시 |
|---|---|---|---|
| rise safe | `assets/art/player/elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png` | 있음, 상승 전용 미승인 후보 | 상승 phase |
| fall candidate | `assets/art/player/elven_fighter_jump_fall_v1_candidate_1254x1254.png` | 있음, 별도 미승인 후보 | 하강 phase |
| 정점 원화 | 별도 승인 프레임 없음 | 미확보/미승인 | idle 실루엣 절차 proxy |
| 착지 원화와 착지 pop | 별도 승인 프레임 및 Player pop 없음 | 미확보/미구현 | fall 후보 실루엣 + 검수 전용 십자 마커 |

Fall 후보가 존재해 하강에서는 그 파일을 보여준다. 절차 proxy는 정점에만 사용한다. 어느 후보도 승인 원화로 취급하지 않는다. rise 한 장이나 fall 한 장만으로 완성된 점프 애니메이션이라고 판정하지 않는다.

## 실제 Window 캡처 기록

캡처 이미지: [`assets/art/review/player_jump_transition_gate.png`](../../assets/art/review/player_jump_transition_gate.png), 1920×2000. Window crop 640×500을 3열로 배치한 10개 실제 post-draw 프레임(5 phase × 우향/좌향)이다. 플레이어 아트 캔버스는 모든 phase에서 같은 192×192 게임 배율(1254 원본 픽셀을 192px로 축소)로 표시했다.

Godot 4.7.2 / physics tick 1/60초에서 takeoff부터 착지까지 53 tick, 0.8833초가 걸렸다. 아래 발 anchor는 GroundShadow가 놓인 Player root의 지면선 기준 y 오프셋이며 음수는 발이 지면선 위에 있다는 뜻이다. silhouette bounds는 192px 캔버스에서 alpha 0.05 이상인 픽셀의 경계 상자다. `phase boundary Δ`는 직전 phase에서의 anchor 및 경계 상자 변화다. 우향과 좌향의 수직 값은 동일했다.

| 경계 phase | 경과/tick | 높이 offset | vy | 양방향 shadow α | 발 anchor y | silhouette bounds (x,y,w,h) | 이전 phase 대비 anchor / bounds 변화 | authored pop |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| 도약 전 idle | 0.000s / 0 | 0.00px | 0.00px/s | 0.420 | -43.00px | (51,22,100,149) | 기준 | 없음 |
| 상승 / rise safe | 0.100s / 6 | 46.67px | -416.66px/s | 0.342 | -92.67px | (55,19,103,149) | -49.67px / +3×0px | 없음 |
| 정점 / idle proxy | 0.450s / 27 | 115.50px | +3.35px/s | 0.228 | -158.50px | (51,22,100,149) | -65.83px / -3×0px | 없음 |
| 하강 / fall 후보 | 0.750s / 45 | 57.49px | +363.35px/s | 0.324 | -86.49px | (49,3,117,182) | +72.01px / +17×+33px | 없음 |
| 착지 / 검수 마커 | 0.883s / 53 | 0.00px | 0.00px/s | 0.420 | -29.00px | (49,3,117,182) | +57.49px / 0×0px | 없음; 마커만 표시 |

모든 전환의 수치 차이는 기록했지만 이 값만으로 팝의 시각적 수용 여부를 판정하지 않는다. rise에서 도약 전으로부터 생기는 anchor 이동은 physics 높이와 후보 pose의 alpha 경계가 함께 반영된 값이다. phase 캡처는 한 번의 연속 clock 샘플이며 각 phase를 시간 정지 애니메이션 프레임으로 보간하지 않았다.

## 승인 및 비변경 경계

- [ ] rise와 fall 후보 모두 192px 크기에서 같은 캐릭터의 점프 연속 포즈로 읽히는지 확인한다.
- [ ] 정점 원화를 별도 검수·승인하기 전에는 apex proxy를 완성 pose로 처리하지 않는다.
- [ ] 착지 프레임과 실제 Player 착지 pop을 별도 검수·승인하기 전에는 완성 루프로 처리하지 않는다. 십자 표시는 검수용 절차 marker다.
- [ ] 우향/좌향 반전, shadow 분리, 발 anchor와 phase 경계 이동/크기 변화를 확인한다.

이 작업은 Player physics 설정, animation manifest, 승인 프레임 데이터 또는 원화 후보를 수정하지 않았다. 캡처용 isolated rig와 review 산출물만 추가했다. 승인 상태는 검수 전까지 미정이다.

## 재현

실제 Window 캡처는 GUI renderer에서 실행한다. headless 캡처는 실제 창 증거로 인정하지 않는다.

```powershell
godot --path . --script res://tools/capture_player_jump_transition_gate.gd
godot --headless --path . --script res://tests/player_jump_transition_gate_smoke.gd
```

캡처 로그는 각 방향/phase에서 elapsed time, tick, jump height/velocity, shadow alpha, 192px silhouette bounds, foot anchor, phase 경계 delta, authored pop 여부와 marker 여부를 남긴다. 스모크 스크립트는 rise/fall 후보 존재 확인을 분리하고 저장된 이미지 크기 및 원화 상태 표시를 검사한다.
