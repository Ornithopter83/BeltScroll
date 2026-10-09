# 추가 smoke 검사 accounting gate

이 gate는 smoke suite가 추가 검사 14건을 빠짐없이 한 번씩 기록했는지, 각 검사에서 전달한 실제 process exit code와 suite 최종 요약이 서로 맞는지 확인한다. 기존 배치 호출 인터페이스인 `Sequence`, `Name`, `ExecutionType`, `ProcessExit`은 유지한다.

## Ledger 규약

- Production ledger는 아래 고정 순서의 14개 고유 이름을 각각 한 번 기록해야 한다.
  1. `attack2_candidate_motion_review_smoke`
  2. `player_attack3_startup_review_smoke`
  3. `player_animation_state_matrix_smoke`
  4. `player_attack1_startup_safe_smoke`
  5. `player_attack3_startup_safe_smoke`
  6. `player_run_stride_safe_smoke`
  7. `player_run_cycle_review_smoke`
  8. `m5_art_review_board_smoke`
  9. `player_run_stride_v2_safe_smoke`
  10. `player_run_v3_antiphase_smoke`
  11. `player_jump_rise_safe_smoke`
  12. `player_skill1_rush_safe_smoke`
  13. `editor_executable_parse_smoke`
  14. `animation_candidate_coverage_smoke`
- 행 형식은 `Sequence;Name;ExecutionType;ProcessExit`이며 sequence는 1부터 14까지 연속이어야 한다.
- 실행 유형은 headless 12건, PowerShell 2건이다. PowerShell 행은 마지막 두 검사에만 허용한다.
- 각 추가 검사는 `RUN_EXIT`의 실제 종료 코드를 전달한다. 종료 코드가 0이 아닌 행이 있으면 최종 suite process exit은 1이어야 한다.
- 검증기는 ledger 행 수와 배치의 `ReportedCount`를 비교하고 최종 suite exit도 함께 검증한다. 누락, 중복, 잘못된 순서, 잘못된 열, UTF-8 손상, 기록 오류는 통과하지 않는다.

## PowerShell 5.1 기록과 진단

Recorder와 validator는 .NET UTF-8 API를 사용한다. ledger는 UTF-8로 추가 기록하며, validator와 recorder는 잘못된 UTF-8 입력을 허용하지 않는다. Recorder는 기존 ledger를 먼저 검사하므로 중복 이름이나 끊긴 sequence 뒤에 행을 추가하지 않는다. 기록 오류는 0이 아닌 종료와 `[smoke] additional_check_record_failed` 진단으로 반환된다. 실패한 suite의 기존 smoke 로그와 ledger는 보존한다.

## Fixtures와 Window 검사

cmd.exe accounting fixture는 정상 종료 0, 일반 실패 7, timeout 124, PowerShell 실패 9를 확인한다. 최종 요약의 추가 검사 수와 suite 종료 코드는 fixture transcript의 실제 행 수 및 suite summary와 대조한다. 별도 negative fixtures는 ledger 누락, 중복, sequence gap, 손상 행, invalid UTF-8, 기록 실패가 거부되는지 확인한다. fixture 실패 시 transcript 경로를 오류 출력에 남긴다.

Window 기반 시각 검사는 headless 추가 검사로 분류하지 않는다. 캡처 명령 성공은 캡처 작업의 기술적 성공만 뜻하며 원화/시각 승인은 `visual_approval=not_granted`로 별도 유지한다. 사람의 승인 전에는 캡처 완료를 시각 리뷰 승인으로 보고하지 않는다.
