# 독립 편집기 → Godot 전투 장면 종단 간 게이트

## 목적

이 게이트는 독립 `BeltScrollEditor.exe`의 보이는 WinForms GUI에서 프로젝트의 실제 `Player`, `ForestRaider`, `ForestRuins` 레코드를 편집·저장한 뒤, 저장한 JSON을 프로젝트의 `data/editor/overrides.json`에 임시 적용하고 Godot 전투 장면을 새 프로세스로 실행해 값이 적용되는지 확인합니다. 종료 시 원본 파일을 임시 백업에서 복원하고 원본 SHA256과 복원 파일 SHA256이 같은지 검사합니다.

GUI 인수 드라이버는 보이는 창의 실제 WinForms 폼과 컨트롤 이벤트를 메시지 루프에서 실행합니다. OS 마우스 이동·클릭 주입 여부는 별도로 기록하며, 현재 드라이버는 OS 마우스 입력을 사용하지 않습니다. Godot 검사는 `scenes/game/main.tscn`을 실제 창이 있는 실행으로 띄워 데이터 적용을 확인하고 뷰포트 캡처를 남깁니다.

## 실행

새로 빌드한 독립 EXE를 지정해 Windows PowerShell 5.1에서 실행합니다. 파일 입출력과 출력은 UTF-8을 사용합니다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
.\tests\editor_gui_runtime_roundtrip_smoke.ps1 -EditorPath '.\dist\BeltScrollEditor.exe' -GodotPath 'C:\Project\Godot\godot.exe'
```

기본 EXE 경로는 `dist\BeltScrollEditor.exe`이고 기본 Godot 경로는 `C:\Project\Godot\godot.exe`입니다. 다른 설치 위치면 `-GodotPath`로 지정합니다. 게이트는 자체 시험 결과를 프로젝트의 `.qa_logs`에 복사하지 않고 `%TEMP%\BeltScrollEditorGameBridge_<id>`에 보존하며, 해당 경로를 콘솔에 출력합니다.

## 자동 편집값과 판정

GUI는 원본 overrides를 로드하고 다음 필드를 실제 편집기 컨트롤로 변경해 저장한 다음 재열기합니다.

- `Player`: 체력 9, 이동 속도 301, 레코드 공격력 13
- `ForestRaider`: 체력 6, 이동 속도 131, 공격력 4, AI 감지 범위 610, 공격 깊이 허용치 42, 분리 반경 126, 분리 강도 147
- `ForestRuins`: Player 배치 (946, 792), ForestRaider 배치 (710, 772)

게임 probe는 저장한 파일을 다시 읽고 메인 전투 장면을 인스턴스화해 Player 체력/속도, ForestRaider 체력/속도/공격력/AI, Player와 ForestRaider 배치를 런타임 객체에서 검사합니다. Player의 `attack_damage`는 현재 게임 런타임이 캐릭터 공격 피해를 오버라이드하는 필드로 지원하지 않으므로 저장 레코드에서 값이 재로딩되는 것까지만 확인합니다. 해당 값이 Player 전투 피해를 바꾼다고 주장하지 않습니다.

게이트 성공 조건은 GUI 보고서·캡처와 종료 코드 0, 게임 적용 보고서·캡처와 종료 코드 0, 원본 overrides 복원 및 SHA256 일치입니다. 전체 `editor-game-bridge-report.json`에는 GUI/게임/복원 종료 코드와 결과, 원본 및 복원 SHA256, 캡처 경로, `actualOsMouseInput: false`가 남습니다. 단계별 종료 코드 파일은 `gui-exit-code.txt`, `game-exit-code.txt`, `restore-exit-code.txt`, 전체 종료 코드는 `exit-code.txt`입니다. GUI 인수 보고서는 `gui-acceptance.json`, 게임 적용 보고서는 `game-application.json`이며, 캡처는 `gui-capture.png`와 `game-live-scene.png`입니다.

스크립트는 실제 overrides 파일을 덮기 전에 artifact 폴더에 바이트 그대로 임시 백업합니다. 성공·실패·시간 초과 모두 `finally`에서 복원을 시도하고 SHA256을 기록합니다. 백업이 만들어지기 전 실패한 경우 게임 단계로 진행하지 않습니다. artifact 폴더는 검토를 위해 자동 삭제하지 않습니다.
