# Attack 1 최종 matte 시각 검수 게이트

## Attack 2 v4 윤곽 복원 후보

`assets/art/player/elven_fighter_attack2_reference_v4_contour_candidate_1254x1254.png`는 기존 v4 clean 후보의 국소 윤곽 복원본입니다. 전후 비교, 흰색·검정·체커보드·Forest Ruins 배경, 포니테일·얼굴/귀·어깨/팔·주먹·양쪽 부츠 확대, 192px 비교는 `assets/art/review/player_attack2_v4_contour_gate.png`에서 확인합니다. Attack 1 직선 펀치와 Attack 3 어퍼컷 비교는 기존 `player_attack2_v4_gate.png`를 참고합니다.

복구 도구는 clean만 읽고 새 contour 후보를 씁니다. 포니테일, 얼굴/귀, 어깨와 공격 팔/주먹, 양쪽 부츠 주변의 지정 구역에서 붉은 색상 이탈을 판정합니다. 구역 안 반투명 붉은 fringe는 alpha 0으로 제거하고, 불투명 붉은 얼룩은 가까운 불투명 비오염 픽셀의 채널별 중앙값 색으로 복원합니다. 이 처리로 원본·safe·clean 파일은 변경되지 않습니다.

```powershell
godot --headless --path . --script res://tools/repair_player_attack2_v4_contour.gd
godot --headless --path . --script res://tests/player_attack2_v4_contour_smoke.gd
```

독립 smoke는 PNG 디코드, RGBA8/1254×1254 규격, 사방 90px 투명 여백, 입력 바이트 보존, 복구 재현성, 오염 감소, 지정 구역 밖 픽셀 보존, alpha 실루엣 제한, 얼굴 내부·바지·장갑·금장식·발 anchor 보존, 오류 코드 및 합성 fixture를 검사합니다. smoke 성공은 시각 승인을 뜻하지 않습니다.

이 후보는 시각 검수 대기 상태이며 본편 Player 씬, 애니메이터 또는 프레임 애니메이션에 연결하지 않습니다. 외곽의 붉은 잔상이 배경별 확대와 192px 비교에서 사라졌는지, 포니테일 가닥·귀·얼굴선·공격 실루엣·장갑과 금장식·양쪽 발 anchor가 온전한지 검수 후 승인합니다.

### Attack 2 v4 판정

자동 smoke 통과 뒤에도 시각 승인은 대기 중입니다. 승인 전에는 본편 연결을 진행하지 않습니다.

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
