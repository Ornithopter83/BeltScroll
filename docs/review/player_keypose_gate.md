# Player 키포즈 검수 게이트

## 승인 상태

v8 clean 정지 원화 `assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png`는 본편에 적용 승인된 상태다. 이 승인은 정지 원화에만 해당한다. v2 키포즈 원본과 신규 relayout 후보는 별도 검수 중이며, Player 씬·VisualAnimator·프레임 애니메이션에는 연결하지 않는다.

원본 `assets/art/player/elven_fighter_attack_keyposes_v2_1254x1254.png`는 수정하지 않았다. 독립 정렬 후보는 `assets/art/player/elven_fighter_attack_keyposes_v2_relayout_1254x1254.png`이고, 192px 전후 비교판은 `assets/art/review/player_keyposes_v2_relayout_contact.png`다. 비교판의 각 포즈에는 BEFORE, RELAYOUT, V8 CLEAN을 각각 192×192px 표시 상자에 담았다.

## 재현 및 기계 검사

```powershell
godot --headless --path . --script res://tools/rebuild_player_keyposes_v2.gd
godot --headless --path . --script res://tests/player_keypose_relayout_smoke.gd
```

재구성 도구는 1254×1254 RGBA PNG의 네 627×627 셀을 따로 처리한다. alpha 5% 기준 8방향 연결 성분을 찾아 가장 큰 인물 실루엣에 비해 작은 분리 성분만 제거한다. 두 번째 셀에서 분리된 조각 645px와 작은 투명 배경 파편을 제거했다. 그 밖의 인물 픽셀은 보간 전 각 셀의 실제 alpha 경계 상자에서 가져온다. 네 셀 모두에 동일한 0.998322 비율을 적용하고 셀별로 수평 중앙과 공통 발 기준선에 배치한다. 손·발·포니테일을 경계에서 잘라 여백 검사를 통과시키지 않는다.

Smoke 결과: 후보 1254×1254, 셀별 alpha 여백 최소 16px, 네 발 기준선 y=610(셀 안 좌표, 편차 0px), 원본 바이트 보존, 두 번째 셀 분리 파편 제거 규칙, 비교판 파일 생성이 통과했다. 이 검사는 시각 승인이나 신체 누락 복원을 뜻하지 않는다.

## 남은 시각 검수 사항

- 두 번째 포즈의 분리된 주먹 조각과 작은 부유 파편은 연결 성분 기준으로 제거됐다.
- 세 번째 포즈의 원본 alpha 경계가 오른쪽 셀 경계에 닿는다. 재배치 후 후보의 셀 여백은 확보됐지만, 경계 접촉 부근 신체가 원본에서 잘렸는지 여부는 픽셀만으로 복구하거나 승인할 수 없어 미해결로 남긴다.
- 네 번째 포즈의 원본 alpha가 셀 상단에 닿으며, 올린 손/팔이 원본 경계에서 잘려 있다. 후보는 남아 있는 픽셀을 보존해 옮긴 것이므로 손을 복원하지 않았다. 신체 완전성은 미해결이다.
- 네 얼굴 정체성, 귀·포니테일, 의상, 해부학, 공격별 실루엣 및 192px 가독성은 담당자의 비교판 시각 검수를 기다린다.

## 게이트 판정

relayout 후보의 자동 배치 조건은 통과했다. 원본 경계에 닿은 세 번째 포즈와 잘린 네 번째 포즈의 신체 완전성은 미해결이며 시각 승인도 아직 없다. 따라서 신규 키포즈와 애니메이션 연결은 미승인 상태로 유지한다.
