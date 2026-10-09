$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$root = Split-Path -Parent $PSScriptRoot
$recorderPath = Join-Path $root 'tools\capture_manual_input_audit.gd'
$runnerPath = Join-Path $root 'tools\run_manual_input_acceptance.ps1'
$gatePath = Join-Path $root 'docs\review\manual_input_acceptance_gate.md'
$recorder = [IO.File]::ReadAllText($recorderPath, [Text.Encoding]::UTF8)
$runner = [IO.File]::ReadAllText($runnerPath, [Text.Encoding]::UTF8)
$gate = [IO.File]::ReadAllText($gatePath, [Text.Encoding]::UTF8)

foreach ($control in @('Num%d','KEY_W','KEY_A','KEY_S','KEY_D','KEY_SPACE','KEY_SHIFT','KEY_J','KEY_ESCAPE','MOUSE_BUTTON_LEFT')) {
    if ($recorder -notmatch [regex]::Escape($control)) { throw "Recorder does not cover required control marker: $control" }
}
foreach ($marker in @('timestamp_utc','monotonic_usec','state_transition','window_focus','synthetic_suspicion_markers','physical_device_origin')) {
    if ($recorder -notmatch [regex]::Escape($marker)) { throw "Recorder does not record required audit field: $marker" }
}
if ($recorder -notmatch '1920, 1080' -or $runner -notmatch '1920x1080') { throw 'The manual path does not request the 1920x1080 main window.' }
if ($recorder -notmatch 'application/run/main_scene' -or $recorder -match 'Input\.parse_input_event') { throw 'Recorder must observe the configured main scene and must not synthesize input.' }
if ($runner -notmatch 'BLOCKED_UNVERIFIED' -or $runner -notmatch 'Console\]::IsInputRedirected') { throw 'Unattended runs must remain blocked and unverified.' }
if ($runner -notmatch 'physical_origin_proven_by_log = \$false' -or $gate -notmatch '증명하지') { throw 'The manual gate must explicitly reject physical-origin claims based only on logs.' }
foreach ($control in @('Num1','Num9','Space','MouseLeft','Esc')) {
    if ($runner -notmatch [regex]::Escape($control)) { throw "Manual review checklist is missing $control." }
}

Write-Output 'manual_input_acceptance_contract_smoke: all checks passed'
