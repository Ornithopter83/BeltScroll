# Player 방향 전환 후보 동작 검수

## 실행 조건

- Godot `4.7.2.stable.mono.official.ed1daf0bf`, 창 모드 `1920×1080`, framebuffer `1920×1080`에서 캡처했다.
- 검수 도구는 실제 `scenes/player/player.tscn`과 `PlayerVisualAnimator`를 인스턴스화한다. `TURN_DURATION = 0.13`, anticipation 0.04초, compression 0.025초, 방향 flip 경계 0.065초를 사용한다.
- 각 표본은 라벨·Sprite가 그려진 다음 `RenderingServer.frame_post_draw`를 기다려 얻었다. 테스트 도구 안에서만 Player 물리를 멈추고 방향 입력과 기존 animator 시계를 단계별로 진행했다. 본편의 이동 속도, 전투 상태, Player 장면, animation manifest는 수정하지 않았다.

## 확인된 원화

전용 원본 `assets/art/player/elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png`가 실제로 존재해 중간 회전 표본에서 검수 Sprite에 한 번만 임시 표시했다. SHA-256은 `43AE0C54EE26ECE7121EC60A265D507877B2CFEA8408026F8BCCD0FF3779DA72`다. 이 PNG는 별도 Godot import 파일이 없어 `Image.load` 후 `ImageTexture`로 읽었다. #110 safe 파생 파일은 참조하지 않았다. 검수 종료 전에 idle Sprite 원본으로 되돌렸으며 후보를 본편에 등록하지 않았다.

idle 기준 원화는 `elven_fighter_reference_v8_clean_candidate_1254x1254.png`이며 방향 전환 전후의 동일 인물·포니테일·녹색 의상·금색 장식과 후보의 3/4 rear pose identity를 육안 비교했다. alpha bounds는 idle `(110,90)-(1144,1164)`로 `1034×1074px`, 회전 후보 `(25,35)-(1208,1254)`로 `1183×1219px`다. 같은 `0.4469` Sprite scale에서 후보 실루엣은 idle보다 폭 약 14.4%, 높이 약 13.5% 크게 표시된다. 본 캡처는 원화 후보를 확인하기 위해 scale과 position을 idle 값 그대로 유지했다. 이 차이는 눈에 띄는 크기 팝이므로 현재 결과만으로 프레임 교체를 승인하지 않는다.

## 캡처 프레임 및 판정 기록

캡처 아틀라스: `assets/art/review/player_turn_candidate_window.png` (1920×1080, 4열×2행).

| 순서 | 상태 | 시계 진행 / facing | 검수 관찰 |
|---|---|---|---|
| 1 | Idle | 0.000초 / 우향 | 원화 기준 크기와 발 기준을 기록했다. |
| 2 | Anticipation | 0.020초 / 아직 우향 | 회전 예비 동작과 압축이 시작됐다. |
| 3 | Mid turn | 0.055초 / 아직 우향 | rear-mid 원화를 검수 Sprite에 임시 표시했다. |
| 4 | Facing flip | 0.075초 / 좌향 | 0.065초 flip 경계를 지난 뒤 한 번만 mirror가 바뀌었다. |
| 5 | Settle | 0.130초 / 좌향 | 기존 방향 전환 시계가 종료되고 기본 자세로 수렴했다. |
| 6 | 반대 방향 mid turn | 0.075초 / 우향 | 좌향에서 우향으로의 flip과 procedural 구간을 확인했다. |
| 7 | 빠른 역입력 | L→R 입력 후 0.035초에 L 재입력 | 진행 중 방향이 재지정되고 첫 flip 전 좌향을 유지했다. |
| 8 | 피격 취소 | turn 0.025초 뒤 hitstun | turn clock이 취소되어 진행도 1.000 / turning false가 됐다. hit 반응 tint와 자세가 나타났다. |

## 발 기준, 팝, mirror 및 회전축

- 표본 모두 Player 발 기준 월드 좌표 `(960, 792)`를 기록했다. 물리는 검수 장면에서 정지시켰으며 플레이어 위치 변화는 없었다. 다만 이는 Player anchor의 고정이다. rear-mid 후보의 alpha-foot 위치는 idle과 별도로 보정하지 않았으며 후보 표본의 지지발 접촉선은 검증되지 않았다.
- idle Sprite scale은 `(0.4469, 0.4469)`이다. turn 구간 최저 가로 scale은 `0.4186`(-6.3%), 최고 세로 scale은 `0.4743`(+6.1%)로 가벼운 압축과 높이 팝이 있다. 빠른 역입력 구간에서 가장 두드러진다. hit 취소 표본의 별도 hit pose scale은 turn pop 측정에서 제외했다.
- 시계의 turn 회전은 idle 기준에서 최대 약 `0.0493 rad`이며 hit recoil 표본은 별도다. Animator의 `_keep_combat_anchor()`가 Sprite의 alpha-foot 기준을 보정해 회전·scale 동안 combat anchor를 유지한다. 발 위치 고정은 성공했지만 후보 원화의 지지발은 실제 공격 접촉점 검증을 거치지 않았다.
- 좌우 반전은 `VisualRoot.scale.x`로만 적용된다. 후보 Sprite의 `flip_h`를 추가로 켜지 않아 이중 mirror는 없다.
- idle과 후보 원화 identity의 큰 특징은 이어지지만, rear-mid 후보는 idle과 시각적 크기 및 발 위치가 완전히 일치하지 않는다. 본편 반영 전에는 alpha-foot 기준점과 축척을 원화별로 확인하고, 중간 프레임 추가 확보 후 연속 재생에서 pop을 다시 판단해야 한다.

## 검수 결과

절차적 전환의 양방향, 중간 후보 원화, 빠른 역입력, 피격 취소를 실제 Godot 창 렌더링으로 확인했다. 후보는 검수 전용이며 본편 등록, 이동 속도 변경, 전투 상태 변경은 없다. 스모크 테스트는 원본 파일 존재, safe 파일 비의존, 0.13초 시계, frame-post-draw, 1920×1080 PNG 크기와 렌더 픽셀을 확인했다.
