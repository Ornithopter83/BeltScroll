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
"%GODOT_EXE%" --path "%PROJECT_DIR%" %*
exit /b %errorlevel%

:smoke
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --quit-after 3
exit /b %errorlevel%