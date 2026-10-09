# 2타 접촉 v6 safe 후보 검수 게이트

## 상태

별도 safe 후보를 생성했으며 기계 규격 검사를 통과했습니다. **사람의 시각 승인은 대기 중이며 본편 씬·애니메이션·런타임 리소스에는 연결하지 않았습니다.** 원본 `elven_fighter_attack2_contact_v6_candidate_1254x1254.png`는 바이트 변경 없이 보존했습니다.

산출물:

- safe 후보: `assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png`
- 3배 비교판: `assets/art/review/player_attack2_contact_v6_safe_comparison.png`
- 생성 도구: `tools/prepare_player_attack2_contact_v6_safe.gd`
- 기계 검사: `tests/player_attack2_contact_v6_safe_smoke.gd`

## 캔버스 및 alpha 결과

입력 v6의 비영점 alpha 경계 여백은 좌/상/우/하 **27/19/20/32px**였습니다. 캐릭터 전체를 한 비율로 축소하고 1254×1254 투명 캔버스 중앙에 배치했습니다. 보간 중 경계가 90px 안으로 들어오는 일을 막기 위해 목표 내부 영역에 12px 추가 여유를 뒀습니다.

| 항목 | v6 원본 | safe 후보 |
|---|---:|---:|
| 캔버스 / 형식 | 1254×1254 RGBA8 | 1254×1254 RGBA8 |
| 비영점 alpha 여백 L/T/R/B | 27/19/20/32px | **119/102/119/102px** |
| 균일 축소 비율 | 1.000000 | **0.872818** |
| 렌더링된 콘텐츠 크기 | — | 1016×1050px |
| 최외곽 1px | 투명 | 완전 투명 |
| 투명 픽셀 RGB | 입력 그대로 | 0/0/0으로 정리 |
| 고립된 단일 alpha 픽셀 | 검사 입력 | **0개** |

리사이즈는 premultiplied alpha 공간에서 수행한 다음 straight alpha PNG로 되돌렸습니다. 원본의 고립 픽셀 1개와 보간 후의 고립 픽셀 400개를 제거했습니다. 8방향으로 이웃 alpha가 있는 윤곽 픽셀은 보존하므로 머리카락의 희미한 윤곽 전체를 5% 실루엣 기준으로 잘라내지 않습니다.

## 3배 비교와 발 anchor

비교판은 승인된 v8 정지 원화(`elven_fighter_reference_v8_clean_candidate_1254x1254.png`), 2타 safe 중간(`elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png`), v6 원본, safe 후보를 같은 **576×576(192px 게임 캔버스의 3배)** 캔버스 크기로 나란히 표시합니다. 노란 십자 표식은 alpha 5% 기준 최하단 행의 접점 구간 중앙입니다.

| 프레임 | 최하단 접점 anchor (원화 px) |
|---|---:|
| v8 승인 정지 원화 | (951, 1112) |
| 2타 safe 중간 | (1063, 1161) |
| v6 원본 | (1179, 1211) |
| v6 safe 후보 | (1099, 1143) |

v6 원본에서 safe 후보로 바뀐 최하단 발 anchor는 **(-80, -68) 원화 px**, 즉 192px 게임 캔버스 환산 **(-12.25, -10.41) 게임 px** 이동했습니다. 비교판 3배 표시에서는 약 **(-36.7, -31.2) 표시 px**입니다. 후보의 alpha 5% 실루엣은 1088×1162px에서 950×1015px로 줄어듭니다. 캔버스 원점을 고정해 적용하면 발이 위·왼쪽으로 이동하고 캐릭터 표시 크기도 작아지므로, 승인 시 애니메이션 기준점과 표시 크기를 함께 검토해야 합니다.

anchor는 alpha 실루엣에서 자동으로 구한 최하단 접점이며, 관절·무게중심 분석을 대신하지 않습니다. 두 부츠 중 실제 지지발인지, 이전 포즈와 접지가 이어지는지는 시각 검수자가 v8 및 safe 중간과 함께 확인해야 합니다. 비교판은 이 이동과 상대 크기를 빠르게 확인하기 위한 검수 자료이지 동작 승인 표시가 아닙니다.

## 재생성 및 검사

```powershell
godot --headless --path . --script res://tools/prepare_player_attack2_contact_v6_safe.gd
godot --headless --path . --script res://tests/player_attack2_contact_v6_safe_smoke.gd
```

스모크 결과: 1254 정사각 RGBA8, 네 방향 90px 이상 여백, 투명 외곽, 투명 픽셀 RGB 0, 고립 alpha 픽셀 0개, 원본 바이트 보존, 비교판 생성 모두 통과했습니다. 이는 기계적 안전 규격만 확인하며 얼굴·귀·포니테일·손·부츠의 시각적 보존이나 동작 품질을 승인하지 않습니다. 사람의 시각 승인 전까지 safe 후보는 별도 후보 상태로 유지합니다.
