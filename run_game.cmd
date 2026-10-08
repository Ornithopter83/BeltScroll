@echo off
setlocal
for %%I in ("%~dp0.") do set "PROJECT_DIR=%%~fI"

if not defined GODOT_EXE (
    where godot.exe >nul 2>nul
    if not errorlevel 1 set "GODOT_EXE=godot.exe"
)
if not defined GODOT_EXE (
    where godot >nul 2>nul
    if not errorlevel 1 set "GODOT_EXE=godot"
)
if not defined GODOT_EXE (
    echo Godot 4.7.2 was not found. Set GODOT_EXE to its executable path or add godot.exe to PATH.
    exit /b 1
)

if /I "%~1"=="smoke" goto smoke
if /I "%~1"=="--smoke" goto smoke
if /I "%~1"=="art-review-check" goto art_review_check
if /I "%~1"=="art-review" goto art_review
if /I "%~1"=="stage-normalize" goto stage_normalize
if /I "%~1"=="stage-review" goto sr
if /I "%~1"=="stage-review-check" goto src
"%GODOT_EXE%" --path "%PROJECT_DIR%" %*
exit /b %errorlevel%

:smoke
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/movement_smoke.gd
if errorlevel 1 exit /b %errorlevel%

"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/player_combat_smoke.gd
if errorlevel 1 exit /b %errorlevel%

"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/training_dummy_smoke.gd
if errorlevel 1 exit /b %errorlevel%

"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/forest_raider_smoke.gd
if errorlevel 1 exit /b %errorlevel%

"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/stage_tools_smoke.gd
exit /b %errorlevel%

:art_review_check
if "%~2"=="" goto art_review_check_default
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/art_review.gd -- --check "%~2"
exit /b %errorlevel%

:art_review_check_default
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/art_review.gd -- --check
exit /b %errorlevel%

:art_review
if "%~2"=="" goto art_review_default
"%GODOT_EXE%" --path "%PROJECT_DIR%" --script res://tests/art_review.gd -- "%~2"
exit /b %errorlevel%

:art_review_default
"%GODOT_EXE%" --path "%PROJECT_DIR%" --script res://tests/art_review.gd --
exit /b %errorlevel%

:stage_normalize
if "%~2"=="" (
    echo Usage: run_game.cmd stage-normalize ^<input.png^> ^<output.png^>
    exit /b 2
)
if "%~3"=="" (
    echo Usage: run_game.cmd stage-normalize ^<input.png^> ^<output.png^>
    exit /b 2
)
if not "%~4"=="" (
    echo Usage: run_game.cmd stage-normalize ^<input.png^> ^<output.png^>
    exit /b 2
)
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tools/normalize_stage_art.gd -- "%~2" "%~3"
exit /b %errorlevel%

:sr
if "%~2"=="" goto srd
"%GODOT_EXE%" --path "%PROJECT_DIR%" --script res://tests/stage_art_review.gd -- "%~2"
exit /b %errorlevel%

:srd
"%GODOT_EXE%" --path "%PROJECT_DIR%" --script res://tests/stage_art_review.gd --
exit /b %errorlevel%

:src
if "%~2"=="" goto srcd
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/stage_art_review.gd -- --check "%~2"
exit /b %errorlevel%

:srcd
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --script res://tests/stage_art_review.gd -- --check
exit /b %errorlevel%
