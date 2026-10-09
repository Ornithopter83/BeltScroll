# Player turn mid art gate

## 상태: 원화 확보 / 키포즈 보류

전용 turn 원화 경로: `res://assets/art/player/elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png`  
safe 후보 경로: `res://assets/art/player/elven_fighter_turn_rear_mid_v1_safe_candidate_1254x1254.png`

원화 원본을 변경하지 않고 별도 safe 후보를 생성했다. 후보는 알파 여백을 사방 90px 이상으로 맞추고 고립 알파 픽셀을 제거했다. 후보는 1254×1254 RGBA8이다.

- 원본 SHA256: `43ae0c54ee26ece7121ec60a265d507877b2cfea8408026f8bccd0ff3779da72`
- 원본 바이트: `1032791`

비교판: `res://assets/art/review/player_turn_mid_comparison.png` (420×480) — 모든 카드는 전체 캔버스를 보존해 192×192로 배치했다. 읽는 순서는 왼쪽 위 v8 idle, 오른쪽 위 원화, 왼쪽 아래 safe 후보, 오른쪽 아래 기존 procedural 캡처의 압축 turn 프레임이다. 헤더 색은 각각 파랑·갈색·초록·보라다.

## 포즈 검토 기록

후방 3/4 시점과 얼굴을 돌려보는 표정, 귀, 포니테일이 읽혀 캐릭터 identity는 유지된다. 다만 앞뒤 다리의 크게 벌어진 보폭, 들린 부츠, 팔의 반동 때문에 정지 turn보다 달리기/보폭 포즈로 읽힌다. 요청한 키포즈 기준으로 수용하지 않고 사람 검토 보류다.

- safe 후보 알파 used rect: 위치 `(149, 90)`, 크기 `(956, 1074)`; 사방 여백 `[149, 90, 149, 90]` px. 고립 알파 픽셀 제거: `224` (원본 및 후보화 단계 합계).
- 192px full-canvas 비교에서 turn 인물 높이: 약 `164px`; procedural 캡처는 원래 capture cell을 동일 192px 전체 cell로 축소해 게임 내 인물 크기와 팝 차이를 함께 보인다.

- 후방 3/4: 원화에는 명확한 뒤돌아본 후방 3/4가 있으나 stride 포즈로 읽힌다. 기존 procedural 캡처는 옆면 방향을 뒤집는 변환 단계여서 후방 키포즈 증거가 아니다.
- 얼굴·귀·포니테일 identity: 얼굴을 돌아보는 표정, 뾰족한 귀, 높은 포니테일이 v8 idle과 일치한다. 좌우 반전만으로는 이 identity 검증을 대체하지 않는다.
- 회전축 발: 원화 한 장에는 지지발 후보(화면 오른쪽 부츠)와 든 발이 보인다. 연속 turn에서 회전축 발이 고정되는지는 평가 불가다. 기존 procedural 캡처 도구는 alpha-foot anchor 안정성을 별도로 기록한다.
- 좌우 미러·골반·발 anchor: 반대 방향 authored frame이 없어 좌우 mirror, 골반 중심, 지지발 이동을 비교할 수 없다. 승인 전에 해당 대응 프레임이 필요하다.
- 크기 팝: v8 idle, 원화, safe는 전체 1254px 캔버스를 192px로 같은 비율 축소했다. procedural 캡처는 전체 capture cell을 192px로 축소해 장면에서 보이는 캐릭터 크기를 비교한다.
- 키포즈 결론: 단순 좌우 flip이나 달리기 자세는 turn 키포즈로 수용하지 않는다. 이 원화는 stride로 보여 현재 보류한다. 사람 승인 전 본편·manifest·allowlist에 등록하지 않는다.

