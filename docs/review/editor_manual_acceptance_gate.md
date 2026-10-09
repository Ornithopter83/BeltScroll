# 독립 편집기 EXE 수동 인수 게이트

## 목적

이 게이트는 독립 실행 파일의 자동 동작과 실제 사용자의 GUI 인수를 별도 상태로 기록합니다. `editor_executable_smoke.ps1`의 기본 모드는 자동 self-test와 GUI acceptance를 실행한 뒤 실제 편집기 창에서 사용자가 기능을 확인하고 각 Y/N 질문에 답해야 합니다. 표준 입력을 리디렉션한 환경에서는 수동 검수를 완료할 수 없으므로 승인하지 않고 종료 코드 `2`와 `manual_status=blocked_unverified`를 기록합니다.

`-AutomatedOnly`는 자동 self-test와 GUI acceptance까지만 실행합니다. 자동 검사가 통과하면 종료 코드 `0`을 반환합니다. 이 결과는 전체 수동 인수가 통과했다는 뜻이 아니며 보고서의 `manual_status`와 전체 `status`는 `blocked_unverified`로 남습니다. 자동 모드가 사용하는 GUI acceptance는 보이는 WinForms 메시지 루프와 내부 컨트롤 호출을 시험합니다. 보고서의 `actualOsMouseInput=false`가 나타내듯 OS 마우스 입력이나 사용자의 시각 검수를 수행하지 않습니다.

## Windows PowerShell 5.1 실행

프로젝트 루트에서 UTF-8 출력 설정을 적용하고 실행합니다.

```powershell
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
Get-Content -Encoding UTF8 .\docs\review\editor_manual_acceptance_gate.md
```

기본 수동 인수 모드:

```powershell
.\tests\editor_executable_smoke.ps1 -EditorPath .\dist\BeltScrollEditor.exe
```

자동 검사만 수행:

```powershell
.\tests\editor_executable_smoke.ps1 -EditorPath .\dist\BeltScrollEditor.exe -AutomatedOnly
```

두 모드의 종료 코드와 보고서 상태를 검증하려면 다음 스모크를 실행합니다. 실행 파일이 없으면 먼저 `editor\build_editor.ps1 -SelfTest`로 만듭니다.

```powershell
.\tests\editor_executable_modes_smoke.ps1 -EditorPath .\dist\BeltScrollEditor.exe
```

## 자동 검사와 산출물

두 모드 모두 동일한 지정 EXE에서 `--self-test` 및 `--gui-acceptance <임시 작업 폴더>`를 실행합니다. GUI acceptance는 WinForms 창을 띄워 생성·복제·편집·삭제, 잘못된 범위 거부, 잘못된 JSON 거부, 저장 실패 보호, JSON 저장·재열기, 백업 복구와 미지 필드 보존을 검사합니다. 작업 폴더는 프로젝트 외부 임시 경로이며 자동 삭제하지 않습니다.

검사 폴더에는 `gui-acceptance.json`, `gui-capture.png`, `overrides.json`, `overrides.json.bak`, 잘못된 JSON fixture, 로그가 기록됩니다. 저장 JSON을 다시 읽어 저장값을 확인하고 백업 파일 존재를 확인합니다. GUI acceptance 보고서는 `actualOsMouseInput=false`, 실제 실행 경로와 출력 JSON 경로를 기록합니다. 바깥쪽 `acceptance-report.json`은 EXE의 절대 경로, 작업 폴더, 체크별 자동/수동 분류 및 상태를 기록합니다.

자동 검사 실패는 두 모드에서 exit `1`입니다. 자동 검사가 성공한 경우 `AutomatedOnly`는 exit `0`이고 `automated_status=passed`, `manual_status=blocked_unverified`, `status=blocked_unverified`를 기록합니다.

## 실제 GUI 인수 절차

기본 모드가 띄운 편집기 창에서 다음 동작을 직접 실행하고 확인한 뒤 각 질문에 `Y` 또는 `N`으로 답합니다.

1. 제공된 malformed JSON을 열거나 가져와 오류를 표시하고 데이터 적용을 거부하는지 확인합니다.
2. 데이터 항목을 생성하고 복제한 뒤 복제본의 필드를 수정해 저장합니다.
3. 저장한 값을 닫았다가 다시 열어 보존 여부를 확인합니다.
4. 게임 데이터를 다시 적용하거나 동기화해 항목과 값을 확인합니다.
5. 편집기를 정상 종료합니다.

각 Y/N 응답은 해당 동작을 사람이 직접 실행해 결과를 확인한 뒤에만 입력합니다. 자동 GUI 입력은 이 절차를 대신하지 않습니다. 표준 입력이 리디렉션되었거나 콘솔 입력을 할 수 없으면 수동 결과는 `blocked_unverified`이며 exit `2`입니다. 이 종료 코드는 승인이나 실패 판정이 아니라 인수 미완료를 구분합니다. 수동 동작에 `N`을 입력하면 수동 인수 실패로 exit `1`입니다.

## 보고서 판독

보고서에는 `mode`, `automated_status`, `manual_status`, `status`, `passed`, `editorPath`, `externalWorkingDirectory`, `results`가 포함됩니다. `passed=true`는 AutomatedOnly에서 자동 검사만 성공했다는 뜻입니다. 전체 승인을 나타내는 값으로 사용하지 마세요. 수동 인수 승인에는 기본 모드에서 실제 GUI 조작을 마치고 모든 Y/N 항목을 확인해 `manual_status=passed`와 `status=passed`가 기록되어야 합니다.
