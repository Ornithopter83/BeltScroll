# M6P F10 공격·피격 shape 픽셀 게이트

- 결과: PASS
- 실제 Window: `Windows`, 크기 `(2560, 1440)`, 뷰포트 `(2560, 1440)`
- 검증: 개별 Player 기본 1·2·3타, Num4·Num5, Raider/Boss AttackArea·ReceiveArea 외곽 기준점. Shape2D 로컬 외곽점을 CollisionShape2D 전역 canvas transform 및 Window final transform으로 투영하고 해당 색상 픽셀을 원형 반경 4 px 안에서 찾음.
- 상태 범위: monitoring 활성·비활성, 좌우 반전, 카메라 줌 1.35·스크롤, Raider·Boss KO, F10 OFF/ON 및 scene restart 뒤 OFF.
- 구동 방식: Player 단계/스킬과 Boss 공격 단계는 스크립트 상태 설정으로 준비했다. 이 픽셀 게이트는 실제 전투 입력·피해 라우팅을 검증하지 않음.
- F10 입력 한계: OFF/ON은 `44`회 overlay `_input` callback 직접 호출로 확인. 물리 키 입력이나 `Input.parse_input_event`를 통한 앱 입력 라우팅은 검증하지 않음.
- 비교: 22 OFF/ON shape 상태, 88 외곽 기준점.

| 상태 | CollisionShape2D | 색 | 기준점 일치 | 결과 |
|---|---|---|---:|---|
| Player 기본 1타 활성 | /root/Main/YSortActors/Player/Hitboxes/Hitbox1/CollisionShape2D | green | 4/4 | PASS |
| Player 기본 1타 비활성 | /root/Main/YSortActors/Player/Hitboxes/Hitbox1/CollisionShape2D | red | 4/4 | PASS |
| Player 기본 2타 활성 | /root/Main/YSortActors/Player/Hitboxes/Hitbox2/CollisionShape2D | green | 4/4 | PASS |
| Player 기본 2타 비활성 | /root/Main/YSortActors/Player/Hitboxes/Hitbox2/CollisionShape2D | red | 4/4 | PASS |
| Player 기본 3타 활성 | /root/Main/YSortActors/Player/Hitboxes/Hitbox3/CollisionShape2D | green | 4/4 | PASS |
| Player 기본 3타 비활성 | /root/Main/YSortActors/Player/Hitboxes/Hitbox3/CollisionShape2D | red | 4/4 | PASS |
| Player Num4 활성 | /root/Main/YSortActors/Player/Hitboxes/Skill1Hitbox/CollisionShape2D | green | 4/4 | PASS |
| Player Num4 비활성 | /root/Main/YSortActors/Player/Hitboxes/Skill1Hitbox/CollisionShape2D | red | 4/4 | PASS |
| Player Num5 활성 | /root/Main/YSortActors/Player/Hitboxes/Skill2Hitbox/CollisionShape2D | green | 4/4 | PASS |
| Player Num5 비활성 | /root/Main/YSortActors/Player/Hitboxes/Skill2Hitbox/CollisionShape2D | red | 4/4 | PASS |
| Raider AttackArea 활성 | /root/Main/YSortActors/ForestRaider1/AttackArea/CollisionShape2D | green | 4/4 | PASS |
| Raider AttackArea 비활성 | /root/Main/YSortActors/ForestRaider1/AttackArea/CollisionShape2D | red | 4/4 | PASS |
| Raider ReceiveArea | /root/Main/YSortActors/ForestRaider1/ReceiveArea/CollisionShape2D | cyan | 4/4 | PASS |
| Boss slash AttackArea 활성 | /root/Main/YSortActors/RuinsWardenBoss/AttackArea/CollisionShape2D | green | 4/4 | PASS |
| Boss slash AttackArea 비활성 | /root/Main/YSortActors/RuinsWardenBoss/AttackArea/CollisionShape2D | red | 4/4 | PASS |
| Boss slash ReceiveArea | /root/Main/YSortActors/RuinsWardenBoss/ReceiveArea/CollisionShape2D | cyan | 4/4 | PASS |
| Boss slam AttackArea 활성 | /root/Main/YSortActors/RuinsWardenBoss/AttackArea/CollisionShape2D | green | 4/4 | PASS |
| Boss slam AttackArea 비활성 | /root/Main/YSortActors/RuinsWardenBoss/AttackArea/CollisionShape2D | red | 4/4 | PASS |
| Boss slam ReceiveArea | /root/Main/YSortActors/RuinsWardenBoss/ReceiveArea/CollisionShape2D | cyan | 4/4 | PASS |
| Player 2타 좌우 반전 + 카메라 줌/스크롤 | /root/Main/YSortActors/Player/Hitboxes/Hitbox2/CollisionShape2D | green | 4/4 | PASS |
| Raider KO ReceiveArea | /root/Main/YSortActors/ForestRaider1/ReceiveArea/CollisionShape2D | cyan | 4/4 | PASS |
| Boss KO ReceiveArea | /root/Main/YSortActors/RuinsWardenBoss/ReceiveArea/CollisionShape2D | cyan | 4/4 | PASS |

## 실패

없음

## 오버레이 변경 판단

외곽점 투영 실패가 재현된 경우에만 `scripts/debug/combat_collision_overlay.gd`의 투영 경로를 수정한다. 이 게이트는 렌더링/표시만 확인하며 게임 충돌 판정과 피해 수치를 변경하지 않는다.
