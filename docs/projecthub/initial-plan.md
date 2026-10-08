# BeltScroll 최초 설계 및 완료 기준

## 문서의 목적과 저장소 상태

이 문서는 BeltScroll을 초기화된 저장소에서 새로 구축하기 위한 최초 제품 계획이다. 이후 WORK는 이 문서의 기술 계약과 품질 기준을 출발점으로 삼고, 실제 구현 상태에 맞춰 세부 일정을 조정한다. 완료되지 않은 기능이나 확보되지 않은 자산을 완료 또는 승인 상태로 표시하지 않는다.

이 작업 전 초기화 과정에서 이전 구현과 게임 리소스가 제거되어 현재 작업 트리에서 재사용할 수 없다. 이전에 존재했던 스크립트, 장면, 테스트, 실행기, 이미지가 현재 파일로 남아 있다고 가정하지 않는다. 과거 인수인계와 커밋 이력은 요구사항을 이해하는 참고 기록일 뿐 복구된 구현의 증거가 아니다. 현재 이 문서와 ProjectHub 작업 메타데이터가 보인다는 사실은 게임 구현이 남아 있다는 뜻이 아니다. 따라서 게임은 새 Godot 프로젝트와 새 파일로 만든다.

ProjectHub 계획에서 제시된 기준 저장소는 `https://github.com/Ornithopter83/BeltScroll.git`, 기준 브랜치는 `origin/main`, 당시 확인 SHA는 `96aaa6d02ac1ab44f6290600d4687f9d9434c61b` (`Initial commit`)이다. 이 기준 정보는 계획 작성 기록이며, 현재 원격 상태를 새로 조회했다는 의미가 아니다. 초기화된 게임 작업 트리에서는 이전 구현을 끌어오거나 의존하지 않는다.

## 제품 목표

Godot 4.x 기반의 1920×1080 2D 벨트스크롤 근접 액션 게임을 제작한다. 호환성 및 개발 기준은 Godot 4.7.2다. 플레이어는 무기를 사용하지 않는 성인 여성 엘븐 격투가다. 캐릭터는 긴 뾰족귀, 식별 가능한 여성 얼굴, 운동선수형 체형, 긴 포니테일 또는 묶은 머리, 짙은 녹청색 경량 전투복, 갈색 장갑과 부츠, 절제된 금색 장식을 갖춘다.

전투 화면에서 캐릭터 표시 높이는 약 170~210px를 목표로 한다. 이 크기에서도 얼굴, 귀, 양팔과 양다리, 의상 및 공격 자세의 실루엣을 알아볼 수 있어야 한다. 최종 게임은 조작에 정확히 반응하고, 읽기 쉬운 피격 판정과 강한 타격감을 제공하며, 고품질 숲 유적 배경과 일관된 캐릭터 애니메이션을 사용해야 한다.

## 기술 및 디렉터리 계약

- 플레이어와 ForestRaider는 물리 기반 `CharacterBody2D`로 구현한다.
- 월드 물리 좌표 `Vector2(x, y)`는 지면 평면이다. `y`는 벨트스크롤 깊이를 나타낸다. 점프 높이와 속도는 `jump_height`, `jump_velocity` 등 별도 상태로 계산해 표시 위치에만 반영한다. 점프 중에도 물리 바닥 좌표와 깊이 정렬은 유지한다.
- 월드 경계, 충돌, 깊이 정렬, 카메라 이동은 같은 전투 공간을 기준으로 설계한다. 액터는 `YSortActors`의 y-sort를 사용하고 캐릭터 발 위치와 그림자가 깊이 정렬 기준과 일치해야 한다.
- 코드, 장면, 아트, 테스트, 도구, 문서를 다음과 같이 분리한다. 실제 하위 파일은 마일스톤에서 추가한다.

```text
project.godot
run_game.cmd
scenes/
  game/
  player/
scripts/
  game/
  player/
  enemies/
  combat/
assets/
  art/
    player/
    enemies/
    stage/
tests/
tools/
docs/
  projecthub/
```

- 루트의 `run_game.cmd`를 Windows 기본 실행 및 headless smoke 실행의 진입점으로 제공한다. 이미지가 아직 없어도 프로젝트가 실행되어야 한다. 임시 도형이나 대체 표시는 개발용으로만 허용하고 정식 아트로 승인하지 않는다.

## 이동 및 점프 계약

플레이어는 지면 평면의 x/y 이동, 대각선 정규화, 이동 방향 전환, arena bounds 제한, 앉기(crouch), 시각 점프를 구현한다. 좌우 방향 전환과 캐릭터 발 기준 anchor를 일관되게 유지해 애니메이션 프레임이 바뀌어도 바닥 위치가 흔들리지 않아야 한다.

점프에는 coyote time, jump buffer, variable jump height, 상승·하강·착지 상태를 포함한다. hit-stun 중에도 시각 점프 상태 갱신은 계속되어야 한다. 점프 높이는 바닥 이동 좌표나 y-sort를 바꾸지 않는다. 카메라 경계와 arena 경계는 별도로 검증한다.

## 전투 및 적 계약

플레이어는 준비(telegraph), contact, recovery 구간이 구분되는 3단 연속 근접 콤보를 가진다. `attack_progress`와 표시 애니메이션 프레임은 동기화한다.

1. 1타는 빠르고 큰 횡공격이며 짧지만 분명한 lunge와 전신 체중 이동을 포함한다.
2. 2타는 더 넓은 회전 sweep이다. 무릎, 발, 골반, 몸통, 어깨와 양팔이 함께 움직이고 포니테일 follow-through가 강조된다.
3. 3타는 가장 깊은 준비와 가장 넓은 contact 실루엣을 가진 상승형 finisher다.

콤보 단계가 올라갈수록 공격 실루엣, 전진 거리, hitbox, knockback, hit-stop, camera trauma를 점진적으로 강화한다. 피격 전달은 피해량, 공격 방향, knockback, hit-stun 등 정보를 담는 Dictionary 기반 `receive_hit` 계약을 사용한다. 플레이어는 피격 시 조작 제한과 flash 또는 squash 계열 시각 반응을 보이고, hit-stun 이후 정상 조작으로 복귀한다.

`TrainingDummy`는 공격·피격 회귀 검증에 쓰며, 피격 후 기준 위치로 돌아온다. `ForestRaider`는 x와 y 모두에서 플레이어를 추적하고 깊이 차이가 허용 범위일 때만 공격한다. 적의 공격은 telegraph/windup, active, recovery 상태를 갖고, 깊이 범위를 벗어나면 취소될 수 있다. 적은 분리(separation), knockback, hit-stun 및 같은 Dictionary hit 계약을 지원하며 여러 적이 영구적으로 겹치지 않아야 한다.

타격 연출은 짧은 camera trauma, 콤보 단계별 hit-stop, impact arc 또는 speed streak로 구성한다. 장시간 흔들림이나 공격·캐릭터를 가리는 연출은 허용하지 않는다.

## 스테이지 및 카메라 기준

Forest Ruins는 깊이감 있는 고품질 1920×1080 배경을 목표로 한다. 중앙 원경은 열려 있어야 하고, 나무와 유적의 원근 및 거리감, 충분히 넓은 하단 전투 공간을 제공해야 한다. 이전에 후보였던 `forest_ruins_source_v4.png`를 포함해 과거의 배경 파일은 초기화 뒤 현재 자산으로 존재하지 않으므로, 확보·복구를 확인하지 않고 통합 대상으로 가정하지 않는다.

최종 렌더에서는 거대한 단색 바닥, 직사각형 procedural 숲, 수평 lane 안내선을 사용하지 않는다. 논리적인 arena bounds는 시각적 lane UI와 분리한다. 정식 배경은 정확한 규격과 품질을 검수하고, 카메라 smoothing 및 trauma가 화면 바깥의 빈 영역을 노출하지 않는지 확인한다.

## 아트 제작 및 승인 기준

RESOURCE 아트 작업은 일반 개발, WORK, QA, HIGH 및 Git 진행과 독립적이며 아트 생성 결과를 기다리느라 기본 개발을 멈추지 않는다. 초기 리소스 요청 대상은 `assets/art/player/elven_fighter_reference_v1_1254x1254.png`이며, 생성 완료 여부와 관계없이 일반 개발을 진행한다. 아직 확보되지 않은 자산을 임의 대체하거나 승인된 것으로 표시하지 않는다.

플레이어 기준 원화는 오른쪽을 바라보는 성인 여성 엘븐 격투가의 전신, 투명 PNG, 1254×1254를 기준으로 한다. 사방 최소 90px의 투명 안전 여백을 목표로 한다. alpha bounds만으로 승인하지 않고 자세, 해부학, 얼굴, 귀, 머리카락, 손발, 복장 및 약 165px 표시 크기에서의 식별성을 함께 검수한다. 바닥 그림자·배경·문자·장식 프레임은 포함하지 않는다.

단일 기준 원화를 시각 승인하기 전에 대형 8×8 애니메이션 시트를 제작하지 않는다. 승인된 원화의 identity를 유지하며 idle, run, crouch, turn, jump, hit, attack1, attack2, attack3 애니메이션을 작은 상태별 프레임 그룹으로 확장한다. 얼굴·복장 변화와 발 anchor 흔들림을 막고 각 단계에서 시각 검토 및 게임 내 검증을 수행한다. ForestRaider 정식 아트는 플레이어와 스테이지가 안정된 후 교체한다. 아트 교체 과정에서 물리, AI, 피격 계약을 변경하지 않는다.

## 마일스톤 로드맵

| 단계 | 이름 | 완료 범위 |
|---|---|---|
| M1 | `FRESH_FOUNDATION` | 초기화된 저장소에 Godot 프로젝트, 루트 실행기, 최초 설계 문서, 기본 실행 씬과 Player 이동 기반을 구축한다. |
| M2 | `MOVEMENT_AND_VALIDATION` | visual jump 전체 계약, crouch, turn, 카메라 경계, y-sort 및 자동 smoke 검증을 완성한다. |
| M3 | `COMBAT_FOUNDATION` | 3단 콤보, Dictionary hit 계약, TrainingDummy, ForestRaider 추적·공격·분리, 피격 및 타격 피드백을 완성한다. |
| M4 | `ART_INTEGRATION` | 신규 숲 유적 배경, 승인된 Player 애니메이션, ForestRaider 아트와 VFX를 실제 전투 화면에 통합한다. |
| M5 | `POLISH_AND_ACCEPTANCE` | 전투 밸런스, 카메라와 hit-stop, animation clipping, anchor jitter, y-sort, 성능, 시각 일관성, 전체 회귀 및 수동 인수 검증을 마친다. |

세부 일정 및 단계 분류는 구현 결과에 따라 조정할 수 있다. 조정은 완료 사실을 과장하거나 미완료 기능·아트를 완료로 취급하는 근거가 되지 않는다.

M1의 초기 분담 기록상 WORK 67은 실행 가능한 Godot 기반을, WORK 68은 최초 설계 및 안내 문서를 담당하며 상호 완료를 기다리지 않는 독립 작업이다. RESOURCE 0은 별도로 신규 Player 기준 원화 생성을 시작한다. RESOURCE 결과가 늦거나 실패해도 임시 시각으로 기본 실행을 진행한다. 이 기록은 해당 작업들이 완료되었다는 판정이 아니다.

## 필수 회귀 및 아트 검증

QA는 실제 실행과 재현 가능한 결과를 기준으로 판정한다. 최소한 다음 항목을 점검한다.

- Godot 프로젝트 로드, InputMap, Player scene 및 Windows 실행기
- x/y 이동, 대각선 정규화, 방향 전환, arena bounds, y-sort
- visual jump와 바닥 좌표 분리, coyote time, jump buffer, variable jump, crouch 및 hit-stun 중 점프 갱신
- 3단 콤보, 공격 progress, Dictionary `receive_hit`, knockback clamp, TrainingDummy 복귀
- ForestRaider의 x/y 추적, depth rejection, 공격 상태와 취소, separation
- 카메라 경계·smoothing·trauma 및 카메라 영역 밖 빈 공간 노출
- 외부 이미지가 없어도 기본 게임이 실행되는지 여부

아트 도입 후 PNG 치수와 alpha, 사방 안전 여백, 스테이지 규격화, 예상 게임 표시 크기의 식별성, 애니메이션 프레임 사이 anchor, 실제 카메라에서의 배경 공백 노출을 추가 검증한다. HIGH 검토에서는 기능·구조·시각 결함을 살피고 수정 가능한 항목은 수정한 뒤 재검증한다.

## 최종 완료 기준

최종 제품은 1920×1080 게임으로 정상 실행되어야 한다. 플레이어는 x/y 깊이 이동, 점프, 앉기, 방향 전환 및 3단 콤보를 안정적으로 수행한다. 적은 거리와 깊이를 고려해 추적·공격하고 피격·넉백이 정상 작동한다. TrainingDummy와 여러 적을 대상으로 실제 전투를 할 수 있어야 한다.

신규 고품질 숲 유적 배경과 identity가 일관된 Player·ForestRaider 아트가 실제 씬에 통합되어 임시 procedural 시각물에 의존하지 않아야 한다. 자동 smoke, 수동 플레이, 아트 검수, 카메라 경계 검증을 통과해야 한다. 치명적인 기능 오류, 캐릭터 잘림, anchor jitter, 잘못된 y-sort, 지속적인 배경 공백이 없어야 한다.