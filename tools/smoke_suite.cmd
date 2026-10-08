@echo off
setlocal EnableExtensions
for %%I in ("%~dp0..") do set "PROJECT_DIR=%%~fI"

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

set "PROBE=%PROJECT_DIR%\tests\smoke_runner_probe.cmd"
set "RUN_LOG=%TEMP%\beltscroll_smoke_%RANDOM%_%RANDOM%.log"
set "SUITE_FAILED=0"
set "FAILED_LOG="

echo [smoke] Importing project resources
"%GODOT_EXE%" --headless --editor --path "%PROJECT_DIR%" --import >"%RUN_LOG%" 2>&1
set "RUN_EXIT=%ERRORLEVEL%"
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" ""
if errorlevel 1 (
    set "SUITE_FAILED=1"
    call :save_failure import
)

call :run_smoke movement_smoke
call :run_smoke player_combat_smoke
call :run_smoke training_dummy_smoke
call :run_smoke forest_raider_smoke
call :run_smoke combat_hud_smoke
call :run_smoke stage_tools_smoke
call :run_smoke stage_integration_smoke
call :run_smoke game_session_smoke
call :run_smoke player_reference_review_smoke
call :run_smoke art_review_smoke
call :run_smoke player_art_normalize_smoke
call :run_smoke player_reference_compare_smoke

call :probe_fixtures
if errorlevel 1 set "SUITE_FAILED=1"
if "%SUITE_FAILED%"=="1" goto failed
del "%RUN_LOG%" >nul 2>nul
echo [smoke] All independent smoke checks passed.
exit /b 0

:run_smoke
set "SMOKE_NAME=%~1"
echo [smoke] Running %SMOKE_NAME%
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script "res://tests/%SMOKE_NAME%.gd" >"%RUN_LOG%" 2>&1
set "RUN_EXIT=%ERRORLEVEL%"
if /I "%SMOKE_NAME%"=="player_art_normalize_smoke" (
    call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "%SMOKE_NAME%: all checks passed" "png-negative"
) else (
    call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "%SMOKE_NAME%: all checks passed"
)
if errorlevel 1 (
    set "SUITE_FAILED=1"
    echo [smoke] FAILED: %SMOKE_NAME%
    type "%RUN_LOG%"
    call :save_failure %SMOKE_NAME%
)
exit /b 0

:save_failure
if not defined FAILED_LOG set "FAILED_LOG=%TEMP%\beltscroll_smoke_failure_%~1_%RANDOM%.log"
copy /y "%RUN_LOG%" "%FAILED_LOG%" >nul
exit /b 0

:probe_fixtures
echo [smoke] Verifying runner against PASS fixtures
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/fixtures/false_pass.gd >"%RUN_LOG%" 2>&1
set "RUN_EXIT=%ERRORLEVEL%"
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "false_pass: all checks passed"
if not errorlevel 1 (
    echo [smoke] ERROR: runner accepted the intentional false PASS fixture.
    exit /b 1
)

"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/fixtures/pass_probe.gd >"%RUN_LOG%" 2>&1
set "RUN_EXIT=%ERRORLEVEL%"
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "pass_probe: all checks passed"
if errorlevel 1 (
    echo [smoke] ERROR: runner rejected the normal PASS fixture.
    exit /b 1
)

call "%PROBE%" "%RUN_LOG%" "" "pass_probe: all checks passed"
if not errorlevel 1 (
    echo [smoke] ERROR: runner accepted a missing process exit code.
    exit /b 1
)

"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/fixtures/nonzero_pass.gd >"%RUN_LOG%" 2>&1
set "RUN_EXIT=%ERRORLEVEL%"
call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "nonzero_pass: all checks passed"
if not errorlevel 1 (
    echo [smoke] ERROR: runner accepted a PASS marker with a nonzero exit code.
    exit /b 1
)
exit /b 0

:failed
echo [smoke] FAILED. Diagnostic log: %FAILED_LOG%
if defined FAILED_LOG type "%FAILED_LOG%"
exit /b 1
