# 전체 스모크 회귀 목록 게이트

## 실행 정책

`tools/smoke_suite.cmd`의 기존 import 및 스모크 호출 순서를 유지하고, 신규 회귀 검사를 기존 목록 뒤에 추가합니다. 모든 검사는 `tools/run_smoke_bounded.ps1`를 통하며 프로세스 종료 코드와 로그를 확인합니다. headless 검사는 `--headless --script res://tests/<이름>.gd`, 창 검사는 화면 렌더러를 사용하는 `--script`로 구동합니다.

| 검사 | 실행 유형 | 제한 시간 | 성공 표식 |
| --- | --- | ---: | --- |
| `player_animation_bank_smoke` | Godot headless SceneTree | 120초 | `player_animation_bank_smoke: all checks passed` |
| `raider_attack_pose_window_smoke` | Godot headless SceneTree 기계 검사 | 120초 | `raider_attack_pose_window_smoke: all checks passed` |
| `player_attack2_inbetween_safe_smoke` | Godot headless SceneTree | 120초 | `player_attack2_inbetween_safe_smoke: all checks passed; visual approval pending` |
| `player_attack2_contact_v5_smoke` | Godot headless SceneTree | 180초 | `player_attack2_contact_v5_smoke: all mechanical checks passed; visual approval remains human review` |
| `player_attack2_contact_v6_smoke` | Godot headless SceneTree | 180초 | `player_attack2_contact_v6_smoke: mechanical checks passed; no image approval is implied` |
| `combat_vfx_visual_smoke` | Godot headless SceneTree | 120초 | `combat_vfx_visual_smoke: all checks passed` |

Raider 공격 리그 검사는 공격 windup/contact/recovery 포즈, hitbox 타이밍 및 발 anchor를 노드 상태로 검사하므로 창 렌더러를 시작하지 않습니다. 기존 `:run_smoke` 검사는 headless 120초, Raider spacing 부하 검사는 300초입니다. 기존 창 검사는 240초 제한을 사용합니다.

## 누락·중복·실패 판정

`tests/smoke_suite_coverage_smoke.ps1`는 전체 등록 순서를 고정 목록과 비교하고 항목 수, 상대 순서, 중복, 각 `.gd` 검사 파일의 존재를 확인합니다. 여섯 신규 회귀 항목은 각각 정확히 한 번 headless 경로에 있어야 합니다. 또한 headless/창 실행 인자, bounded runner 호출, 성공 표식 검사, 종료 코드 검사, 타임아웃 기록과 개별 실패 로그 보존을 확인합니다. 이 검사 자체도 PowerShell 프로세스로 45초 제한 실행되며 고정 성공 표식을 검사합니다.

`tests/smoke_runner_probe.cmd`는 로그에 `SCRIPT ERROR`, 파서 오류, 런타임 오류 또는 허용되지 않은 Godot `ERROR:`가 있거나 프로세스 종료 코드가 0이 아니거나 최종 성공 표식이 다르면 실패시킵니다. 표식만 출력하고 비정상 종료한 검사는 통과할 수 없습니다. 타임아웃과 runner 오류도 비정상 종료로 판정합니다.

각 실패 시점의 `%TEMP%\beltscroll_smoke_failure_<검사>_<난수>.log` 파일에 실제 프로세스 로그, 종료 코드, 실행 시간과 timeout 정보가 보존됩니다. 실패 검사가 여럿이면 각각 다른 로그를 남깁니다.

## 전체 회귀 실행

프로젝트 루트에서 실행합니다.

```cmd
tools\smoke_suite.cmd
```

전체 스모크 성공 표식은 `[smoke] All independent smoke checks passed.`이며, 실행 요약에서 `process_exit=0`을 확인합니다. 실행 시점의 실제 결과는 작업 보고서에 기록합니다.
