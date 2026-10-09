# M6E 공격 1 단일 접촉 후보 검토

## 원화 확보 상태

신규 단일 접촉 입력 `elven_fighter_dark_fantasy_attack1_contact_v2_candidate_1254x1254.png`를 확인했다. RESOURCE 이름의 원화는 없었으며, 이 단일 PNG를 원본 그대로 읽어 정규화 후보 `elven_fighter_dark_fantasy_attack1_contact_safe_candidate_1254x1254.png`를 생성했다. 기존 2×2 시트 crop은 이 후보 생성에 사용하지 않았다.

비교 보드의 왼쪽은 기존 다크 판타지 redesign 원화를 idle 기준 이미지로 사용한다. 가운데는 새 단일 접촉 입력을 정규화한 후보를 표시한다. 오른쪽에는 기존 M6D attack1 2×2 시트를 함께 두고 균등 627×627 crop 기준으로 경계 alpha를 측정했다.

신규 입력은 RGBA8로 변환해 1254×1254 투명 캔버스에 배치했다. 출력의 α≥0.05 bounds는 `(105, 90, 1043, 1074)`이고, alpha 하단 경계/임시 발 anchor는 `y=1164`다. 네 방향 모두 최소 90px 투명 여백을 둔다. 이 anchor는 두 발 중 어느 발이 지지발인지 판정하지 않는다.

## 기존 M6D 셀 진단

alpha 경계와 bounds는 각 627×627 셀 crop 내부에서 α≥0.05로 측정했다. edge alpha 순서는 위/아래/왼쪽/오른쪽이며 crop 테두리에 닿은 픽셀 수다.

| 셀 | alpha bounds (x, y, w, h) | edge alpha 위/아래/왼쪽/오른쪽 | 진단 |
|---|---:|---:|---|
| 좌상 | (89, 9, 489, 618) | 0 / 49 / 0 / 0 | 하단 경계에 alpha 접촉 |
| 우상 | (53, 33, 548, 594) | 0 / 49 / 0 / 0 | 하단 경계에 alpha 접촉 |
| 좌하 | (60, 0, 567, 598) | 35 / 0 / 0 / 50 | 상단·오른쪽 경계에 alpha 접촉 |
| 우하 | (0, 0, 602, 600) | 47 / 0 / 49 / 0 | 상단·왼쪽 경계에 alpha 접촉 |

네 crop 모두 최소 한 변에 보이는 alpha가 닿는다. 균등 분할 경계에서 그림이 잘렸거나 이웃 셀로 이어질 위험이 확인된다. 특히 좌하·우하 crop은 상단과 내부 세로 경계에도 alpha가 있어, 셀 독립성이 검증되지 않았다. 경계가 잘린 셀은 승인 가능으로 판정하지 않는다. 발 anchor나 접지발도 이 crop들로 확정하지 않는다.

## 정규화 및 승인 경계

도구는 지정 폴더에서 새 단일 접촉 원화를 찾으면 투명 alpha bounds를 crop하고 RGBA8로 변환한다. 1254×1254 투명 캔버스 안에서 각 변에 최소 90px 여백을 확보하며 하단 visible-alpha 경계를 y=1164에 정렬한다. 이 하단 경계는 자동 접지점이 아니라 일관된 임시 발 anchor다. 지지발은 사람이 별도로 확인해야 한다.

출력 PNG 이름은 `*_safe_candidate_*`여도 미승인 후보로만 취급한다. 누락 팔다리를 보완·합성하지 않으며, manifest, reviewed-frame allowlist, PlayerArt 또는 런타임 등록을 변경하지 않는다.

- 비교 보드: [m6e_attack1_candidate_comparison.png](../../assets/art/review/m6e_attack1_candidate_comparison.png)
- 후보 준비 및 셀 진단: `godot.exe --path . --script tools/prepare_m6e_attack1_candidate.gd`
- smoke 검사: `godot.exe --path . --script tests/m6e_attack1_candidate_smoke.gd`
- 후보 원본: `assets/art/player/elven_fighter_dark_fantasy_attack1_contact_v2_candidate_1254x1254.png`
- 판정: 신규 단일 contact **확보**, RGBA/투명 여백/임시 anchor 정규화 **완료**, 기존 2×2 경계 alpha **검출**, 셀 잘림/혼입 위험 **미해결**, 신규 후보 승인 **보류**, manifest/allowlist/본편 아트 **변경 없음**.
