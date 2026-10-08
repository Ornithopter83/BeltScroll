# Project design
BeltScroll 완전 신규 제작 계획.

1. 원격 저장소 확인
강제 원격: https://github.com/Ornithopter83/BeltScroll.git
작업 기준: origin/main
확인 SHA: 96aaa6d02ac1ab44f6290600d4687f9d9434c61b
커밋: Initial commit
원격 main은 부모 커밋과 추적 파일이 없는 빈 초기 저장소다. docs/projecthub/initial-plan.md도 존재하지 않는다. 이전 9acf8468 계열 구현과 자산은 현재 main에 없으므로 재사용 가능한 실제 파일로 가정하지 않는다.

실제 프로젝트 루트는 C:\AI-AGENT\Worker\BeltScroll 하나로 고정한다. 초기화를 다시 수행하지 않는다. 기존 인수인계는 설계 요구의 참고 자료로만 사용한다. 코드, 씬, 테스트와 자산 통합은 새 저장소에서 처음부터 구성한다. 최초 전체 설계는 docs/projecthub/initial-plan.md에 한 번 보존한다.

2. 제품 목표
Godot 4.x 기반 1920x1080 2D 벨트스크롤 근접 액션 게임. 개발 및 검증 기준은 Godot 4.7.2 호환성이다.

플레이어는 무기를 사용하지 않는 성인 여성 엘븐 격투가다. 긴 뾰족귀, 선명한 여성 얼굴, 운동선수형 체형, 긴 묶은 머리, 짙은 녹청색 경량 전투복, 갈색 장갑과 부츠, 작은 금색 장식을 유지한다.

전투 화면에서 약 170~210px 높이로 표시하며 얼굴, 귀, 양팔, 양다리, 의상과 공격 실루엣의 가독성을 확보한다.

최종 목표는 움직임과 피격 판정이 정확하고 타격감이 강하며, 고품질 숲 유적 배경과 일관된 캐릭터 애니메이션을 사용하는 실제 플레이 가능한 게임이다.

3. 기술 아키텍처
CharacterBody2D를 Player와 ForestRaider의 물리 기반으로 사용한다. 물리 위치 Vector2(x,y)는 지면 평면에 해당하며 y가 벨트스크롤 깊이다. 점프는 바닥 물리 좌표와 별도의 jump_height 및 jump_velocity로 처리하여 표시 위치만 변경한다.

월드의 경계, 충돌, depth 정렬과 카메라 동작을 서로 일관되게 설계한다. YSortActors의 y-sort를 유지하고 그림자와 실제 캐릭터 발 위치를 정렬 기준으로 사용한다.

프로젝트는 scenes, scripts, assets/art, tests, tools, docs/projecthub로 분리한다. 프로젝트 루트에 run_game.cmd를 마련하여 실행과 검증의 단일 진입점으로 사용한다. 에셋이 아직 없더라도 프로젝트가 실행되도록 임시 표시를 허용하지만 이를 최종 아트로 승인하지 않는다.

4. 이동 설계
Player의 x/y 지면 이동, 방향 전환, 대각선 이동 정규화, arena bounds, crouch, visual jump를 구현한다.

점프에는 coyote time, jump buffer, variable jump height, 정상적인 상승·하강·착지 상태를 포함한다. hit-stun 중에도 visual jump 갱신이 중단되지 않아야 한다.

좌우 바라보기와 발 기준 anchor는 일관성을 유지한다. 애니메이션 교체로 바닥 위치가 흔들려서는 안 된다.

5. 전투 설계
Player는 3단 연속 근접 콤보를 가진다. 각 공격은 준비, contact, recovery 구간을 갖고 attack_progress와 표시 프레임을 동기화한다.

1타는 빠르고 큰 횡공격과 짧은 lunge, 2타는 골반·몸통·양팔·다리를 활용하는 회전 sweep, 3타는 강한 상승형 finisher로 구성한다.

1타에서 3타로 진행할수록 공격 실루엣, 전진 거리, hitbox, knockback, hit-stop과 camera trauma를 점진적으로 강화한다.

Dictionary 기반 receive_hit 계약으로 피해량, 공격 방향, knockback, hit-stun 등의 전달 정보를 관리한다. Player는 피격 시 행동 제한과 시각 반응을 보이고 정상적으로 조작에 복귀한다.

TrainingDummy는 공격과 피격 회귀 검증에 사용하며 피격 이후 기준 위치로 복귀한다.

ForestRaider는 CharacterBody2D 적으로 구현한다. Player의 x/y를 추적하고 깊이 차이가 허용 범위일 때만 공격한다. telegraph 또는 windup, active, recovery, 공격 취소, separation, knockback, hit-stun을 구현한다.

전투 피드백은 짧은 camera trauma, 단계별 hit-stop, impact arc 또는 speed streak를 사용한다. 화면을 장시간 흔들거나 공격 가독성을 해치는 연출은 금지한다.

6. 스테이지 설계
Forest Ruins는 깊이감 있는 고품질 1920x1080 숲 유적 배경을 목표로 한다. 열린 중앙 원경, 나무와 유적의 거리감, 충분히 넓은 하단 전투 공간이 필요하다.

이전 forest_ruins_source_v4.png는 유력했던 후보지만 초기화된 저장소에는 존재하지 않는다. 확보되지 않은 원본에 의존하는 통합 작업을 지시하지 않는다. 신규 이미지 또는 실제 복구된 원본을 검수한 후 통합한다.

거대한 단색 바닥, 직사각형 procedural 숲, 수평 lane 표시선은 최종 렌더에서 사용하지 않는다. arena bounds는 논리적인 이동 제한으로 유지하며 시각적 lane UI와 분리한다.

정식 배경의 정규화, 정확한 크기, 이미지 품질, 카메라 smoothing과 trauma 시 외부 빈 영역 노출 여부를 검증한다.

7. 아트 제작 및 승인
RESOURCE는 WORK·QA·HIGH·Git과 독립적으로 즉시 수행한다. 생성 완료 여부와 관계없이 일반 개발을 진행한다. 미확보 자산을 임의로 대체하거나 승인된 것으로 표시하지 않는다.

플레이어 신규 단일 원화는 1254x1254 투명 PNG를 기준으로 한다. 모든 방향 90px 이상 안전 여백을 목표로 한다. alpha bounds뿐 아니라 자세, 해부학, 여성 얼굴, 귀, 머리카락, 손발, 복장, 약 165px 축소 시 가독성을 검수한다.

단일 기준 원화를 시각 승인하기 전에 대형 8x8 애니메이션 시트를 제작하지 않는다. 승인된 원화의 identity를 유지하며 idle, run, crouch, turn, jump, hit, attack1, attack2, attack3를 작은 상태별 프레임 그룹으로 확대한다.

애니메이션마다 얼굴과 복장이 달라지거나 foot anchor가 흔들리는 현상을 방지한다. 각 단계에서 시각 검토와 게임 내 검증을 거친다.

ForestRaider의 정식 아트는 Player와 stage가 안정된 이후 교체한다. 아트 교체 과정에서 물리·AI·피격 계약을 변경하지 않는다.

8. 마일스톤 로드맵
M1 FRESH_FOUNDATION: 빈 저장소에서 Godot 프로젝트, 루트 실행기, 최초 설계 문서, 기본 실행 씬 및 Player 이동 기반 구축.

M2 MOVEMENT_AND_VALIDATION: visual jump 전체 계약, crouch, turn, 카메라 경계, 정렬 및 자동 smoke 검증 완성.

M3 COMBAT_FOUNDATION: 3단 콤보, Dictionary hit 계약, TrainingDummy, ForestRaider 추적·공격·분리, 피격과 타격 피드백 완성.

M4 ART_INTEGRATION: 신규 숲 유적 배경, 승인된 Player 애니메이션, ForestRaider 아트, VFX와 실제 전투 화면 통합.

M5 POLISH_AND_ACCEPTANCE: 전투 밸런스, 카메라와 hit-stop, animation clipping, anchor jitter, y-sort, 성능, 시각 일관성, 전체 회귀 및 수동 인수 검증.

단계 분류는 초기 계획이며 실제 구현 결과에 따라 세부 마일스톤을 조정할 수 있다. 완료되지 않은 단계나 자산을 완료로 간주하지 않는다.

9. 필수 회귀 검증
프로젝트 로드, InputMap, Player scene, 이동, 방향 전환, arena bounds, y-sort, visual jump, coyote time, jump buffer, variable jump, crouch, hit-stun 중 점프 갱신, combo 3단, 공격 progress, receive_hit, knockback clamp, TrainingDummy, ForestRaider x/y pursuit, depth rejection, camera bounds와 trauma를 검증한다.

아트 도입 이후에는 PNG 치수와 alpha, 안전 여백, 스테이지 정규화, 예상 게임 표시 크기, 플레이 화면에서의 캐릭터 식별성, 프레임 전환 시 anchor, 실제 카메라 외부 노출 여부를 추가 검증한다.

QA는 실제 실행 결과와 재현 가능한 로그를 기반으로 판정한다. HIGH는 기능·구조·시각적 결함을 검토하고 가능한 수정을 수행한 뒤 재검증한다.

10. 최종 완료 기준
1920x1080 게임이 정상 실행되고 플레이어가 x/y 깊이 이동, 점프, 앉기, 방향 전환 및 3단 콤보를 안정적으로 수행한다.

적은 깊이와 거리를 고려해 추적·공격하며 피격과 넉백이 정상 작동한다. TrainingDummy와 다수 적을 대상으로 전투가 가능하다.

신규 고품질 배경 및 일관된 Player·ForestRaider 아트가 실제 씬에 통합되어 임시 procedural 시각물에 의존하지 않는다.

자동 smoke, 수동 플레이 검증, 아트 검수와 카메라 경계 검수가 통과한다. 치명적인 기능 오류, 캐릭터 잘림, anchor jitter, 잘못된 y-sort 및 지속적인 배경 공백이 없어야 한다.

11. 현재 M1 실행 원칙
현재 저장소는 빈 초기 커밋이므로 복구·수정이 아닌 신규 구현으로 진행한다.

이미 발행된 WORK 10~66은 재사용하지 않는다. 최초 신규 WORK는 67부터 시작한다.

이 마일스톤에서는 서로 충돌하지 않는 독립적인 두 WORK를 사용한다. WORK 67은 실행 가능한 Godot 기반, WORK 68은 최초 설계 문서 및 프로젝트 안내를 담당한다. 어느 WORK도 다른 WORK의 산출물 완료를 기다리지 않는다.

RESOURCE 0은 신규 Player 원화 제작을 즉시 시작하며 게임 기본 실행을 차단하지 않는다. 실제 승인 전까지 플레이어 씬은 독립적인 임시 시각 표현을 사용한다.
