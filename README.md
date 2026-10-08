# BeltScroll

BeltScroll은 Godot 4.7.2 기반의 1920×1080 2D 벨트스크롤 근접 액션 게임 프로젝트입니다. 목표는 성인 여성 엘븐 격투가의 좌우·깊이 이동, 점프, 앉기와 전신 동작을 활용한 전투입니다. 이동과 충돌은 바닥의 2D 좌표를 사용하고, 점프 높이는 시각 요소만 올려 표현합니다.

## 현재 구현 상태

저장소 초기화로 이전 게임 구현과 에셋이 작업 트리에서 제거됐습니다. 현재는 기본 arena, Y-sort 액터 레이어, 플레이어 이동·방향 전환·앉기·시각 점프와 간단한 공격 표시가 있는 초기 실행용 프로젝트입니다. 공격은 임시 표시만 제공하며 콤보, 적, 정식 아트는 아직 구현·통합되지 않았습니다.

플레이어 기준 원화(투명 1254×1254 PNG, 사방 90px 안전 여백 목표)는 생성·검수·승인 전입니다. 숲 유적 배경 및 캐릭터 애니메이션도 확보된 정식 자산으로 간주하지 않습니다. 현재 장면은 이미지 파일 없이 도형으로 실행되며, 이 임시 시각은 최종 아트가 아닙니다. 기술 계약과 마일스톤은 [최초 설계 문서](docs/projecthub/initial-plan.md)에 있습니다.

## 현재 디렉터리

```text
project.godot                 프로젝트 설정 및 InputMap
run_game.cmd                  Windows 기본 실행 및 smoke 진입점
scenes/game/main.tscn         arena, YSortActors, Player가 있는 메인 장면
scenes/player/player.tscn     플레이어와 Camera2D 장면
scripts/player/               플레이어 컨트롤러
docs/projecthub/initial-plan.md  기술 계약, 아트 기준, 로드맵 및 인수 기준
.godot/                       Godot가 생성하는 로컬 import/editor 캐시
```

적, 전투 시스템, 아트, 테스트 및 개발 도구 디렉터리는 아직 저장소에 없습니다. 필요할 때 설계 문서의 마일스톤에 따라 추가합니다.

## Windows 실행

Godot 4.7.2를 설치하고 `godot.exe`를 PATH에 추가하거나 `GODOT_EXE`에 실행 파일 경로를 지정한 뒤 프로젝트 루트에서 실행합니다.

```powershell
.\run_game.cmd
```

기본 실행기와 같은 진입점에서 headless smoke를 실행하려면 다음 명령을 사용합니다.

```powershell
.\run_game.cmd smoke
```

`--headless`를 직접 전달해도 headless 실행할 수 있습니다.

```powershell
.\run_game.cmd --headless --quit-after 3
```

## 입력

| 동작 | 기본 키 |
|---|---|
| 이동 | WASD 또는 방향키 |
| 점프 | Space |
| 앉기 | C 또는 아래 방향키 |
| 공격 표시 | J 또는 왼쪽 마우스 버튼 |

아래 방향키는 이동과 앉기 액션에 모두 연결됩니다. S는 아래 이동에 연결됩니다. 공격 입력은 현재 임시 공격 표시만 켭니다.

## 리소스 상태

- 플레이어 원화: `assets/art/player/elven_fighter_reference_v1_1254x1254.png`는 요청 예정 경로입니다. 현재 파일은 없으며 생성·치수·alpha·여백·시각 검수 및 승인 전입니다. 목표는 투명 PNG 1254×1254와 사방 90px 이상 안전 여백입니다.
- Forest Ruins 배경, ForestRaider 및 애니메이션: 초기화 후 보유 파일이 없습니다.
- 임시 도형 시각: 실행을 위한 개발 표현이며 최종 아트가 아닙니다.
