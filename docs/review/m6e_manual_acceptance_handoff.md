# M6E 실제 사람 수동 인수 실행·인계

## 목적과 증거 원칙

`tools/run_m6e_manual_acceptance.ps1`은 기존 수동 인수 게이트의 사람 검수 절차를 순서대로 안내하고 입력 로그, 플레이 관찰 로그, 사람이 지정한 증거 파일 경로와 SHA-256을 기록한다. Num1~9의 실제 반응, 1920×1080 전체화면·3배 표시, 타이틀부터 보스 조우·승리·재시작·패배까지의 플레이, 외부 편집기 GUI 생성·수정·저장·닫기·재열기·게임 재적용을 확인한다.

Godot 로그는 장치 출처를 증명하지 않는다. M6D 플레이 관찰기의 화면 프레임 캡처는 자동 캡처임을 그대로 표시하며 사람의 확인으로 바꾸지 않는다. 자동 입력, 입력 주입, self-test, GUI 자동 acceptance를 이 실행기는 실행하지 않는다. 체크는 검수자가 직접 수행한 뒤 `pass`로 답하고 실제 증거 파일을 지정한 경우에만 기록된다. 증거 파일이 없거나 검수자가 없으면 해당 체크는 미확인으로 남는다.

무인 또는 표준 입력 리디렉션 실행은 어떤 GUI도 실행하지 않고 `BLOCKED_UNVERIFIED`와 종료 코드 `2`를 기록한다. 기록에는 미확인 항목과 검수자가 이어서 할 행동이 포함된다. 이 상태는 실패나 승인 판정이 아니라 사람 검수가 이루어지지 않았다는 의미다.

## 실행

Windows PowerShell 5.1의 대화형 콘솔에서 프로젝트 루트 기준으로 실행한다. PowerShell 출력과 파이프 인코딩을 UTF-8로 설정하고 게이트를 읽는다.

```powershell
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
Get-Content -Encoding UTF8 .\docs\review\m6e_manual_acceptance_handoff.md
.\tools\run_m6e_manual_acceptance.ps1 -GodotPath 'C:\Path\To\Godot_v4.exe' -EditorPath '.\dist\BeltScrollEditor.exe'
```

Godot이 PATH의 `godot` 또는 `godot4`로 확인되면 `-GodotPath`를 생략할 수 있다. 출력 기본 경로는 시스템 임시 폴더의 새 `BeltScrollM6E_*` 디렉터리다. `-OutputDirectory`를 지정하면 그 디렉터리를 사용한다.

```powershell
.\tools\run_m6e_manual_acceptance.ps1 `
  -GodotPath 'C:\Path\To\Godot_v4.exe' `
  -EditorPath 'D:\Build\BeltScrollEditor.exe' `
  -OutputDirectory 'D:\Review\M6E'
```

## 검수 순서

1. 첫 번째 실제 게임 창에서 전체화면과 1920×1080, 게임 원화 기준 3배 표시를 눈으로 확인한다. 실제 키보드의 Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9를 차례로 눌렀다 놓으며 각 본편 반응을 확인한다. Num4와 Num5는 슬롯 표시와 실제 발동 차이를 확인한다. 완료 후 게임 창을 직접 닫는다.
2. 두 번째 실제 게임 창의 타이틀 화면에서 Enter로 시작한다. 검수자가 직접 플레이해 보스 조우와 보스전 승리를 확인한다. 승리 화면에서 R로 재시작해 새 시작 상태를 확인한 뒤, 다시 플레이하여 패배 화면까지 확인한다. 미관찰 상태에서 F10을 누르면 관찰이 끝나며 도달하지 않은 항목은 미확인으로 남는다.
3. 실행기가 여는 외부 편집기 GUI에서 항목을 생성하고 수정한다. 저장하고 편집기를 닫은 다음 다시 열어 값이 유지되는지 확인하고 게임에 재적용/동기화해 게임 반영을 확인한다. 각 단계를 직접 수행한다.
4. 실행기가 제시하는 각 체크에 검수자가 직접 관찰한 결과만 `pass`, `fail`, `not_tested`로 답한다. `pass`에는 실제 증거 파일 경로도 입력한다. 한 영상/연속 기록이 여러 체크를 포함하면 각 항목에 같은 파일 경로를 지정할 수 있다. 파일이 없거나 비어 있거나 마지막 수정 시각이 7일보다 오래되면 `pass` 응답도 미확인으로 저장된다.

물리 키를 NumLock 상태와 키보드 종류(숫자열/키패드)에 맞춰 확인하고 사용한 장치와 이상 동작은 증거 메모/영상에 남긴다. 입력 이벤트 로그만으로 장치의 물리성을 추정하지 않는다. 게임을 정상 종료하지 못했거나 관찰 프로세스의 종료 코드가 0이 아니면 완전한 수동 인수 기록으로 처리되지 않는다.

## 산출물과 판정

기본 출력 폴더에는 다음이 남는다.

- `input-events.jsonl`: 첫 번째 게임 세션에서 관찰된 입력과 창 포커스 이벤트. 실제 물리 장치 출처는 미확인으로 명시된다.
- `physical-playthrough.log`, `physical-playthrough-error.log`: 두 번째 세션의 실제 입력 관찰기 출력/오류. `PHYSICAL_INPUT_OBSERVATION`과 입력 주입 없음이 기록된다.
- `m6d_manual_acceptance.json`: M6D 계약에 맞춘 물리 키보드, 표시, 보스 플레이, 편집기 GUI 단계, 증거 해시 및 현재 HEAD 결속 보고서.
- `manual-review.json`: 동일한 인수 기록의 호환 사본.

`MANUAL_REVIEW_RECORDED`는 모든 필수 사람 체크가 PASS이고 증거 파일이 실제 존재하며 현재 HEAD와 프로세스 상태를 기록한 경우에만 반환된다. `FAIL`이 확인되면 `MANUAL_REVIEW_FAILED`/종료 코드 `1`, 사람이 없거나 항목·증거·프로세스 결과가 불완전하면 `BLOCKED_UNVERIFIED`/종료 코드 `2`다. 자동 캡처는 `evidenceHashes`의 사람 증거로 자동 추가되지 않는다. 사람 파일을 별도로 지정한 경우에만 그 파일의 해시가 기록된다.

검수자가 부재하거나 시간이 부족하면 보고서의 `nextActions`를 따라 미확인 항목을 실제로 검수하고 다시 실행한다. 별도 자동 플레이스루 보고서가 필요하면 기존 M6D 플레이스루/감사 절차를 별도로 수행한다. 이 실행기의 물리 관찰 결과를 자동 Window 보고서의 사람 승인으로 전용하지 않는다.
