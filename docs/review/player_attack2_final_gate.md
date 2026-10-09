# Attack2 v4 ink final candidate review gate

## 대상과 처리 범위

후보 파일은 `assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png`입니다. 입력은 기존 `elven_fighter_attack2_reference_v4_contour_candidate_1254x1254.png`이며, 원본·safe·clean·contour 입력은 이 작업에서 수정하지 않습니다.

복원은 포니테일, 얼굴과 귀, 팔 안쪽, 백피스트 장갑, 양쪽 부츠의 지정 영역에 한정합니다. 먼저 투명 alpha와 맞닿은 실루엣 경계에서 안쪽으로 최대 3px 거리를 계산합니다. 이 경계 띠 안에 있고 투명 경계까지 연결되는 붉은 성분만 처리합니다. 일반 포화도만으로 화면 전체를 보정하지 않습니다. 밝은 정상 피부색과 금색은 보호하고, 나머지 선택 픽셀의 RGB를 가까운 암갈색 윤곽의 국소 중앙값으로 복원합니다. 국소 표본이 모자라면 attack1 final 및 attack3 contour 참조의 실제 알파 경계에서 모은 암갈색 잉크 팔레트에 맞춥니다. 모든 픽셀의 alpha는 그대로 유지하므로 실루엣, 여백, 발 anchor와 자세를 바꾸지 않습니다.

`assets/art/review/player_attack2_v4_ink_final_gate.png`에는 흰색·검정·체커보드·Forest Ruins 배경의 전후 비교, 포니테일·얼굴·팔 안쪽·장갑·양쪽 부츠 확대 비교, 그리고 캐릭터 높이를 192px로 맞춘 네 배경의 전후 비교가 있습니다. 이 판은 원격 HQ 시각 검수용입니다.

## 독립 smoke

```powershell
godot --headless --path . --script res://tools/finalize_player_attack2_ink.gd
godot --headless --path . --script res://tests/player_attack2_ink_final_smoke.gd
```

Smoke는 RGBA8·1254×1254, 네 방향 90px 이상 투명 여백, contour 입력과 보호 입력의 바이트 불변, 실제 alpha 경계 오염 감소, warm skin/gold 색 보존, 모든 alpha 및 실루엣 불변, 수정 좌표 제한, null/잘못된 크기 처리, CLI 오류 코드를 확인합니다. 합성 fixture로 경계 복원과 난색 보호도 확인합니다.

이 후보의 생성 결과는 경계 연결 붉은 성분 1,336개에서 6,204픽셀의 RGB를 국소 잉크 색으로 복원했습니다. 정상색과 alpha는 보존됐고 지정 입력 파일은 바이트 단위로 불변임을 smoke에서 확인했습니다. Godot 실행은 샌드박스 환경의 `user://logs` 쓰기 및 시스템 CA 읽기 진단을 출력하지만 스크립트와 smoke는 정상 종료했습니다.

## 검수 상태

후보와 비교판은 검수 요청을 위한 산출물이며 자동 승인되지 않았습니다. HQ 원격 검수 결과를 별도로 기록하고, 이 작업은 본편 Player·애니메이션 연결이나 원본/safe/clean/contour 교체를 수행하지 않습니다.
