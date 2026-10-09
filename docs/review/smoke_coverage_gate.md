# 전체 스모크 회귀 목록 게이트

## 실행 정책

`origin/main`의 기존 59개 스모크 호출 순서를 유지하고 새 회귀 검사 다섯 개를 마지막에 추가합니다. 전체 등록 검사는 64개이며, 추가 검사 집계는 앞서 추가된 3개와 이번 5개를 합쳐 8개입니다. 모든 Godot 검사는 `tools/run_smoke_bounded.ps1`를 통하며 프로세스 종료 코드와 로그를 확인합니다. headless 검사는 `--headless --script res://tests/<이름>.gd`, 창 검사는 화면 렌더러를 사용하는 `--script`로 구동합니다.

| 검사 | 실행 유형 | 제한 시간 | 성공 표식 |
| --- | --- | ---: | --- |
| `player_animation_bank_smoke` | Godot headless SceneTree | 120초 | `player_animation_bank_smoke: all checks passed` |
| `raider_attack_pose_window_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `raider_attack_pose_window_smoke: all checks passed` |
| `player_attack2_inbetween_safe_smoke` | Godot headless SceneTree | 120초 | `player_attack2_inbetween_safe_smoke: all checks passed; visual approval pending` |
| `player_attack2_contact_v5_smoke` | Godot headless SceneTree | 180초 | `player_attack2_contact_v5_smoke: all mechanical checks passed; visual approval remains human review` |
| `player_attack2_contact_v6_smoke` | Godot headless SceneTree | 180초 | `player_attack2_contact_v6_smoke: mechanical checks passed; no image approval is implied` |
| `combat_vfx_visual_smoke` | Godot headless SceneTree | 120초 | `combat_vfx_visual_smoke: all checks passed` |
| `attack2_candidate_motion_review_smoke` | Godot headless SceneTree 기계 검사 | 180초 | `attack2_candidate_motion_review_smoke: all checks passed; visual review remains pending` |
| `player_attack3_startup_review_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `player_attack3_startup_review_smoke: all checks passed` |
| `player_animation_state_matrix_smoke` | Godot headless SceneTree 상태 검사 | 120초 | `player_animation_state_matrix_smoke: state coverage and capture evidence present; no art completeness claim` |
| `player_attack1_startup_safe_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `player_attack1_startup_safe_smoke: mechanical checks passed; human visual approval is pending` |
| `player_attack3_startup_safe_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `player_attack3_startup_safe_smoke: mechanical checks passed; human visual approval remains pending` |
| `player_run_stride_safe_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `player_run_stride_safe_smoke: mechanical checks passed; human visual approval remains required` |
| `player_run_cycle_review_smoke` | Godot headless SceneTree 증거 검사 | 120초 | `player_run_cycle_review_smoke: isolated v1/v2 gate and Window evidence are present` |
| `m5_art_review_board_smoke` | Godot headless SceneTree 원화 보드 검사 | 120초 | `m5_art_review_board_smoke: all checks passed; human art approval remains independent` |

Raider 공격 리그 검사는 공격 windup/contact/recovery 포즈, hitbox 타이밍 및 발 anchor를 노드 상태로 검사하므로 창 렌더러를 시작하지 않습니다. 기존 `:run_smoke` 검사는 headless 120초, Raider spacing 부하 검사는 300초입니다. 기존 창 검사는 240초 제한을 사용합니다.

## 누락·중복·실패 판정

`tests/smoke_suite_coverage_smoke.ps1`는 기존 59개 순서가 보존되고 다섯 추가 검사가 마지막에 한 번씩 등록됐는지, 항목 수·중복·각 `.gd` 파일 존재 여부를 확인합니다. 실행 유형, 각 검사 제한 시간, 성공 표식, 종료 코드 검사, 타임아웃 기록, 개별 실패 로그 보존도 확인합니다. 실행 요약에는 `additional_checks=8`, 추가 검사의 `execution_type=headless`, 검사별 `process_exit` 및 스위트 종료 코드가 기록됩니다. 이 검사 자체도 PowerShell 프로세스로 45초 제한 실행되며 고정 성공 표식을 검사합니다.

`tests/editor_executable_parse_smoke.ps1`는 Windows PowerShell에서 `editor_executable_smoke.ps1`를 UTF-8로 읽어 파싱하고 수동 Y/N 확인 경로 및 리다이렉트 입력 차단을 확인합니다. 전체 스위트는 이 검사도 45초 제한으로 실행합니다. editor 실행 파일 인수 검사에서 표준 입력이 리다이렉트되면 수동 확인을 진행하지 않고 각 항목과 JSON 보고서에 `blocked` 상태를 남기며 대화형 콘솔에서 다시 실행하라고 안내합니다.

`tests/animation_live_review_suite_smoke.ps1`는 실제 캡처 도구가 일반 회귀 실행에 들어오지 않고, 각각 한 번씩 명시 실행 경로에만 있는지 확인합니다. 기본 회귀 스위트는 기존 캡처 증거를 읽기만 합니다. headless 상태 행렬 검사와 통합 원화 보드 검사는 기계적 증거만 확인하며, 원화 보드 검사 통과는 시각 승인이나 원화 완성도를 주장하지 않습니다.

실제 Godot Window에서 캡처를 재생성하려면 별도로 실행합니다.

```cmd
tools\smoke_suite.cmd --rebuild-live-review-captures
```

이 경로는 attack2 timed motion strip과 플레이어 상태 행렬을 비-headless Window 렌더러로 다시 캡처하고, attack3 startup 비교판은 생성 도구로 다시 만듭니다. 각 프로세스 종료 코드와 출력 성공 표식을 확인합니다. 캡처 재생성 성공은 기계적 실행 성공이며 시각 검수 또는 승인 완료가 아닙니다. 실제 이미지는 사람이 확인해야 합니다.

`tests/smoke_runner_probe.cmd`는 로그에 `SCRIPT ERROR`, 파서 오류, 런타임 오류 또는 허용되지 않은 Godot `ERROR:`가 있거나 프로세스 종료 코드가 0이 아니거나 최종 성공 표식이 다르면 실패시킵니다. 표식만 출력하고 비정상 종료한 검사는 통과할 수 없습니다. 타임아웃과 runner 오류도 비정상 종료로 판정합니다.

각 실패 시점의 `%TEMP%\beltscroll_smoke_failure_<검사>_<난수>.log` 파일에 실제 프로세스 로그, 종료 코드, 실행 시간과 timeout 정보가 보존됩니다. 실패 검사가 여럿이면 각각 다른 로그를 남깁니다.

## 전체 회귀 실행

프로젝트 루트에서 실행합니다.

```cmd
tools\smoke_suite.cmd
```

전체 스모크 성공 표식은 `[smoke] All independent smoke checks passed.`이며, 실행 요약에서 `process_exit=0`을 확인합니다. 실행 시점의 실제 결과는 작업 보고서에 기록합니다.
