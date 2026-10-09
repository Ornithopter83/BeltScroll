# Jump rise safe candidate review gate

## 산출물과 보존

- 원본: `assets/art/player/elven_fighter_jump_rise_v1_candidate_1254x1254.png`
- safe 후보: `assets/art/player/elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png`
- 비교 보드: `assets/art/review/player_jump_rise_safe_comparison.png`
- 원본 SHA-256: `c10d605c079e90aaa5bb71577651126a74b907ee3a8365940dbb78f8c90c54e3`
- 준비 스크립트는 원본 바이트를 읽기 전후 비교하며, smoke 검사에서도 원본 바이트가 그대로인지 확인한다.
- safe 후보는 별도 파일이다. 기본 Player와 manifest에는 등록하지 않았다.

## 기계 검사

| 검사 | 결과 |
|---|---|
| 캔버스와 포맷 | 1254×1254 RGBA8 통과 |
| 비영점 alpha 경계 상자 | x=102..1151, y=124..1120 |
| 좌/상/우/하 투명 여백 | 102 / 124 / 102 / 133px 통과 |
| 외곽 테두리 alpha | 네 가장자리 완전 투명 통과 |
| alpha=0 픽셀의 RGB | 모두 0 통과 |
| 고립 alpha 픽셀 | 0개 통과 |
| 축소 | 균일 축소 통과; 0.8506× / 0.8506× (alpha 0.05 경계 기준) |
| 보존 특징 | 얼굴, 뾰족귀, 양쪽 장갑, 양쪽 부츠, 포니테일 모두 alpha 존재 통과 |

원본 경계에서 고립된 alpha 픽셀 293개를 제거한 후 축소했다. 재표본화 과정에서 나온 고립 픽셀 89개도 제거했다. 나머지 포즈 픽셀은 균일 비율로 축소했으며 방향이나 관절을 바꾸지 않았다.

## 동일 게임 캔버스 비교

비교 보드는 v8 idle → jump 원본 → jump safe 순서다. 세 이미지를 같은 192×192 게임 캔버스에 놓고 보드에서 각 캔버스를 3배 nearest-neighbor 미리보기로 표시했다. 아래 좌표와 경계 상자는 192px 캔버스 좌상단 기준이며 alpha 0.05를 사용했다. torso 중심은 각 포즈의 중앙 상체 측정 창에서 alpha 가중 y 중심으로 계산했다. 하체 중심은 하단 영역의 alpha 가중 y 중심이며, 다리 굽힘 각도 자체가 아니라 포즈 위치를 비교하는 proxy다.

| 측정값 (px) | v8 idle | jump 원본 | jump safe |
|---|---:|---:|---:|
| 실루엣 경계 상자 x,y,w,h | 42, 12, 117, 171 | 47, 6, 120, 175 | 55, 19, 103, 149 |
| 실루엣 높이 | 171 | 175 | 149 |
| 상체 창 alpha 중심 y | 87.39 | 83.71 | 83.41 |
| 하체 alpha 중심 y | 129.29 | 124.51 | 120.10 |
| 최저 실루엣 발 anchor x,y | 151, 182 | 51, 180 | 59, 167 |
| 전체 실루엣 alpha 중심 x,y | 99.40, 91.31 | 107.14, 83.71 | 106.70, 84.67 |

Jump 원본의 전체 실루엣 중심은 v8 idle보다 오른쪽 7.75px, 위쪽 7.60px 이동했다(벡터 길이 약 10.85px). 최저 anchor y는 idle보다 2px 위다. Safe 적용은 원본의 포즈를 유지하면서 게임 캔버스에서 보이는 크기를 줄인다. safe의 최저 anchor는 원본 대비 오른쪽 8px, 위쪽 13px이며 전체 중심 이동은 -0.44px, +0.97px다. anchor는 최저 실루엣 점 하나만 요약하므로 양쪽 발을 각각 판정하지 않는다.

## 사람 검수 — 승인 전 확인 필요

- [ ] 도약 프레임에서 양발이 모두 지면에서 떨어져 보이는지 확인한다. 원본 최저 anchor가 idle과 2px 차이라 체공 여부는 이 수치만으로 확정하지 않는다.
- [ ] 얼굴, 귀, 장갑, 양쪽 부츠, 포니테일이 게임 크기에서도 기존 elven fighter와 같은 인물로 읽히는지 확인한다.
- [ ] 다리 굽힘과 천 꼬리 실루엣이 점프 상승 동작으로 자연스러운지 확인한다.
- [ ] 승인 뒤에도 별도 지시 전까지 후보를 기본 Player 또는 manifest에 등록하지 않는다.

## 재현

```powershell
godot --headless --path . --script res://tools/prepare_player_jump_rise_safe.gd
godot --headless --path . --script res://tests/player_jump_rise_safe_smoke.gd
```

두 명령은 이 작업에서 실행했고 smoke 기계 검사는 통과했다. 실행 환경이 `user://logs` 기록과 Windows 인증서 저장소에 대한 경고를 출력했지만 두 스크립트는 정상 완료했다. 위 사람 검수 항목은 미완료 상태다.
