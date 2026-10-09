# BeltScroll

BeltScroll은 Godot 4.7.2 기반의 1920×1080 2D 벨트스크롤 액션 게임입니다. 실행하면 Forest Ruins 배경을 사용한 타이틀 메뉴가 먼저 열립니다. 메뉴에서 게임 시작, 조작 안내, 종료를 선택할 수 있으며 게임 시작은 기존 전투 장면으로 이동합니다.

## 현재 구현 상태

- **타이틀 메뉴:** 어두운 반투명 그라데이션 위에 BELT SCROLL 제목과 금색·녹청색 버튼을 표시합니다. 마우스 클릭, 키보드·게임패드 포커스 이동, 확인·취소를 지원하며 안내 패널을 닫으면 이전 버튼으로 포커스가 돌아옵니다.
- **전투:** 플레이어와 Forest Raider 3명, Training Dummy, 전투 HUD, 공격·피격 연출과 오디오, 계속하기·재시작·타이틀 이동 버튼이 있는 일시정지 메뉴, 재도전·타이틀 이동 버튼이 있는 승리·패배 화면이 구현되어 있습니다. 결과·일시정지 패널은 현재 배우와 HUD 위치를 바탕으로 가림이 적은 곳에 배치됩니다. 버튼은 마우스와 키보드·게임패드 포커스를 지원하며 ESC·R 조작도 유지합니다. 전투 장면은 `scenes/game/main.tscn`이며 smoke 테스트는 이 장면을 직접 불러옵니다.
- **아트:** Forest Ruins 배경과 적 스프라이트가 `assets/art`에 있습니다. 플레이어 v8 clean 원화는 `PlayerArt` 정지 이미지로 게임에 연결되어 있습니다. 대기·이동·점프·공격·피격·KO는 별도 VisualAnimator가 Sprite 변환으로 표현하며, 프레임 애니메이션이 아닙니다. 정규화 safe 후보와 승인된 clean 후보 및 흰색·검정·체커보드·숲 배경/192px 비교를 함께 보존합니다.

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
tests/gamepad_input_smoke.gd     합성 게임패드 입력·deadzone·결과 재시작 smoke
tests/game_session_navigation_smoke.gd 일시정지·결과 메뉴 경로와 씬 전환 상태 복원 smoke
tests/                            기능별 독립 smoke 테스트
tests/editor_executable_smoke.ps1 독립 편집기 EXE 인수 검증
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

합성 게임패드 입력 smoke:

```powershell
godot --headless --path . --script res://tests/gamepad_input_smoke.gd
```

전체 기능 smoke 묶음:

```powershell
.\run_game.cmd smoke
```

## 조작

### 메뉴

마우스로 버튼을 클릭하거나 Tab 및 방향키·왼쪽 스틱·십자키로 포커스를 옮기고 Enter, Space 또는 남쪽 버튼(A/Cross)으로 선택합니다. 조작 안내 패널에서는 Esc, 동쪽 버튼(B/Circle) 또는 돌아가기 버튼을 사용합니다.

### 전투

| 동작 | 입력 |
|---|---|
| 이동 | WASD 또는 방향키, 왼쪽 스틱, 십자키 |
| 점프 | Space, 남쪽 버튼(A/Cross) |
| 공격 | J, 왼쪽 마우스 버튼, 서쪽 버튼(X/Square) |
| 방어 | 왼쪽 Shift, 동쪽 버튼(B/Circle) |
| 공격 | Num1 |
| 점프 | Num2 |
| 막기 | Num3 |
| 스킬 슬롯 1~2 | Num4~Num5 (현재 스킬 미구현) |
| 예약 입력 | Num6~Num9 |
| 일시정지 / 재개 | Esc, Start |
| 조작 도움말 열기 / 닫기 | H, Select/Back |
| 일시정지 메뉴 선택 | 마우스, 방향키·스틱·십자키, Enter·남쪽 버튼 |
| 승리·패배 화면에서 재시작 | R, 북쪽 버튼(Y/Triangle), 재도전 버튼 |
| 타이틀로 돌아가기 | 일시정지·결과 메뉴의 타이틀 버튼 |

WASD와 방향키는 상·하·좌·우 이동입니다. 숫자 키는 Num1 공격, Num2 점프, Num3 막기, Num4~Num5 스킬 슬롯, Num6~Num9 예약입니다. 스킬 기능은 아직 구현되지 않았습니다. 스틱 이동 deadzone은 0.2입니다.

## 독립 편집기 EXE 인수 검증

`dist/BeltScrollEditor.exe` 산출물의 존재·실행·`--self-test`, GUI 동작과 프로젝트 외부 경로 실행을 확인하려면 [편집기 EXE 인수 게이트](docs/review/editor_acceptance_gate.md)를 따릅니다.

```powershell
.\tests\editor_executable_smoke.ps1
```

인수 게이트를 통과하기 전에는 독립 편집기 EXE의 배포가 완료되었다고 간주하지 않습니다.

## 검수 상태

`tests/title_menu_smoke.gd`는 메뉴 리소스 로드, Tab/Enter/Esc와 마우스 클릭 입력, 포커스 표시, 안내 패널, 종료 요청 및 기존 메인 전투 장면 전환을 확인합니다. `tests/gamepad_input_smoke.gd`는 물리 패드 없이 합성 조이스틱 버튼·축 이벤트로 InputMap 연결, deadzone, 축 해제 시 정지와 결과 화면 재시작을 확인합니다.

`tests/game_session_navigation_smoke.gd`는 일시정지 계속하기·재시작·타이틀 이동, VICTORY·DEFEAT 각각의 재도전·타이틀 이동, 중복 요청 방지와 전환 후 pause·time scale·hit-stop·CombatAudio 복원을 확인합니다.

`tests/gameplay_endings_window_smoke.gd`는 실제 Window 화면에서 기본 시작 위치와 일반 WASD 이동 후 위치의 승리·패배 패널, 배우/HUD 가림, 버튼 포커스와 타이틀 복귀를 캡처합니다.
