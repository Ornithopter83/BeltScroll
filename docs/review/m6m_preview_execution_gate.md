# M6M 보폭 프리뷰 실행 진단 게이트

## 목적과 판정 원칙

M6L QA에서 보고된 보폭 프리뷰의 120초 타임아웃을 HIGH의 단일 748.9ms 성공 기록만으로 무효화하지 않는다. HIGH 실행은 별도 성공 표본이며, QA 타임아웃의 원본 프로세스 로그·종료 코드·import 상태가 이 작업공간에 남아 있지 않으면 원인은 미해결이다. 현재 HIGH 기록은 코드 검증 스모크와 Window 캡처를 언급하지만 import와 스모크 실행 시간 분리, 제한시간 종료, 프로세스 정리, 동일 조건 재실행 판정을 제공하지 않는다.

`tools/run_m6m_preview_bounded.ps1`은 Godot 리소스 import 단계를 먼저 분리해 실행하고, 성공한 뒤 실제 후보 로딩 스모크를 headless와 Window 모드에서 각각 2회 이상 실행한다. 매 프로세스에 제한시간, stdout/stderr 로그 경로, 경과시간, 종료 코드, PID, 종료 뒤 생존 여부를 기록한다. timeout은 프로세스 트리를 종료한 뒤 확인한다. cold import timeout은 새 프로세스로 한 번 재시도한다. validation timeout은 설정된 반복 횟수만큼 새 프로세스로 반복한다.

판정 기준:

- 두 validation 반복이 모두 exit 0이면 해당 모드의 bounded 자동 스모크는 PASS다. 기존 QA 120초 타임아웃이 설명됐다는 뜻은 아니다.
- validation에서 timeout이 2회 이상 나면 해당 모드는 `BLOCKED_REPRODUCIBLE_TIMEOUT`이다.
- timeout이 한 번이면 재현되지 않은 실패도 성공 처리하지 않고 `BLOCKED_INTERMITTENT_TIMEOUT`으로 둔다. 부하와 import 상태를 함께 수집해 재실행한다.
- import 재시도까지 성공하지 않으면 validation을 실행하지 않고 `BLOCKED_IMPORT`로 둔다. import 비용과 스모크 시간을 합산하지 않는다.
- nonzero exit는 `BLOCKED_VALIDATION_FAILURE`다. 로그의 첫 실패 원인을 해결한 뒤 다시 실행한다.
- 모든 새 반복이 통과해도 QA에서 보고된 원본 로그 또는 재현 원인이 확보되지 않았다면 최종 수동/QA 상태는 BLOCKED로 남긴다.

## 확인 범위

`tests/m6l_walk_cycle_preview_smoke.gd`는 현재 파일시스템의 실제 후보 PNG를 Godot `Image`와 `Texture2D`로 읽고, opposite stride를 독립 후보 프레임으로 확인한다. 런타임 후보 배열에서 최소 6개의 이미지 텍스처가 생성되는지 확인하며, 재생이 cadence 뒤 한 프레임 진행하는지, Space 일시정지/재개, 좌우 수동 프레임 이동을 확인한다. 기존 run 후보의 `same_run_lead` phase 중복 마커와 화면 FAIL 요약 데이터가 만들어지는지도 확인한다. `--headless` 실행은 draw 호출이 가능한 자동 스모크이지 화면의 사람이 보는 시각 검토 증거는 아니다. Window 실행도 자동화 입력과 스모크 확인이며, 실제 물리 키 입력이나 사람의 보행 품질 승인은 아니다.

후보 프레임 순서는 검토용이다. 기존 run v1~v5는 반복 phase로 FAIL이고, 반대 stride 및 passing 후보는 한 장씩의 독립·미승인 프레임이다. 지지발 고정, 좌우 접지 교대, 반대 팔 흔들림, 골반 높이, 좌우 이동의 사람 시각 승인을 대신하지 않는다.

## 실행 방법

Windows PowerShell 5.1에서:

```powershell
.\tools\run_m6m_preview_bounded.ps1 -Mode Both -GodotPath 'C:\Project\Godot\godot.exe' -Repeats 2
```

기본 제한시간은 import 300초, headless 검증 45초/회, Window 검증 60초/회다. 각 제한시간은 매 실행에 개별 적용된다. 로그와 `run-summary.json`은 UTF-8로 `%TEMP%\BeltScroll_M6M_<timestamp>`에 남는다. 제한시간과 로그 폴더를 바꾸려면 `-ImportTimeoutSeconds`, `-HeadlessTimeoutSeconds`, `-WindowTimeoutSeconds`, `-OutputDirectory`를 지정한다. 최초 import가 이미 끝난 프로젝트에서도 import 단계는 별도 측정된다. warm 상태의 빠른 import 시간을 최초 cold import 비용으로 해석하지 않는다.

## 실행 결과 기록

아래 표에는 이번 환경의 실제 실행 결과를 기록한다. import와 validation은 서로 다른 프로세스다. 각 validation을 2회 이상 실행하고, 결과와 함께 stdout/stderr 로그 경로 및 `run-summary.json`을 남긴다. 이 워크스페이스에는 실행 전부터 `.godot` 캐시가 있어 이번 3.767초 import는 진정한 최초 cold-cache import라고 단정하지 않는다. QA 원본 실행의 machine load, cold/warm cache 상태, Godot 경로/버전, 프로세스 종료 상태를 확보하지 못하면 원인 규명은 미완료다.

| 날짜/환경 | Godot | 모드 | import (초/exit/timeout) | 검증 반복 (초/exit/timeout) | 프로세스 정리 | 판정/로그 |
|---|---|---|---|---|---|---|
| 2026-10-10, PowerShell 5.1, 기존 `.godot` 캐시 존재 | 4.7.2 stable mono | headless | 3.767s / 0 / no timeout (`initial_import`; 별도 프로세스) | 1.887s / 0 / no timeout; 1.927s / 0 / no timeout (각 45s 제한) | 전 3개 PID 종료 후 생존 확인 false | PASS 자동 스모크; 로그 폴더 `%TEMP%\BeltScroll_M6M_20261010_140958_222`; stderr에 root certificate store 읽기와 `%APPDATA%\Godot\editor_settings-4.7.tres` 저장 실패 경고 |
| 2026-10-10, 같은 세션/캐시 | 4.7.2 stable mono | Window | 같은 별도 import 프로세스 결과를 사용 | 2.326s / 0 / no timeout; 2.401s / 0 / no timeout (각 60s 제한) | 전 2개 PID 종료 후 생존 확인 false | PASS 자동 Window 스모크; stdout/stderr 및 `run-summary.json`은 위 폴더 |

위 반복에서 실제 후보 PNG가 Texture2D로 로드됐고, Space 일시정지/재개, 0.18초 cadence 뒤 프레임 진행, 정지 중 Right/Left 프레임 이동, run 후보 phase 중복에 대한 런타임 FAIL 요약이 통과했다. 후보 처리 표본은 첫 headless 실행에서 747.0ms였다. 이는 HIGH의 748.9ms와 일치하는 수준의 단일 처리 지표지만, QA 120초 타임아웃 재현 또는 반증으로 취급하지 않는다.

이번 import/스모크 종료 코드와 프로세스 정리는 성공했지만 환경 경고는 남았다. 별도 첫 진단 시도(14:08대)에서는 import 스캔 중 `scenes/review/m6m_walk_sequence_lab.tscn:1` 파싱 오류와 사용자 Godot 설정 저장 오류가 함께 나타났고, 후속 실행에서는 해당 parse error가 사라져 import가 exit 0으로 끝났다. 원래 M6L QA의 프로세스 로그가 없으므로 이 일시적 import 스캔 상태가 과거 120초 timeout과 관련 있는지는 확인할 수 없다. 현재 반복 검증에서 120초 timeout은 재현되지 않았으나, QA 당시 환경과 조건이 달랐는지 알 수 없어 원인은 **미해결**이다.

## 최종 상태

**BLOCKED_UNVERIFIED** — 이번 import 및 headless/Window 반복 스모크는 모두 제한시간 안에 exit 0으로 끝나고 프로세스도 정리됐다. HIGH의 748.9ms 및 이번 747.0ms 후보 처리 성공은 유효한 성공 표본이지만 M6L QA의 120초 타임아웃을 반증하지 않는다. 원본 QA 로그/종료 코드와 당시 cache·machine load를 확보하지 못했고 import 환경 경고도 있어 과거 타임아웃 원인은 미해결이다. 사람 시각 검토도 별도 대기다.
