# Num4 돌진 접촉 safe 후보 검수 게이트

## 산출물과 원본 보존

- 원본: `assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png`
- 별도 safe 후보: `assets/art/player/elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png`
- 비교 보드: `assets/art/review/player_skill1_rush_safe_comparison.png`
- 원본 SHA-256: `cf9fdabd1db74d298bbd2f102ab4a40302da152d4990698b763d7ebcde4fcfc1`
- 준비 스크립트는 읽은 원본 바이트를 생성 후 다시 대조하고, smoke도 SHA-256과 바이트 불변을 확인한다. 원본 파일은 수정하지 않았다.
- 후보는 별도 경로에만 만들었다. 본편 Player, manifest, allowlist에는 등록하지 않았다.

## 기계 검사 결과

| 항목 | 결과 |
|---|---|
| safe 캔버스 / 포맷 | 1254×1254 RGBA8 통과 |
| 원본 alpha 경계 (alpha > 0) | x=25..1252, y=0..1223 |
| safe alpha 경계 (alpha > 0) | x=102..1151, y=106..1147 |
| safe 좌 / 상 / 우 / 하 여백 | 102 / 106 / 102 / 106px 통과 |
| 가장 바깥 행과 열 | alpha 완전 투명 통과 |
| alpha=0 픽셀 RGB | RGB 모두 0 통과 |
| 고립 alpha 픽셀 | safe 0개 통과 |
| 축소 | 원본 bounds 1228×1224에서 1050×1042로 0.855049 균일 비율 축소 통과 |
| 192px 리사이즈에서 측정한 축척 | x=0.854866, y=0.854808 통과 |
| 원본 보존 | SHA-256 일치, 생성 전후 바이트 동일 통과 |

원본에 있던 고립 alpha 픽셀 391개를 복제본에서 제거하고, alpha bounds를 유지한 채 축소했다. Lanczos 재표본화로 생긴 고립 픽셀 112개도 safe 복제본에서 정리했다. RGB 가장자리가 투명부로 번지지 않도록 premultiplied alpha로 재표본화한 다음 완전 투명 픽셀 RGB를 0으로 만들었다.

## 같은 192×192 게임 캔버스 비교

비교 보드의 순서는 v8 idle, 기존 Attack 1 접촉(`attack1_reference_v1_final_candidate`), Num4 원본, Num4 safe다. 네 이미지를 각각 192×192로 Lanczos 축소하고 2배 nearest-neighbor로 같은 크기에 표시했다. 좌표와 경계 상자는 게임 캔버스의 좌상단 기준이며 alpha 0.05를 사용한다. 노란 표식은 최하단 alpha 행의 접촉 anchor다. 주먹 proxy는 화면 오른쪽 상단 영역의 가장 오른쪽 alpha 픽셀로, 주먹끝의 정밀 관절 위치가 아니라 수평 도달 범위를 대략 비교한다.

| 측정값 (192px) | v8 idle | Attack 1 접촉 | Num4 원본 | Num4 safe |
|---|---:|---:|---:|---:|
| 실루엣 bounds x,y,w,h | 42, 12, 117, 171 | 25, 19, 153, 153 | 7, 17, 183, 160 | 18, 30, 157, 138 |
| alpha 중심 x,y | 99.40, 91.31 | 100.23, 90.24 | 98.04, 96.12 | 96.09, 98.32 |
| 오른쪽 주먹 도달 proxy x,y | 141, 70 | 177, 53 | 189, 54 | 174, 63 |
| 최하단 접촉 anchor x,y | 151, 182 | 163, 171 | 176, 176 | 163, 167 |

원본 자세는 idle보다 전방 주먹 proxy가 오른쪽 48px에 있으며, 공격 접촉보다 12px 더 뻗어 있다. 보드에서 얼굴·뾰족귀·갈색 포니테일, 청록색 의상과 금색 장식이 같은 인물 identity를 유지하는지 확인한다. 주먹은 오른쪽으로 직선 연장되고, 왼쪽 다리/부츠가 뒤로 뻗은 추진발이며 오른쪽 다리는 전방에 굽혀 착지하는 실루엣이다. 이는 이미지 판독이며 실제 타격 방향과 애니메이션 연결이 올바르다는 승인으로 간주하지 않는다.

safe는 포즈 픽셀을 재배치하거나 관절을 변경하지 않고 캔버스 안에 약 85.5%로 균일 축소해 중앙 정렬했다. 화면상 보이는 bounds는 183×160에서 157×138로 작아졌다. alpha 중심은 원본보다 (-1.95, +2.20)px 이동했다. 최하단 접촉 anchor는 (176,176)에서 (163,167)로 이동, 즉 왼쪽 13px·위쪽 9px이며, 주먹 proxy는 (189,54)에서 (174,63)으로 이동했다. 크기 안전 여백을 얻는 대신 같은 원점에 배치할 경우 크기와 바닥 anchor가 바뀌므로 사람 검수에서 실제 기준점을 승인해야 한다.

## Num4 직선 돌진과 Num5 회전기 구분

기존 `temp/player_skill_motion_capture/num5_004_active.png` 런타임 캡처는 상체가 옆으로 기울고 다리를 옆으로 휘두르는 회전/킥 실루엣을 보여 준다. 비교 대상인 Num4 원화는 상체를 낮춰 오른쪽 주먹을 거의 수평으로 연장하고 반대편 발을 뒤로 차는 직선 추진 실루엣이다. 따라서 정지 원화만 보면 Num5 회전기보다 직선 돌진 접촉으로 읽힌다. 별도 런타임 Num4 활성 캡처 `num4_001_active.png`는 guard 주먹과 이동 자세를 보여 주므로, 이 후보는 현재 게임 동작에 연결된 원화가 아니라 검토 대상 key pose다.

## 사람 검수 — 본편 등록 전 필수

- [ ] 192px 크기에서 얼굴 생김새, 뾰족귀, 포니테일, 청록색/금색 복장 identity가 v8 idle 및 공격 접촉과 일치한다.
- [ ] 오른쪽 주먹이 목표 방향으로 직선 돌진하는 접촉으로 읽히고, 기존 Attack 1 접촉과 타격감이 구별된다.
- [ ] 왼쪽으로 뻗은 추진발과 앞쪽으로 굽힌 다리가 추진 방향을 뒷받침하며 실루엣이 뭉개지지 않는다.
- [ ] safe의 작아진 실루엣과 (163,167) 최하단 anchor가 게임 배치에 적절하다. 필요하다면 본편 등록 전 별도 승인 작업에서 anchor를 조정한다.
- [ ] Num5 활성 회전/옆차기 캡처와 나란히 재생해, Num4가 회전 공격이 아니라 직선 돌진으로 분명히 읽힌다.
- [ ] 포즈를 본편에 연결할 경우 시작/접촉/회복 동작 전반에서 Num4와 Num5가 서로 혼동되지 않는다.
- [ ] 사람 승인 전에는 본편·manifest·allowlist에 등록하지 않는다.

## 재현

```powershell
godot --headless --path . --script res://tools/prepare_player_skill1_rush_safe.gd
godot --headless --path . --script res://tests/player_skill1_rush_safe_smoke.gd
```

두 명령을 실행했다. safe 준비와 smoke의 기계 검사는 통과했다. Godot가 `user://logs` 쓰기 및 Windows 인증서 저장소 읽기 오류를 출력했으나 종료 코드는 0이었다. 위 사람 검수 항목은 승인 대기다.
