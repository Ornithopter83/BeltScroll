# Num4 돌진 접촉 동작 비교 검수

## 검수 산출물

- [Window 캡처 스트립](../../assets/art/review/player_skill1_contact_motion_strip.png)
- 캡처 실행: `godot --path . --script tools/capture_player_skill1_contact_motion.gd`
- 독립 점검: `godot --headless --path . --script tests/player_skill1_contact_motion_smoke.gd`
- 각 타일은 실제 1920×1080 Window의 post-draw 이미지다. 2열×5행 보드는 3840×5400이다.

## 캡처 구성과 동기화

오른쪽을 보는 Num4는 startup 중간, active 초반, active 후반, recovery 중간 순서로 담았다. 같은 네 시점을 왼쪽 보기로 반복하고 각 방향에서 Num5 active 회전 비교를 한 장씩 덧붙였다. 각 타일에는 Player의 `skill_phase_remaining`, 진행 시간, 실제 x 이동량, skill hitbox 상태가 함께 적혀 있다. 캡처 프레임은 physics tick 뒤에 기다린 Window post-draw에서 얻었다.

Num4의 phase 기준은 startup 0.16초, active 0.12초, recovery 0.42초다. 접촉용 receiver는 Player의 공격 판정에 실제로 맞도록 배치했고, 검사 신호가 도착하면 `impact pop YES`로 표기한다. 우향은 전진 거리가 양수이고 좌향은 음수다. Num5 회전 reference도 같은 192px base art 배율로 표시하며, 해당 스킬의 live phase clock과 회전 pose를 함께 캡처한다. 절차 애니메이터의 phase별 늘림/축소 값은 이 기준 배율에 더해진다.

가운데 칸은 기존 `elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png`를 alpha 높이 192px로 축소한 격리 미리보기다. 본편 Player 원화/애니메이터나 manifest 및 allowlist에는 후보를 등록하지 않았다. 실제 본편 Num4 동작은 기존 Player 인스턴스와 절차 애니메이터에서 가져왔다.

## 검수 게이트

- 얼굴, 뾰족귀, 청록색 의상과 금색 장식이 기존 캐릭터 identity를 유지하는지 비교한다.
- 후보 주먹의 전방 연장과 뒷발 추진 자세를 보고, 본편 절차 동작의 전진 경로가 직선 돌진 판정과 맞는지 확인한다.
- 두 방향에서 alpha 높이 192px, 발 기준선 접지, 전진 거리와 hitbox ON/OFF를 확인한다.
- startup에서 접촉 직전, active와 `impact pop`, recovery에서 접촉 직후가 순서대로 보이는지 확인한다.
- Num5의 몸통 회전과 주변 방향 판정이 Num4 직선 돌진과 구별되는지 같은 배율로 확인한다.

## 검수 메모

캡처 실행 시 10장의 Window 프레임이 생성되었고 파일은 3840×5400이다. safe 후보에는 얼굴/뾰족귀/청록·금색 복장 identity, 뻗은 팔, 후방 추진 다리가 보이며, 실제 접지점은 양향 모두 표시 기준선에 맞췄다. 본편 Player는 같은 캐릭터의 기본 원화와 실제 전진/hitbox를 사용하지만 Num4 구간의 팔은 기본 가드 자세에 머문다. 따라서 본편의 직선 주먹 연장과 추진발 표현은 확인되지 않았고, 이 비교는 그 동작 표현이 현재 임시 절차 모션의 남은 시각 검수 사항임을 드러낸다. 실제 receiver 타격과 impact pop은 Num4/Num5 active 및 recovery 샘플에서 확인 가능하다. safe 후보는 단일 접촉 원화이므로 후보 자체의 연속 주먹 궤적은 애니메이션하지 않는다.
