# Player 키포즈 검수 게이트

## 비교 기준과 승인 범위

본편에는 v8 clean 정지 원화가 승인되어 적용되어 있다. 현재 경로는 `assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png`이며, `scenes/player/player.tscn`이 이 원화를 사용한다. `candidate`는 파일 경로에 남아 있는 이름이고 본편 정지 원화의 현재 적용 상태를 뜻하지 않는다.

이 승인은 정지 원화에만 해당한다. 신규 2×2 키포즈 시트와 애니메이션 연결은 아직 승인되지 않았다. 자동 검수나 contact 생성은 승인 상태를 바꾸지 않는다. `assets/art/player/elven_fighter_attack_keyposes_v2_1254x1254.png`가 제공되어 자동 검수와 contact 비교를 마쳤으며, 현재 결과는 실패·미승인이다. 담당자는 얼굴 정체성·귀·포니테일·의상·해부학·공격별 실루엣·발 기준선·192px 가독성을 contact에서 확인하고 별도로 승인해야 한다.

## 검사 절차

검수 도구는 원본 PNG를 읽기만 하며 입력 이미지나 비교 원화를 저장·수정하지 않는다. 입력은 투명 alpha 채널이 있는 정사각형 PNG이며, 같은 크기의 셀 네 개로 이루어진 균등한 2×2 배열이어야 한다. 셀 크기는 고정하지 않고 입력에서 계산한다. 384×384 입력은 192px 셀, 1254×1254 입력은 627px 셀, 2048×2048 입력은 1024px 셀로 판정한다.

각 셀에 대해 실제 크기, 유효 alpha 경계, 투명 여백, 셀/격자 경계 접촉 및 잘림 징후, 발 기준선을 개별 판정한다. 기본 발 기준선 검사는 네 셀 alpha 최하단 편차가 2px 이내인지 확인한다. 자세별 발 위치가 다르면 `--foot-anchors`에 좌상·우상·좌하·우하 셀의 셀 내부 y 좌표를 지정한다. `--foot-tolerance`와 `--margin`은 원본 셀 픽셀 단위다.

각 포즈는 투명 여백을 제외한 alpha 경계 상자에 맞춰 최대 192×192px 상자에 비율을 유지해 배치한다. 본편 승인 v8 clean 정지 원화도 같은 192×192px 표시 상자에 배치한다. 실제 입력 셀 크기와 무관하게 contact에서 두 이미지의 표시 크기는 동일하다. 투명 영역 뒤의 회색 바둑판은 alpha 여백 확인용이다.

```powershell
godot --headless --path . --script res://tools/inspect_player_keyposes.gd -- res://path/to/player_keyposes_1254x1254.png
godot --headless --path . --script res://tools/inspect_player_keyposes.gd -- res://path/to/player_keyposes.png --reference res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png --output res://assets/art/review/player_keyposes_v2_contact.png --foot-anchors 612,612,612,612
```

종료 코드는 정상 0, 검수 실패 1, 인수·파일 처리 실패 2다. 보고서에는 `INPUT_MISSING`, `INVALID_DIMENSIONS`, `GRID_INTRUSION`, `FOOT_BASELINE_ERROR` 등의 실패 코드가 함께 출력된다. `PASS`는 기하 검사를 통과했다는 뜻이며 사람의 키포즈 승인 표시는 아니다.

## 합성 smoke

`tests/player_keypose_pipeline_smoke.gd`는 메모리에서 384×384, 1254×1254, 2048×2048 RGBA fixture를 생성해 검사한다. 입력 부재, 잘못된 차원, 격자 침범, 기준선 오차 실패 코드와 alpha·여백·실제 셀 크기·contact 생성을 확인한다.

```powershell
godot --headless --path . --script res://tests/player_keypose_pipeline_smoke.gd
```

## 현재 승인 상태

- v8 clean 정지 원화: 본편 적용 승인.
- 신규 2×2 키포즈 입력: `assets/art/player/elven_fighter_attack_keyposes_v2_1254x1254.png` 제공됨. 자동 검수 실패 (`FOOT_BASELINE_ERROR`, `GRID_INTRUSION`, `ALPHA_MARGIN_ERROR`); 실패 결과를 담은 contact는 `assets/art/review/player_keyposes_v2_contact.png`.
- 비교 결과: 얼굴 정체성·귀·포니테일·의상은 192px 표시에서도 v8과 대체로 연속성이 보인다. 다만 2번 포즈 아래쪽에 분리된 주먹 조각이 있고, 3번 포즈가 셀 경계에 닿으며, 4번 포즈의 유효 alpha 경계가 셀 좌상단에 닿는다. 네 포즈의 alpha 최하단 편차는 36px로 기본 2px 허용치를 넘는다. 공격 포즈 실루엣의 차이는 읽히지만 경계 침범과 분리된 파편 때문에 현재 시트는 가독성·배치 기준에 부적합하다.
- 신규 키포즈 및 애니메이션 연결: 미승인. 위 경계·여백·기준선 실패와 담당자 시각 검수가 해결될 때까지 Player 씬 / VisualAnimator / 프레임 애니메이션에 연결하지 않는다.
