@echo off
setlocal EnableExtensions
if "%~1"=="" goto usage
if "%~2"=="" goto usage
if not exist "%~1" (
    echo [smoke probe] Missing run log: %~1
    exit /b 1
)

set "PROBE_LOG=%~1"
set "PROBE_EXIT=%~2"
set "PROBE_MARKER=%~3"
set "PROBE_ALLOW=%~4"

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $log=$env:PROBE_LOG; $code=$env:PROBE_EXIT; $marker=$env:PROBE_MARKER; $allow=$env:PROBE_ALLOW; if ($code -notmatch '^-?\d+$') { Write-Output '[smoke probe] Missing or invalid process exit code.'; exit 1 }; $lines=[IO.File]::ReadAllLines($log,[Text.Encoding]::UTF8); $failure=$false; foreach($line in $lines) { if ($line -match '(?i)SCRIPT ERROR\s*:|Parse Error\s*:|Parser Error\s*:|\b(runtime error|invalid call|attempt to call)\b') { Write-Output ('[smoke probe] Godot script/runtime error: '+$line); $failure=$true; continue }; if ($line -match '(?i)\bERROR\s*:') { if ($line -match '(?i)(certificate|cert store|TLS|SSL|editor settings|editor_settings|editor layout|editor-layout|user://logs|failed to open log|cannot open log|could not create log|permission denied.*log)') { Write-Output ('[smoke probe] Environment warning: '+$line) } elseif ($allow -eq 'png-negative' -and $line -match '(?i)Condition .(!success|err|image\.is_null\(\)). is true\. Returning: (ERR_FILE_CORRUPT|Ref<Image>\(\)|ERR_PARSE_ERROR)') { Write-Output ('[smoke probe] Expected rejected-input diagnostic: '+$line) } else { Write-Output ('[smoke probe] Godot error: '+$line); $failure=$true } } }; if ($code -ne '0') { Write-Output ('[smoke probe] Process exited with code '+$code+'.'); $failure=$true }; if (-not [string]::IsNullOrEmpty($marker)) { $last=''; foreach($line in $lines) { $trimmed=$line.Trim(); if ($trimmed -eq '') { continue }; if ($trimmed -match '(?i)^WARNING\s*:') { continue }; if ($trimmed -match '(?i)(certificate|cert store|TLS|SSL|editor settings|editor_settings|editor layout|editor-layout|user://logs|failed to open log|cannot open log|could not create log|permission denied.*log)') { continue }; $last=$trimmed }; if ($last -cne $marker) { Write-Output ('[smoke probe] Final success marker mismatch. Expected: '+$marker+'; last output: '+$last); $failure=$true } }; if ($failure) { exit 1 }; Write-Output '[smoke probe] PASS'; exit 0"
exit /b %errorlevel%

:usage
echo Usage: smoke_runner_probe.cmd ^<log-file^> ^<exit-code^> [final-success-marker]
    exit /b 1
