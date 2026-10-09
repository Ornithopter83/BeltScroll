# 2타 접촉 v6 후보 검수 게이트

## 현재 상태

**신규 v6 접촉 후보를 찾았지만 규격 게이트 실패이며 사람의 시각 승인 전입니다.** 원본 `assets/art/player/elven_fighter_attack2_contact_v6_candidate_1254x1254.png`는 1254×1254 RGBA8이고 최외곽 테두리는 투명합니다. 그러나 비영점 alpha 기준 여백은 좌/상/우/하 **27/19/20/32px**로 모두 90px에 미달합니다. 후보를 축소·수정하지 않았으며 본편에 연결하지 않았습니다.

검수판 `assets/art/review/player_attack2_contact_v6_comparison.png`에는 아래 순서로 다섯 패널이 있습니다.

1. 승인된 v8 정지 원화: `elven_fighter_reference_v8_clean_candidate_1254x1254.png`
2. 기존 1타 접촉 후보: `elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png`
3. 2타 safe 중간 후보: `elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png`
4. 이전 2타 접촉 후보: `elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png`
5. 신규 v6 접촉 후보: `elven_fighter_attack2_contact_v6_candidate_1254x1254.png` (규격 게이트 실패, 시각 승인 대기)

각 제공 원화는 alpha 5% 이상 실루엣을 원본 비율대로 높이 576px(192px 게임 스프라이트의 3배)로 표시하고, 최하단 alpha 행을 공통 발 기준선에 맞춥니다. 체크무늬 배경으로 외곽을 볼 수 있습니다. 비교판은 별도 검수 산출물이며 게임 연결이나 승인 표시가 아닙니다.

## 비교 관찰 및 승인 경계

비교판에서 v6는 높은 갈색 포니테일과 금색 묶음 장식, 뾰족한 귀, 청록·금색 의상, 갈색 장화 등 승인된 v8의 주요 identity 특징을 유지합니다. 얼굴은 화면 오른쪽을 향하고, 오른팔은 오른쪽으로 뻗으며 왼팔은 가드 자세로 접혀 있어 safe 중간의 팔 동선과 이어질 수 있습니다. 이전 2타 접촉에 비해 v6 몸통은 더 측면에 가깝고 얼굴이 또렷하게 보이며, 큰 포니테일과 허리천은 회전 방향을 강조합니다. 다만 정지 비교만으로 팔의 연속 동작이나 실제 접촉 타이밍은 판단할 수 없습니다.

v6는 양 무릎을 굽힌 넓은 런지 형태이며 양 장화가 보입니다. 공통 발 기준선에는 정렬되지만, 이 정렬은 그림별 바닥 높이를 비교하기 위한 것입니다. 어느 발이 실제 지지발인지, 무게중심이 안정적인지, 애니메이션에서 발 anchor가 유지되는지는 담당자가 프레임 연결과 함께 확인해야 합니다. v6는 3배 표시에서 전신, 얼굴·귀, 양팔, 양발의 실루엣이 읽힙니다.

v5에서 지적된 밝은 가장자리 오염 및 고립 alpha 픽셀은 v6의 3배 비교판에서 눈에 띄게 반복되지 않습니다. 원본 확대에서는 특히 포니테일과 머리카락 외곽에 가는 적갈색 테두리가 보여 가장자리 색 오염인지 원화의 윤곽 처리인지 사람의 확대 확인이 필요합니다. 최외곽 1px 테두리가 투명하다는 사실만으로 가장자리 결함이 해결됐다고 볼 수는 없습니다. 무엇보다 90px 안전 여백이 크게 부족하므로 규격 수정 후 재검수해야 합니다.

v8 정지 원화의 본편 적용 승인은 [player_keypose_gate.md](player_keypose_gate.md)에 기록되어 있습니다. 2타 safe 중간 후보는 별도 승인 대기 원화이고 이 검수 작업에서 시각 승인하지 않습니다. v6 접촉도 사람의 시각 승인 전까지 본편 씬·애니메이션·런타임 리소스에 연결하지 않습니다. 검수판 생성 도구는 입력 PNG와 게임 리소스를 수정하지 않습니다.

다음 항목은 시각 승인 전 남아 있습니다.

- 원본 PNG가 정확히 1254×1254 RGBA8인지, 모든 비영점 alpha 픽셀 기준 사방 여백이 각각 90px 이상인지, 최외곽 1px 테두리가 완전 투명한지
- 3배 표시에서 얼굴·귀·포니테일·의상 identity가 승인된 v8과 이어지는지
- 1타 및 safe 중간에서 접촉까지 주먹·팔꿈치·어깨의 이동 경로와 반대 팔 가드가 자연스러운지
- 회전 중 의도한 지지발과 발 anchor가 이어지는지, 공통 발 기준선 정렬이 적절한지
- v5에서 관찰된 밝은 가장자리 오염, alpha fringe, 고립 픽셀 같은 결함이 되풀이되는지

현재 규격 게이트에서 캔버스 크기·RGBA8은 통과하고, 사방 90px 여백은 실패하며, 최외곽 투명 테두리는 통과했습니다. 얼굴·의상·동작·균형·가장자리 품질은 스모크가 판정하지 않으며 사람의 확대 검수가 필요합니다.

## 원화 후보 검색 경로

빌더는 아래 후보 이름을 순서대로 찾습니다.

- `assets/art/player/elven_fighter_attack2_v6_contact_candidate_1254x1254.png`
- `assets/art/player/elven_fighter_attack2_reference_v6_contact_candidate_1254x1254.png`
- `assets/art/player/elven_fighter_attack2_contact_v6_candidate_1254x1254.png`
- `assets/art/player/elven_fighter_attack2_contact_v6_identity_candidate_1254x1254.png`

후보가 있으면 기계 게이트는 원본 형식 RGBA8, 1254×1254 크기, 비영점 alpha 경계 기준 각 90px 이상 여백, 최외곽 투명 테두리를 확인합니다. 조건에 실패해도 사람 검수용 패널에는 후보를 표시하되 승인으로 간주하지 않습니다.

## 재생성 및 스모크

```powershell
godot --headless --path . --script res://tools/build_player_attack2_contact_v6_review.gd
godot --headless --path . --script res://tests/player_attack2_contact_v6_smoke.gd
```

스모크는 독립 검수판 PNG, 비교 원화 입력, 후보의 기계적 규격을 확인하고, 규격 게이트 실패 후보도 별도 판에 남기는지 확인합니다. 사람 검수자가 얼굴·의상·동작·균형·가장자리 결함을 확대 확인하고 승인 여부를 기록하기 전에는 v6와 safe 중간 후보를 본편에 연결하지 않습니다.
