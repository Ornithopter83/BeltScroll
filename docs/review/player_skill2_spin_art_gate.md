# Num5 회전 백피스트 원화 검수 게이트

## 판정 요약

v2 원화를 확보했다. #90 검수 도구가 찾던 `elven_fighter_skill2_spin_contact_v2_candidate_1254x1254.png`라는 파일은 없으며, 실제 원화는 [elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png](../../assets/art/player/elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png)다. 검수 도구는 정확한 실제 파일명을 읽고, 원본을 보존한 채 별도 [safe 후보](../../assets/art/player/elven_fighter_skill2_spin_backfist_v2_safe_candidate_1254x1254.png)를 생성한다. 기존 **V2 FILE MISSING** 판정은 해소됐다.

v2는 v8과 같은 엘프 전사 identity로 보인다. 몸통은 옆과 뒤가 보이도록 회전했고, 한쪽 팔은 뒤로 접혀 있다. 그러나 다른 팔과 주먹은 어깨에서 앞으로 곧게 뻗어 있어 백피스트보다 직선 타격으로 읽힌다. 다리는 넓게 벌어져 있고 한 발이 축처럼 지면에 놓여 보이지만, 회전 동작과 회전축 발을 분명히 입증하기에는 정지 그림의 정보가 부족하다. 팔 교차도 확인되지 않는다. 따라서 **Num5 v2 safe는 보류하며, 회전 접촉 원화로 미수용**이다. 직선 타격처럼 보이는 판정이 남아 있는 동안 이 원화를 회전 백피스트로 승인하지 않는다.

사람의 시각 승인 없이 원화나 safe 후보를 본편, manifest 또는 allowlist에 등록하지 않는다. safe 후보는 픽셀 안전성 파생본이며 포즈 승인이나 본편 등록을 뜻하지 않는다.

## 검수 산출물 및 재현

- [동일 캔버스 비교 보드](../../assets/art/review/player_skill2_spin_art_comparison.png)는 v8 idle, Num4 safe 돌진, Num5 v1, Num5 v2 safe를 각각 원향과 좌우 미러로 보여준다.
- [검수 생성기](../../tools/review_player_skill2_spin_art.gd)는 원본 경로를 읽고 v2 safe 후보와 비교 보드를 생성한다.
- [기계 검사 smoke](../../tests/player_skill2_spin_art_smoke.gd)는 입력 파일·캔버스·포맷과 safe 후보 여백, 투명 테두리, 고립 픽셀 및 보드 크기를 확인한다.

원본 1254×1254 캔버스를 자르거나 alpha 경계에 맞춰 각 이미지를 재배치하지 않았다. 모든 보드 패널은 같은 192×192 캔버스로 Lanczos 축소하고, 그 결과를 동일한 픽셀 크기로 표시했다. 각 패널은 원향과 수평 반전본을 나란히 둔다.

v2 safe 후보 생성은 원본 바이트를 보존하면서 별도 메모리 이미지에서만 수행한다. 우선 원본의 고립 alpha 픽셀을 검사·제거한 뒤 alpha 경계를 추출하고, premultiplied-alpha Lanczos로 비율을 유지해 1254×1254 캔버스에 맞췄다. 안전 여백 90px과 resample guard 12px을 고려해 콘텐츠를 최대 1030×1030px 영역에 배치하고 투명 RGB를 0으로 정리했다. 생성 시 원본 SHA-256은 `f1e3bdd58d9ab4791295799caec8fcfe12ef2f4afc97617ffdf421922641dc4b`였으며 생성 전후 바이트 일치를 확인했다.

## 픽셀 측정 기록

alpha 경계는 alpha가 0보다 큰 픽셀을 포함하는 `(x,y,w,h)`이며 여백은 좌/상/우/하 순서다. 고립 alpha 픽셀은 주변 8방향에 양수 alpha 이웃이 없는 픽셀 수다.

| 원화 | 캔버스 / 포맷 | alpha 경계 (x,y,w,h) | 여백 L/T/R/B (px) | 고립 alpha 픽셀 | 192px alpha 크기 (5% 기준) |
|---|---|---|---|---:|---|
| v8 idle | 1254×1254 / RGBA8 | 21,13,1195,1241 | 21 / 13 / 38 / 0 | 543 | 117×171 |
| Num4 safe rush | 1254×1254 / RGBA8 | 102,106,1050,1042 | 102 / 106 / 102 / 106 | 0 | 157×138 |
| Num5 v1 contact | 1254×1254 / RGBA8 | 0,27,1239,1227 | 0 / 27 / 15 / 0 | 739 | 181×169 |
| Num5 v2 source | 1254×1254 / RGBA8 | 0,27,1238,1227 | 0 / 27 / 16 / 0 | 288 제거 대상 | 미비교 |
| Num5 v2 safe candidate | 1254×1254 / RGBA8 | 110,102,1033,1050 | 110 / 102 / 111 / 102 | 0 | 129×146 |

v2 safe의 균일 축척은 0.874271이며 artwork 영역은 1033×1050px다. 네 변의 alpha 여백은 모두 90px 이상이고 가장자리는 투명하다. 원본 v2의 288개 고립 픽셀은 파생본을 만들 때만 제거했으며 원본에는 변경을 가하지 않았다. v8 및 Num5 v1은 기존 원본 측정상 가장자리 여백이 0px이고 고립 픽셀도 있어 외곽 픽셀 검토 대상이다. 이 수치는 기계 측정이며 시각적 품질 승인을 대신하지 않는다.

## 시각 검수 항목

- [x] v8, Num4 safe, Num5 v1, Num5 v2 safe를 같은 크기의 전체 캔버스 배율로 비교하고 좌우 미러를 함께 표시했다.
- [x] v2에서 얼굴, 뾰족한 귀, 갈색 포니테일, 청록색·금색 의상을 확인했다. v8 identity와 다르다는 징후는 보이지 않는다.
- [ ] 몸통의 후방 회전이 접촉 동작에서 읽힐 정도로 분명한지 사람의 검수가 필요하다.
- [ ] 뻗은 주먹이 수평 백피스트로 읽히는지 검수해야 한다. 현재는 직선 타격으로 읽혀 미수용이다.
- [ ] 회전축 발과 팔 교차가 게임 크기에서 분명한지 검수해야 한다. 현재 팔 교차는 확인되지 않고 지지발도 확정하기 어렵다.
- [ ] 사람 검수자가 회전 동작·백피스트·identity를 승인하기 전까지 본편 등록을 보류한다.

## 재현 명령

```powershell
godot --headless --path . --script res://tools/review_player_skill2_spin_art.gd
godot --headless --path . --script res://tests/player_skill2_spin_art_smoke.gd
```

검수 생성기는 safe 후보와 보드 PNG를 정상 생성하고 종료했다. 실행 로그에는 제한된 `user://logs` 쓰기와 Windows 인증서 저장소 읽기 오류가 출력됐지만 산출물은 작성됐다. 비교 보드와 픽셀 측정은 기계 검수 결과다. 사람의 포즈 승인 및 본편 등록은 대기 중이다.
