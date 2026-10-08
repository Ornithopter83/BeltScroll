# Player keypose review gate

## 검사 절차

검수 도구는 원본 PNG를 읽기만 하며 입력 이미지를 저장하거나 수정하지 않는다. 기준 비교 이미지는 `assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png`이며 파일 이름 그대로 아직 후보 원화다. 프로젝트에는 승인 완료로 확인된 별도 v8 clean 원화가 없다. 새 키포즈 승인 시 승인된 원화 경로를 `--reference`로 명시한다.

```powershell
godot --headless --path . --script res://tools/inspect_player_keyposes.gd -- res://path/to/player_keyposes.png
godot --headless --path . --script res://tools/inspect_player_keyposes.gd -- res://path/to/player_keyposes.png --reference res://path/to/approved_v8_clean.png --output res://assets/art/review/player_keyposes_contact.png --foot-anchors 188,188,188,188
```

입력 시트는 RGBA PNG의 균등한 2×2 배열이어야 하며, 기본 셀 크기는 192×192px이다. 각 셀마다 크기, 유효 alpha 경계, 바깥 분할선 침범, alpha 안전 여백, 셀 경계 잘림, 발 기준선을 독립 판정한다. 기본 발 기준선 검사는 네 셀 alpha 최하단 편차가 2px 이내인지 확인한다. 자세에 따라 발 위치가 다르면 `--foot-anchors`로 좌상·우상·좌하·우하 셀의 셀 내 y 좌표를 제공한다. `--foot-tolerance`와 `--margin`은 픽셀 단위다.

각 포즈는 투명 여백을 제외한 alpha 경계 상자에 맞춰 192×192 비교 타일로 축소되고, 기준 원화도 실루엣에 맞춰 같은 크기 상자에 놓인다. contact sheet의 회색 바둑판은 투명 영역 확인용이다. 종료 코드는 정상 0, 이미지 검수 실패 1, 인수·파일 처리 실패 2다.

## 승인 게이트

- 자동 검수 PASS는 시트 크기와 배치만 승인한다. 얼굴 정체성, 복장 세부, 손·팔다리·관절을 포함한 해부학 일치는 contact sheet를 보고 사람이 수동 승인해야 한다.
- 수동 승인자가 이름과 날짜를 기록하고 승인된 clean 원화를 비교 경로로 지정하기 전까지 Player 씬, VisualAnimator, 프레임 애니메이션에 키포즈를 연결하지 않는다.
- 승인 원화 또는 입력 시트가 저장소에 없으면 contact sheet의 비교 후보 표시와 검수 대기 상태를 유지한다.

## 합성 smoke

`tests/player_keypose_pipeline_smoke.gd`는 Godot 리소스 파일에 의존하지 않고 메모리에서 RGBA fixture를 만든다. 정상·잘못된 크기·셀 여백·셀 경계 침범·발 anchor·검수 종료 코드와 192px 비교 contact sheet 구성을 검사한다. 실행 명령:

```powershell
godot --headless --path . --script res://tests/player_keypose_pipeline_smoke.gd
```

## 현재 승인 상태

- 입력 2×2 키포즈 원화: 아직 제공되지 않음.
- v8 clean 원화: 저장소의 `clean_candidate`를 임시 기본 비교 대상으로 설정; 사람 승인 전.
- 얼굴·복장·해부학 일치: 사람의 시각 검토 및 승인 대기.
- Player 씬 / VisualAnimator / 프레임 애니메이션: 승인 대기 상태 그대로.
