# 독립 편집기 EXE 인수 게이트

## 목적과 판정

이 게이트는 빌드 산출물 `dist/BeltScrollEditor.exe`를 프로젝트 실행 환경과 분리해 확인합니다. 스크립트가 파일 존재, `--self-test`, 실제 WinForms 메시지 루프를 사용하는 `--gui-acceptance`, 프로젝트 외부 작업 디렉터리 실행을 점검합니다. 자동 모드는 생성·복제·수정·삭제, 범위 오류, 잘못된 JSON 거부, 저장·재열기·백업, 원본 필드 보존과 정상 종료를 실행합니다. 게임 재적용은 게임 런타임 통합이 별도로 필요한 수동 확인 항목으로 유지합니다.

이 게이트가 통과되기 전에는 편집기 실행 파일의 배포 완료를 주장하지 않습니다. 스크립트는 인수 시험 도구이며 배포를 수행하지 않습니다. GUI 항목을 Y로 확인하는 행위는 해당 동작을 직접 실행하고 결과를 본 뒤에만 진행합니다.

## 실행

프로젝트 루트의 Windows PowerShell 5.1에서 실행합니다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Get-Content -Encoding UTF8 .\docs\review\editor_acceptance_gate.md
.\tests\editor_executable_smoke.ps1
```

다른 빌드 위치를 확인할 때는 경로를 지정합니다.

```powershell
.\tests\editor_executable_smoke.ps1 -EditorPath 'D:\build\BeltScrollEditor.exe' -SelfTestTimeoutSeconds 120
```

`--self-test`는 제한 시간 내에 종료해야 하며 종료 코드 0을 반환해야 합니다. GUI는 임시 폴더를 현재 작업 디렉터리로 실행합니다. 이 폴더는 프로젝트 디렉터리 바깥이며 시험 파일과 JSON 보고서를 포함합니다. 보고서 경로는 스크립트 마지막에 출력됩니다. 시험 폴더는 검토를 위해 자동 삭제하지 않습니다.

`--gui-acceptance <임시 폴더>`는 실제 창을 표시하고 메시지 루프에서 자동 조작합니다. 해당 폴더에 `gui-acceptance.json`, `gui-capture.png`, `exit-code.txt`, 저장 결과 `overrides.json`, 백업 `overrides.json.bak`, malformed JSON fixture와 로그를 보존합니다. 직접 실행할 때는 프로젝트 밖의 임시 경로를 지정합니다.

빌드 직후 self-test와 GUI 인수 시험을 함께 실행할 수 있습니다.

```powershell
.\editor\build_editor.ps1 -SelfTest -GuiAcceptance
```

```powershell
$acceptanceDir = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollEditorGui_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $acceptanceDir | Out-Null
& .\dist\BeltScrollEditor.exe --gui-acceptance $acceptanceDir
Get-Content -Encoding UTF8 (Join-Path $acceptanceDir 'gui-acceptance.json')
```

## GUI 확인 순서

스크립트가 제공하는 `malformed-editor-data.json`을 편집기에서 열거나 가져와 JSON 구문 오류를 거부하는지 확인합니다. 오류가 표시되고 기존 데이터가 적용되거나 손상되지 않아야 합니다. 이후 GUI에서 다음 과정을 실제로 수행하고 각 질문에 `Y` 또는 `N`으로 답합니다.

1. 새 게임 데이터 항목을 생성합니다.
2. 해당 항목을 복제하고 복제본의 필드를 수정합니다.
3. 복제본을 저장하고 닫습니다.
4. 파일/항목을 다시 열어 수정값과 원본·복제본 구분이 유지되는지 확인합니다.
5. 게임 데이터를 다시 적용 또는 동기화해 새 항목과 수정값이 반영되는지 확인합니다.
6. 편집기를 정상 종료합니다.

각 확인은 실제 동작이 성공한 경우에만 `Y`로 기록합니다. 창을 열 수 없거나 기능을 수행할 수 없으면 `N`으로 기록해 실패 또는 미검증 상태를 남깁니다. 자동 모드와 수동 확인은 각각 별도 결과로 유지합니다.

## 자동 기록과 미검증 제한

UTF-8 JSON 보고서에는 실행 파일 경로, 프로젝트 외부 임시 작업 경로, fixture 위치, 각 검사 결과가 담깁니다. `--self-test`와 GUI 자동 시험 로그·결과 JSON·창 캡처·종료 코드도 같은 시험 폴더에 보존됩니다. 자동 GUI 결과는 모든 시나리오가 실제 메시지 루프에서 완료된 경우에만 통과합니다.

`--self-test`는 내부 데이터 작업만 검사합니다. 자동 GUI 시험은 실제 폼 컨트롤 이벤트를 실행하지만 게임 데이터 재적용을 확인하지 않습니다. 게임 데이터 재적용은 수동 게이트에서 확인해야 하며, 사람이 확인하지 않은 항목은 미검증으로 남겨야 합니다. 수동 질문에 `Y`로 답하기 전에는 전체 수동 인수 게이트를 통과 처리하지 않습니다.
