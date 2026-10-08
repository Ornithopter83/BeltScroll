# Attack 1 최종 matte 시각 검수 게이트

## 검수 대상

`assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png`는 Attack 1 정지 원화의 새 clean 후보입니다. 흰색·검정·체커보드·Forest Ruins 배경, 얼굴·주먹/팔·포니테일 확대, 192px 크기 전후 샘플은 `assets/art/review/player_attack1_final_gate.png`에 있습니다. 비교는 기존 clean 후보와 새 후보를 나란히 보여 주며, v8 clean 샘플은 192px 줄에 윤곽 참고용으로 포함했습니다.

이 후보는 시각 승인 전이며 본편 Player 씬, VisualAnimator 또는 프레임 애니메이션에 연결하지 않습니다. 공격 원본, safe 및 기존 clean 후보는 수정하지 않았습니다.

## 재현 및 독립 smoke

```powershell
godot --headless --path . --script res://tools/refine_player_attack1_matte.gd
godot --headless --path . --script res://tests/player_attack1_final_matte_smoke.gd
```

처리기는 1254×1254 입력 규격과 alpha 경계 상자를 검사합니다. alpha는 모든 픽셀에서 그대로 유지합니다. 투명 경계를 접한 반투명 픽셀은 주변 불투명 전경색과 비교해 붉은 색상 이탈이 확인될 때 RGB만 복원하고, 불투명 경계 픽셀은 포화된 빨강 이탈과 주변 불투명 색상 합의가 함께 있을 때만 복원합니다. 국소 색상은 가까운 불투명 샘플의 robust medoid를 사용해 피부·갈색 머리카락·금색 장식 경계의 혼색을 만들지 않습니다.

Smoke는 후보 규격·RGBA·최소 90px 여백, 원본/safe/기존 clean 바이트 보존, alpha 및 전체 실루엣 고정, 윤곽 stain 감소, edge RGB 국소 변경, 합성 반투명/불투명 stain 복구와 금색/피부 보존, 누락 경로·덮어쓰기·잘못된 캔버스의 오류 코드를 확인합니다. Smoke 통과는 시각 승인을 대신하지 않습니다.

## 시각 승인 체크

- 네 배경에서 머리카락, 팔, 주먹 외곽의 붉은 테두리나 밝은 fringe가 남지 않았는지 확인합니다.
- 얼굴 피부, 귀, 포니테일 가닥과 매듭, 금색 장식의 색과 윤곽이 유지됐는지 확대 비교합니다.
- 전방 주먹과 팔의 실루엣 및 손가락 모양, 양쪽 발 anchor가 보존됐는지 확인합니다.
- 192px 비교에서 공격 포즈의 가독성과 가장자리 halo 여부를 확인합니다.

### 판정

자동 검사는 matte 후보의 픽셀/규격 조건을 확인합니다. 위 항목의 시각 승인은 아직 대기 중이며, 승인 전에는 본편 연결을 진행하지 않습니다.
