# Attack 3 safe identity 검수 게이트

## 검수 대상과 처리 범위

`assets/art/player/elven_fighter_attack3_reference_v1_safe_1254x1254.png`는 확보된 attack3 v1 원화를 원본 보존 방식으로 1254×1254 RGBA 캔버스에 맞춘 safe 검수본입니다. 전체 alpha 실루엣을 중심의 1074px 상자 안에 배치해 각 방향에 최소 90px 투명 여백을 확보합니다. 원본 크기보다 실루엣이 클 때에만 비율을 유지해 축소합니다. 이 처리는 픽셀을 그리거나 지우거나 복원하지 않으며, 원본 PNG는 바이트 단위로 보존합니다.

검수판 `assets/art/review/player_attack3_identity_gate.png`는 원본, safe, 승인된 v8 clean을 흰색·검정·체커보드·Forest Ruins 배경으로 나란히 비교하고, 아래쪽에 attack3 safe와 v8 clean의 실루엣 높이를 각각 192px로 맞춰 발 바닥 기준선을 정렬한 비교 줄을 둡니다.

원격 attack3 원화는 v8과 복장이 다릅니다. 허벅지가 노출되는 짧은 의상과 다른 상체 디자인이 원본에 보입니다. 이 차이를 고치거나 v8 복장을 복원한 것으로 판정하지 않습니다.

## 독립 identity 체크

- 얼굴과 귀의 특징이 attack3 원본에서 읽히는지 기록합니다.
- 포니테일의 실루엣과 묶음 장식이 원본과 일치하는지 기록합니다.
- 상의의 형태·목 장식·색상 배치가 원본의 별도 디자인으로 보존됐는지 기록합니다.
- 긴 바지는 원본에 존재하지 않으며, 허벅지 노출과 짧은 의상을 v8 긴 바지로 오판하거나 복원 요구로 바꾸지 않습니다.
- 부츠와 다리의 원본 실루엣을 확인합니다. 잘리지 않은 손발이나 없는 디테일을 보충했다고 판정하지 않습니다.
- 위로 뻗은 주먹의 위치, 장갑 실루엣과 팔 연결을 독립적으로 확인합니다.

체크 항목별 관찰 결과와 승인 결정은 검수자가 별도로 기록합니다. 이 준비 작업은 아트 승인, 공격 프레임 확정, 본편 Player/애니메이션 연결을 수행하지 않습니다.

## 재현 및 smoke

```powershell
godot --headless --path . --script res://tools/prepare_player_attack3.gd
godot --headless --path . --script res://tests/player_attack3_art_smoke.gd
```

Smoke는 safe 규격·RGBA·최소 투명 여백·alpha 경계·정규화 결과 픽셀 일치·원본 바이트 보존, 검수판 크기, null 입력 처리, 안정된 오류 코드와 잘못된 인자 종료 코드를 확인합니다. 통과 결과는 시각 identity 검수나 아트 승인을 대체하지 않습니다.
