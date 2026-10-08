# BeltScroll

BeltScroll은 Godot 4.7.2 기반의 1920×1080 2D 벨트스크롤 액션 게임입니다. 실행하면 Forest Ruins 배경을 사용한 타이틀 메뉴가 먼저 열립니다. 메뉴에서 게임 시작, 조작 안내, 종료를 선택할 수 있으며 게임 시작은 기존 전투 장면으로 이동합니다.

## 현재 구현 상태

- **타이틀 메뉴:** 어두운 반투명 그라데이션 위에 BELT SCROLL 제목과 금색·녹청색 버튼을 표시합니다. 마우스 클릭과 키보드 포커스 이동·Enter 선택을 지원하며 조작 안내 패널은 Esc로 닫을 수 있습니다.
- **전투:** 플레이어와 Forest Raider 3명, Training Dummy, 전투 HUD, 공격·피격 연출과 오디오, 일시정지, 승리·패배 화면 및 R 재시작이 구현되어 있습니다. 전투 장면은 `scenes/game/main.tscn`이며 smoke 테스트는 이 장면을 직접 불러옵니다.
- **아트:** Forest Ruins 배경과 적 스프라이트가 `assets/art`에 있습니다. 플레이어 v8 원본은 보존되어 있고, 정규화 safe 후보와 국소 오염 복원 clean 후보 및 흰색·검정·체커보드·숲 배경/192px 비교가 포함되어 있습니다. clean 후보는 확대 비교에서 붉은 덩어리 제거와 머리카락·얼굴·귀·손·장식 보존을 확인해 시각 검수 통과했습니다. safe 후보는 원본 보존용이며 미정리 상태입니다. v8 플레이어 이미지는 게임 씬에 연결하지 않았습니다.

## 주요 경로

```text
project.godot                    프로젝트 설정 및 기본 실행 씬
run_game.cmd                     Windows 실행 및 smoke 진입점
scenes/ui/title_menu.tscn        Forest Ruins 타이틀 메뉴
scripts/ui/title_menu.gd         메뉴, 도움말 패널, 장면 전환 및 종료
scenes/game/main.tscn            전투 장면
scenes/player/player.tscn        플레이어와 Camera2D
scenes/enemies/forest_raider.tscn Forest Raider
scenes/combat/training_dummy.tscn Training Dummy
scenes/ui/combat_hud.tscn        전투 HUD
tests/title_menu_smoke.gd        메뉴·버튼·전환 독립 smoke
tests/                            기능별 독립 smoke 테스트
docs/projecthub/initial-plan.md  기술 계약 및 프로젝트 계획
```

## 실행

Godot 4.7.2를 설치하고 `godot.exe`를 PATH에 추가하거나 `GODOT_EXE`에 실행 파일 경로를 지정한 뒤 프로젝트 루트에서 실행합니다.

```powershell
.\run_game.cmd
```

메뉴에서 **게임 시작**을 선택하면 `scenes/game/main.tscn`이 열립니다. 전투 장면을 바로 실행할 수도 있습니다.

```powershell
godot --path . res://scenes/game/main.tscn
```

메뉴 독립 smoke:

```powershell
godot --headless --path . --script res://tests/title_menu_smoke.gd
```

전체 기능 smoke 묶음:

```powershell
.\run_game.cmd smoke
```

## 조작

### 메뉴

마우스로 버튼을 클릭하거나 Tab 및 방향키로 포커스를 옮기고 Enter 또는 Space로 선택합니다. 조작 안내 패널에서는 Esc 또는 돌아가기 버튼을 사용합니다.

### 전투

| 동작 | 입력 |
|---|---|
| 이동 | WASD 또는 방향키 |
| 점프 | Space |
| 앉기 | C |
| 공격 | J 또는 왼쪽 마우스 버튼 |
| 일시정지 / 재개 | Esc |
| 조작 도움말 | H |
| 승리·패배 화면에서 재시작 | R |

아래 방향키는 이동과 앉기 입력에 모두 연결되어 있습니다. S는 아래 방향 이동에 사용됩니다.

## 검수 상태

`tests/title_menu_smoke.gd`는 메뉴 리소스 로드, Tab/Enter/Esc와 마우스 클릭 입력, 포커스 표시, 안내 패널, 종료 요청 및 기존 메인 전투 장면 전환을 확인합니다. 타이틀 메뉴는 Godot 4.7.2 OpenGL Window Viewport에서 1920×1080으로 캡처해 배경·그라데이션·텍스트·포커스 표시를 시각 확인했습니다. 변경 후 실제 실행 결과는 각 smoke 명령의 종료 코드와 PASS 출력으로 확인합니다.
