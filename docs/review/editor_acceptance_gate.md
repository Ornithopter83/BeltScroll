# 독립 편집기 EXE 인수 게이트

## 목적과 판정

이 게이트는 빌드 산출물 `dist/BeltScrollEditor.exe`를 프로젝트 실행 환경과 분리해 확인합니다. 스크립트가 파일 존재, `--self-test`의 종료 코드, GUI 실행, 프로젝트 외부 작업 디렉터리 실행을 점검합니다. 잘못된 JSON 거부와 GUI 편집 흐름은 실제 창에서 작업자가 확인해 보고서에 기록합니다.

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

## GUI 확인 순서

스크립트가 제공하는 `malformed-editor-data.json`을 편집기에서 열거나 가져와 JSON 구문 오류를 거부하는지 확인합니다. 오류가 표시되고 기존 데이터가 적용되거나 손상되지 않아야 합니다. 이후 GUI에서 다음 과정을 실제로 수행하고 각 질문에 `Y` 또는 `N`으로 답합니다.

1. 새 게임 데이터 항목을 생성합니다.
2. 해당 항목을 복제하고 복제본의 필드를 수정합니다.
3. 복제본을 저장하고 닫습니다.
4. 파일/항목을 다시 열어 수정값과 원본·복제본 구분이 유지되는지 확인합니다.
5. 게임 데이터를 다시 적용 또는 동기화해 새 항목과 수정값이 반영되는지 확인합니다.
6. 편집기를 정상 종료합니다.

각 확인은 실제 동작이 성공한 경우에만 `Y`로 기록합니다. 창을 열 수 없거나 기능을 수행할 수 없으면 `N`으로 기록해 실패 또는 미검증 상태를 남깁니다. 비정상 JSON GUI 동작은 스크립트가 직접 주입하는 것이 아니라, 제공된 잘못된 JSON 파일을 대상으로 사람이 확인합니다.

## 자동 기록과 미검증 제한

UTF-8 JSON 보고서에는 실행 파일 경로, 프로젝트 외부 임시 작업 경로, 잘못된 JSON fixture 위치, 각 검사 결과가 담깁니다. `--self-test` 로그 파일도 같은 시험 폴더에 보존됩니다. 최종 출력이 `all acceptance checks passed`이고 보고서의 모든 `passed` 값이 `true`인 경우에만 이 인수 게이트가 통과한 것입니다.

`--self-test`가 내부 데이터 작업을 검사하더라도 GUI 확인을 대신하지 않습니다. 특히 실제 창 실행, malformed JSON 거부, 생성·복제·수정·저장·재열기와 게임 데이터 재적용 결과는 사람이 직접 확인해야 합니다. 이 스크립트는 자동화된 좌표 클릭이나 시각적 UI 판독을 하지 않으므로 작업자 확인 없이 배포 인수 통과로 처리할 수 없습니다.
