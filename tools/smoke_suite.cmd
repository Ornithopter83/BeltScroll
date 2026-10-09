@echo off
setlocal EnableExtensions
for %%I in ("%~dp0..") do set "PROJECT_DIR=%%~fI"

if /I "%~1"=="--rebuild-live-review-captures" goto live_review_captures
if not "%~1"=="" (
    echo Usage: tools\smoke_suite.cmd [--rebuild-live-review-captures]
    exit /b 2
)

if not defined GODOT_EXE (
    where godot.exe >nul 2>nul
    if not errorlevel 1 set "GODOT_EXE=godot.exe"
)
if not defined GODOT_EXE (
    where godot >nul 2>nul
    if not errorlevel 1 set "GODOT_EXE=godot"
)
if not defined GODOT_EXE (
    echo Godot was not found. Set GODOT_EXE to its executable path or add godot.exe to PATH.
    exit /b 1
)

set "BOUNDED_RUNNER=%PROJECT_DIR%\tools\run_smoke_bounded.ps1"
set "PROBE=%PROJECT_DIR%\tests\smoke_runner_probe.cmd"
set "RUN_LOG=%TEMP%\beltscroll_smoke_%RANDOM%_%RANDOM%.log"
set "SUITE_FAILED=0"
set "FAILED_LOG="
set "ADDITIONAL_CHECKS=0"
set "ADDITIONAL_TYPES=headless"
for /f %%T in ('powershell.exe -NoLogo -NoProfile -NonInteractive -Command "[Diagnostics.Stopwatch]::GetTimestamp()"') do set "SUITE_START_TICKS=%%T"

echo [smoke] Importing project resources
set "SMOKE_ARGS=--headless --editor --path ""%PROJECT_DIR%"" --import --quit"
call :run_bounded 300
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" ""
if errorlevel 1 (
    set "SUITE_FAILED=1"
    call :save_failure import
)

call :run_smoke movement_smoke
call :run_smoke ground_dust_smoke
call :run_smoke player_combat_smoke
call :run_smoke player_skill_smoke
call :run_smoke player_pose_blender_smoke
call :run_smoke training_dummy_smoke
call :run_smoke forest_raider_smoke
call :run_smoke raider_spacing_stress_smoke
call :run_smoke raider_visual_animator_smoke
call :run_smoke combat_hud_smoke
call :run_smoke stage_tools_smoke
call :run_smoke stage_integration_smoke
call :run_smoke game_session_smoke
call :run_smoke game_session_navigation_smoke
call :run_smoke game_pause_smoke
call :run_smoke gamepad_input_smoke
call :run_smoke player_keypose_pipeline_smoke
call :run_smoke player_keypose_relayout_smoke
call :run_smoke player_reference_review_smoke
call :run_smoke art_review_smoke
call :run_smoke player_art_normalize_smoke
call :run_smoke player_reference_compare_smoke
call :run_smoke player_v5_art_smoke
call :run_smoke forest_raider_matte_smoke
call :run_smoke player_v5_final_matte_smoke
call :run_smoke forest_raider_final_matte_smoke
call :run_smoke player_v6_art_smoke
call :run_smoke player_v7_ink_smoke
call :run_smoke player_attack1_final_matte_smoke
call :run_smoke player_attack1_edge_v2_smoke
call :run_smoke player_attack1_contour_smoke
call :run_smoke player_attack2_art_smoke
call :run_smoke player_attack2_v2_art_smoke
call :run_smoke player_attack2_v4_art_smoke
call :run_smoke player_attack3_art_smoke
call :run_smoke player_attack3_contour_smoke
call :run_smoke combat_audio_smoke
call :run_window_smoke combat_art_overlap_smoke
call :run_window_smoke combat_art_candidate_capture_smoke
call :run_window_smoke forest_raider_art_integration_smoke
call :run_window_smoke player_art_integration_smoke
call :run_window_smoke player_visual_animator_smoke
call :run_window_smoke player_attack_pose_integration_smoke
call :run_window_smoke camera_boundary_window_smoke
call :run_window_smoke display_num_input_window_smoke
call :run_window_smoke gameplay_window_render_smoke
call :run_window_smoke combat_live_session_window_smoke
call :run_window_smoke raider_healthbar_window_smoke
call :run_gameplay_endings_window_smoke

rem New mechanical regression coverage is appended to preserve the established order.
call :run_smoke player_animation_bank_smoke
call :run_smoke player_attack2_inbetween_safe_smoke
call :run_smoke player_attack2_contact_v5_smoke
call :run_smoke player_attack2_contact_v6_smoke
call :run_smoke combat_vfx_visual_smoke
call :run_smoke raider_attack_pose_window_smoke
call :run_smoke player_attack2_contact_v6_safe_smoke
call :run_smoke attack2_candidate_motion_review_smoke
call :record_additional_check attack2_candidate_motion_review_smoke
call :run_smoke player_attack3_startup_review_smoke
call :record_additional_check player_attack3_startup_review_smoke
call :run_smoke player_animation_state_matrix_smoke
call :record_additional_check player_animation_state_matrix_smoke

call :run_suite_coverage
if errorlevel 1 (
    set "SUITE_FAILED=1"
    call :save_failure suite_coverage
)
call :run_animation_live_review_coverage
if errorlevel 1 (
    set "SUITE_FAILED=1"
    call :save_failure animation_live_review_coverage
)

call :probe_fixtures
if errorlevel 1 (
    set "SUITE_FAILED=1"
    call :save_failure fixtures
)
echo [smoke] Verifying bounded process runner fixtures
set "SMOKE_ARGS=-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""%PROJECT_DIR%\tests\smoke_bounded_runner_smoke.ps1"""
set "BOUNDED_EXECUTABLE=powershell.exe"
call :run_bounded 45
set "BOUNDED_EXECUTABLE="
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "smoke_bounded_runner_smoke: all checks passed"
if errorlevel 1 (
    set "SUITE_FAILED=1"
    echo [smoke] FAILED: bounded runner fixtures
    type "%RUN_LOG%"
    call :save_failure bounded_runner
)
if "%SUITE_FAILED%"=="1" goto failed
del "%RUN_LOG%" >nul 2>nul
call :report_suite 0
echo [smoke] All independent smoke checks passed.
exit /b 0

:run_smoke
set "SMOKE_NAME=%~1"
echo [smoke] Running %SMOKE_NAME%
set "SMOKE_ARGS=--headless --path ""%PROJECT_DIR%"" --script ""res://tests/%SMOKE_NAME%.gd"""
set "SMOKE_TIMEOUT=120"
if /I "%SMOKE_NAME%"=="raider_spacing_stress_smoke" set "SMOKE_TIMEOUT=300"
if /I "%SMOKE_NAME%"=="player_animation_bank_smoke" set "SMOKE_TIMEOUT=120"
if /I "%SMOKE_NAME%"=="player_attack2_inbetween_safe_smoke" set "SMOKE_TIMEOUT=120"
if /I "%SMOKE_NAME%"=="player_attack2_contact_v5_smoke" set "SMOKE_TIMEOUT=180"
if /I "%SMOKE_NAME%"=="player_attack2_contact_v6_smoke" set "SMOKE_TIMEOUT=180"
if /I "%SMOKE_NAME%"=="combat_vfx_visual_smoke" set "SMOKE_TIMEOUT=120"
if /I "%SMOKE_NAME%"=="raider_attack_pose_window_smoke" set "SMOKE_TIMEOUT=120"
if /I "%SMOKE_NAME%"=="player_attack2_contact_v6_safe_smoke" set "SMOKE_TIMEOUT=180"
if /I "%SMOKE_NAME%"=="attack2_candidate_motion_review_smoke" set "SMOKE_TIMEOUT=180"
if /I "%SMOKE_NAME%"=="player_attack3_startup_review_smoke" set "SMOKE_TIMEOUT=120"
if /I "%SMOKE_NAME%"=="player_animation_state_matrix_smoke" set "SMOKE_TIMEOUT=120"
echo [smoke] Type=headless timeout=%SMOKE_TIMEOUT%s log=%RUN_LOG%
call :run_bounded %SMOKE_TIMEOUT%
set "ALLOW_MODE="
set "SUCCESS_MARKER=%SMOKE_NAME%: all checks passed"
if /I "%SMOKE_NAME%"=="player_art_normalize_smoke" set "ALLOW_MODE=png-negative"
if /I "%SMOKE_NAME%"=="forest_raider_matte_smoke" set "ALLOW_MODE=png-negative"
if /I "%SMOKE_NAME%"=="player_v5_art_smoke" (
    set "ALLOW_MODE=png-negative"
    set "SUCCESS_MARKER=player_v5_art_smoke: all checks passed; visual approval pending."
)
if /I "%SMOKE_NAME%"=="player_v5_final_matte_smoke" (
    set "SUCCESS_MARKER=player_v5_final_matte_smoke: all checks passed; visual approval pending."
)
if /I "%SMOKE_NAME%"=="forest_raider_final_matte_smoke" set "ALLOW_MODE=png-negative"
if /I "%SMOKE_NAME%"=="player_attack1_final_matte_smoke" set "ALLOW_MODE=png-negative"
if /I "%SMOKE_NAME%"=="player_v6_art_smoke" set "SUCCESS_MARKER=player_v6_art_smoke: all checks passed; visual approval pending."
if /I "%SMOKE_NAME%"=="player_v7_ink_smoke" set "SUCCESS_MARKER=player_v7_ink_smoke: all checks passed; visual approval pending."
if /I "%SMOKE_NAME%"=="player_keypose_relayout_smoke" set "SUCCESS_MARKER=player_keypose_relayout_smoke: all checks passed; source-edge clipping remains a visual review issue"
if /I "%SMOKE_NAME%"=="player_attack2_inbetween_safe_smoke" set "SUCCESS_MARKER=player_attack2_inbetween_safe_smoke: all checks passed; visual approval pending"
if /I "%SMOKE_NAME%"=="player_attack2_contact_v5_smoke" set "SUCCESS_MARKER=player_attack2_contact_v5_smoke: all mechanical checks passed; visual approval remains human review"
if /I "%SMOKE_NAME%"=="player_attack2_contact_v6_smoke" set "SUCCESS_MARKER=player_attack2_contact_v6_smoke: mechanical checks passed; no image approval is implied"
if /I "%SMOKE_NAME%"=="player_attack2_contact_v6_safe_smoke" set "SUCCESS_MARKER=player_attack2_contact_v6_safe_smoke: mechanical checks passed; visual approval remains pending"
if /I "%SMOKE_NAME%"=="attack2_candidate_motion_review_smoke" set "SUCCESS_MARKER=attack2_candidate_motion_review_smoke: all checks passed; visual motion judgment remains pending"
if /I "%SMOKE_NAME%"=="player_animation_state_matrix_smoke" set "SUCCESS_MARKER=player_animation_state_matrix_smoke: state coverage and capture evidence present; no art completeness claim"
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "%SUCCESS_MARKER%" "%ALLOW_MODE%"
if errorlevel 1 (
    set "SUITE_FAILED=1"
    echo [smoke] FAILED: %SMOKE_NAME%
    type "%RUN_LOG%"
    call :save_failure %SMOKE_NAME%
)
exit /b 0

:run_window_smoke
set "SMOKE_NAME=%~1"
echo [smoke] Running %SMOKE_NAME% with the window renderer
set "SMOKE_ARGS=--path ""%PROJECT_DIR%"" --script ""res://tests/%SMOKE_NAME%.gd"""
echo [smoke] Type=window timeout=240s log=%RUN_LOG%
call :run_bounded 240
if /I "%SMOKE_NAME%"=="camera_boundary_window_smoke" call :report_camera_run
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "%SMOKE_NAME%: all checks passed"
if errorlevel 1 (
    set "SUITE_FAILED=1"
    echo [smoke] FAILED: %SMOKE_NAME%
    type "%RUN_LOG%"
    call :save_failure %SMOKE_NAME%
)
exit /b 0

:run_gameplay_endings_window_smoke
set "SMOKE_OLD_APPDATA=%APPDATA%"
set "APPDATA=%TEMP%\BeltScrollGodotSmokeUserData"
if not exist "%APPDATA%" mkdir "%APPDATA%" >nul 2>nul
call :run_window_smoke gameplay_endings_window_smoke
if defined SMOKE_OLD_APPDATA (set "APPDATA=%SMOKE_OLD_APPDATA%") else set "APPDATA="
set "SMOKE_OLD_APPDATA="
exit /b 0

:run_bounded
set "RUN_EXECUTABLE=%GODOT_EXE%"
if defined BOUNDED_EXECUTABLE set "RUN_EXECUTABLE=%BOUNDED_EXECUTABLE%"
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%BOUNDED_RUNNER%" -Executable "%RUN_EXECUTABLE%" -TimeoutSeconds %~1 -LogPath "%RUN_LOG%"
set "RUN_EXIT=%ERRORLEVEL%"
exit /b 0

:save_failure
set "FAILED_LOG_CURRENT=%TEMP%\beltscroll_smoke_failure_%~1_%RANDOM%.log"
if not defined FAILED_LOG set "FAILED_LOG=%FAILED_LOG_CURRENT%"
copy /y "%RUN_LOG%" "%FAILED_LOG_CURRENT%" >nul
echo [smoke] Diagnostic log for %~1: %FAILED_LOG_CURRENT%
exit /b 0

:run_suite_coverage
echo [smoke] Verifying suite inventory, order, routing, timeouts, and success markers
set "SMOKE_ARGS=-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""%PROJECT_DIR%\tests\smoke_suite_coverage_smoke.ps1"""
set "BOUNDED_EXECUTABLE=powershell.exe"
call :run_bounded 45
set "BOUNDED_EXECUTABLE="
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "smoke_suite_coverage_smoke: all checks passed"
if errorlevel 1 (
    echo [smoke] FAILED: suite coverage inventory
    type "%RUN_LOG%"
    exit /b 1
)
exit /b 0

:run_animation_live_review_coverage
echo [smoke] Verifying explicit live review capture path and visual approval boundary
set "SMOKE_ARGS=-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""%PROJECT_DIR%\tests\animation_live_review_suite_smoke.ps1"""
set "BOUNDED_EXECUTABLE=powershell.exe"
call :run_bounded 45
set "BOUNDED_EXECUTABLE="
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "animation_live_review_suite_smoke: all checks passed"
if errorlevel 1 (
    echo [smoke] FAILED: live review capture policy
    type "%RUN_LOG%"
    exit /b 1
)
exit /b 0

:record_additional_check
set /a ADDITIONAL_CHECKS+=1
echo [smoke] additional_check=%~1 execution_type=headless process_exit=%RUN_EXIT%
exit /b 0

:live_review_captures
:rebuild_live_review_captures
if not defined GODOT_EXE (
    where godot.exe >nul 2>nul
    if not errorlevel 1 set "GODOT_EXE=godot.exe"
)
if not defined GODOT_EXE (
    where godot >nul 2>nul
    if not errorlevel 1 set "GODOT_EXE=godot"
)
if not defined GODOT_EXE (
    echo Godot was not found. Set GODOT_EXE to its executable path or add godot.exe to PATH.
    exit /b 1
)
set "BOUNDED_RUNNER=%PROJECT_DIR%\tools\run_smoke_bounded.ps1"
set "PROBE=%PROJECT_DIR%\tests\smoke_runner_probe.cmd"
set "RUN_LOG=%TEMP%\beltscroll_live_review_%RANDOM%_%RANDOM%.log"
set "SUITE_START_TICKS=0"
set "SUITE_FAILED=0"
set "FAILED_LOG="
echo [smoke] Rebuilding live review captures; execution_type=window_capture,visual_approval=not_granted
set "SMOKE_ARGS=--path ""%PROJECT_DIR%"" --script ""res://tools/capture_attack2_candidate_motion_review.gd"""
call :run_bounded 240
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" ""
if not errorlevel 1 findstr /L /C:"attack2-candidate-motion-review: saved isolated timed preview to res://assets/art/review/player_attack2_candidate_motion_strip.png" "%RUN_LOG%" >nul
if errorlevel 1 (
    set "SUITE_FAILED=1"
    call :save_failure capture_attack2_candidate_motion_review
) else echo [smoke] capture=attack2_candidate_motion_review execution_type=window process_exit=%RUN_EXIT%
set "SMOKE_ARGS=--path ""%PROJECT_DIR%"" --script ""res://tools/capture_player_animation_state_matrix.gd"""
call :run_bounded 180
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" ""
if not errorlevel 1 findstr /L /C:"player-state-matrix: saved 1920x1080 real Window Viewport captures to" "%RUN_LOG%" >nul
if errorlevel 1 (
    set "SUITE_FAILED=1"
    call :save_failure capture_player_animation_state_matrix
) else echo [smoke] capture=player_animation_state_matrix execution_type=window process_exit=%RUN_EXIT%
set "SMOKE_ARGS=--headless --path ""%PROJECT_DIR%"" --script ""res://tools/build_player_attack3_startup_review.gd"""
call :run_bounded 120
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" ""
if not errorlevel 1 findstr /L /C:"comparison generated: res://assets/art/review/player_attack3_startup_comparison.png (" "%RUN_LOG%" >nul
if errorlevel 1 (
    set "SUITE_FAILED=1"
    call :save_failure build_player_attack3_startup_review
) else echo [smoke] capture=player_attack3_startup_review execution_type=headless_generated_board process_exit=%RUN_EXIT%
if "%SUITE_FAILED%"=="1" goto failed_capture
del "%RUN_LOG%" >nul 2>nul
echo [smoke] Live review capture artifacts regenerated; human visual approval remains pending.
exit /b 0

:failed_capture
echo [smoke] Live review capture regeneration failed. Diagnostic log: %FAILED_LOG%
if defined FAILED_LOG type "%FAILED_LOG%"
exit /b 1

:probe_fixtures
echo [smoke] Verifying runner against PASS fixtures
set "SMOKE_ARGS=--headless --path ""%PROJECT_DIR%"" --script res://tests/fixtures/false_pass.gd"
call :run_bounded 120
if not "%RUN_EXIT%"=="0" (
    echo [smoke] ERROR: intentional false PASS fixture did not complete normally. Exit code: %RUN_EXIT%
    exit /b 1
)
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "false_pass: all checks passed"
if not errorlevel 1 (
    echo [smoke] ERROR: runner accepted the intentional false PASS fixture.
    exit /b 1
)

set "SMOKE_ARGS=--headless --path ""%PROJECT_DIR%"" --script res://tests/fixtures/pass_probe.gd"
call :run_bounded 120
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "pass_probe: all checks passed"
if errorlevel 1 (
    echo [smoke] ERROR: runner rejected the normal PASS fixture.
    exit /b 1
)

call "%PROBE%" "%RUN_LOG%" "missing" "pass_probe: all checks passed"
if not errorlevel 1 (
    echo [smoke] ERROR: runner accepted a missing process exit code.
    exit /b 1
)

set "SMOKE_ARGS=--headless --path ""%PROJECT_DIR%"" --script res://tests/fixtures/nonzero_pass.gd"
call :run_bounded 120
if not "%RUN_EXIT%"=="1" (
    echo [smoke] ERROR: nonzero PASS fixture returned unexpected exit code %RUN_EXIT%.
    exit /b 1
)
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "nonzero_pass: all checks passed"
if not errorlevel 1 (
    echo [smoke] ERROR: runner accepted a PASS marker with a nonzero exit code.
    exit /b 1
)
exit /b 0

:failed
call :report_suite 1
echo [smoke] FAILED. Diagnostic log: %FAILED_LOG%
if defined FAILED_LOG type "%FAILED_LOG%"
exit /b 1

:report_camera_run
for /f "tokens=2 delims=:" %%E in ('findstr /C:"Actual process exit code:" "%RUN_LOG%"') do echo [smoke] camera_boundary_window_smoke process_exit=%%E
for /f "tokens=2 delims=:" %%E in ('findstr /C:"Elapsed seconds:" "%RUN_LOG%"') do echo [smoke] camera_boundary_window_smoke elapsed_seconds=%%E
for /f "tokens=2 delims=:" %%E in ('findstr /C:"Reported check count:" "%RUN_LOG%"') do echo [smoke] camera_boundary_window_smoke checks=%%E
exit /b 0

:report_suite
for /f %%T in ('powershell.exe -NoLogo -NoProfile -NonInteractive -Command "$elapsed=([Diagnostics.Stopwatch]::GetTimestamp() - [long]$env:SUITE_START_TICKS) / [Diagnostics.Stopwatch]::Frequency; [Math]::Round($elapsed,3)"') do set "SUITE_ELAPSED=%%T"
echo [smoke] suite process_exit=%~1 elapsed_seconds=%SUITE_ELAPSED%
echo [smoke] additional_checks=%ADDITIONAL_CHECKS% execution_types=%ADDITIONAL_TYPES% additional_checks_process_exit=%~1
exit /b 0
