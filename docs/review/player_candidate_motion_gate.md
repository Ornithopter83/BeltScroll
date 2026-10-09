# 플레이어 원화 동작 검수 게이트

## 범위와 승인 상태

`scenes/review/player_candidate_motion.tscn`은 본편 게임과 분리한 원화 검수 장면이다. Player 씬과 `data/art/animation_manifest.json`을 수정하거나 승인 상태를 높이지 않는다. 승인 원화와 미승인 후보를 한 화면에서 비교할 수 있지만 각 상태는 원본 승인 기록을 그대로 표시한다.

| 상태 | 표시 원화 | 한 장 표시 시간 |
|---|---|---:|
| idle 승인 | `elven_fighter_reference_v8_clean_candidate_1254x1254.png` | 0.800초 (manifest idle) |
| run 후보 | run stride v1, v2 반대 보폭 | 각 0.120초, 검수 루프 배정; 두 장 0.240초 |
| jump 후보 | jump rise v1 | 0.300초 검수 표시값; 실제 동작 시간 미확정 |
| attack startup 후보 | 1타 startup v1, 3타 startup v1 | 각 0.075초, 0.100초 (manifest 임시 startup 시간) |
| 승인 attack contact | 1타 contour, 2타 v4 ink, 3타 v2 contour | 각각 0.105초, 0.120초, 0.140초 (manifest) |
| Num4 전방 돌진 접촉 | `elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png` | 0.120초 검수 표시값; 실제 동작 시간 미확정 |

검수 장면에서 임시 표시 시간을 사용하는 run/jump는 출처와 미확정 상태를 UI에 표시한다. 정지 원화 한 장은 실제 동작 주기를 측정할 수 없다. 모든 항목은 원화 한 장을 지정 시간 동안 고정 표시하며 프레임 사이 보간을 하지 않는다. 192×192 게임 캔버스 기준으로 alpha 실루엣 높이를 192px에 맞추고 3배(576px) 확대한다. 노란 표시는 alpha 5% 이상 픽셀의 하단 연속 구간 중앙이며, 민트 표시는 run 문서에서 수동 지정한 지지발 후보이다. alpha 경계점이 지지발의 확정값을 뜻하지 않는다.

## 조작

- 숫자 1–5: idle, run, jump, attack startup, 승인 contact 상태 선택
- 위/아래: 상태 선택, 좌/우 화살표: 해당 상태의 다음/이전 원화
- A/D: 좌향/우향, Space: 재생/중단
- 확보된 Num4 전방 돌진 접촉 후보는 숫자 키패드 4로 바로 선택할 수 있다.
- Num4 후보는 파일 `assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png`가 확보되어 현재 선택할 수 있다. 파일이 없는 환경에서는 Num4 버튼을 비활성화하고 `원화 미확보`를 표시한다.

## Window 캡처와 검사

실제 GUI Window에서 3개 검수 상태를 우향·좌향으로 렌더링해 post-draw 캡처 스트립을 만든다.

```powershell
godot --path . res://scenes/review/player_candidate_motion.tscn -- --review-capture
```

출력은 `assets/art/review/player_candidate_motion_strip.png`이며 타일은 idle 대신 run, jump, 승인 contact의 우/좌향 창 캡처다. 자동 캡처 경로는 headless 성공을 근거로 삼지 않는다. 상태 선택, 원화 전환, 좌우 반전, 중단 유지, 필수 원화 누락 및 manifest 불변 검사는 다음 smoke로 실행한다.

```powershell
godot --headless --path . --script res://tests/player_candidate_motion_smoke.gd
```

Smoke는 확보된 Num4 후보, 기존 승인 원화와 후보 파일 누락, 상태 전환 및 manifest 불변을 확인한다. 동작의 시각 품질이나 후보 승인을 자동화하지 않는다.
