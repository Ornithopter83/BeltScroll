$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$root = Split-Path -Parent $PSScriptRoot
$recorderPath = Join-Path $root 'tools\capture_manual_input_audit.gd'
$runnerPath = Join-Path $root 'tools\run_manual_input_acceptance.ps1'
$gatePath = Join-Path $root 'docs\review\manual_input_acceptance_gate.md'
$checklistPath = Join-Path $root 'docs\review\m5d_human_acceptance_checklist.md'
$recorder = [IO.File]::ReadAllText($recorderPath, [Text.Encoding]::UTF8)
$runner = [IO.File]::ReadAllText($runnerPath, [Text.Encoding]::UTF8)
$gate = [IO.File]::ReadAllText($gatePath, [Text.Encoding]::UTF8)
$checklist = [IO.File]::ReadAllText($checklistPath, [Text.Encoding]::UTF8)

foreach ($control in @('Num%d','KEY_W','KEY_A','KEY_S','KEY_D','KEY_SPACE','KEY_SHIFT','KEY_J','KEY_ESCAPE','MOUSE_BUTTON_LEFT')) {
    if ($recorder -notmatch [regex]::Escape($control)) { throw "Recorder does not cover required control marker: $control" }
}
foreach ($marker in @('timestamp_utc','monotonic_usec','state_transition','window_focus','synthetic_suspicion_markers','physical_device_origin')) {
    if ($recorder -notmatch [regex]::Escape($marker)) { throw "Recorder does not record required audit field: $marker" }
}
if ($recorder -notmatch '1920, 1080' -or $runner -notmatch '1920x1080' -or $runner -notmatch "'--fullscreen'") { throw 'The manual path must request a 1920x1080 fullscreen main window.' }
if ($recorder -notmatch 'application/run/main_scene' -or $recorder -match 'Input\.parse_input_event') { throw 'Recorder must observe the configured main scene and must not synthesize input.' }
if ($runner -notmatch 'BLOCKED_UNVERIFIED' -or $runner -notmatch 'Console\]::IsInputRedirected' -or $runner -notmatch 'exit 2') { throw 'Unattended runs must remain blocked and unverified with exit 2.' }
if ($runner -notmatch 'physical_origin_proven_by_log = \$false' -or $gate -notmatch '증명하지') { throw 'The manual gate must explicitly reject physical-origin claims based only on logs.' }
if ($runner -match "'--windowed'") { throw 'The manual acceptance launch must not force windowed mode.' }
foreach ($control in @('Num1','Num9','Space','MouseLeft','Esc','ThreeTimesScale','PlayerHealthBar','RaiderHealthBars','Skill4AndSkill5Differ','EditorManualCreate','EditorManualModify','EditorManualSave','EditorManualReopen','EditorGameReapply','ArtIdentity','RunStride','TurnRotation','FramePops')) {
    if ($runner -notmatch [regex]::Escape($control)) { throw "Manual review checklist is missing $control." }
}
foreach ($marker in @('1920×1080','전체화면','3배','Num1~9','양측 체력바','Num4','Num5','재적용','identity','보폭','프레임 팝','input-events.jsonl','manual-review.json','BLOCKED_UNVERIFIED')) {
    if ($gate -notmatch [regex]::Escape($marker) -and $checklist -notmatch [regex]::Escape($marker)) { throw "Human acceptance documentation is missing: $marker" }
}
if ($runner -notmatch 'MANUAL_REVIEW_RECORDED' -or $runner -notmatch 'automated_input_or_gui_self_test_substitutes_for_human_acceptance = \$false') { throw 'Automated input or GUI self-tests must never substitute for a direct human review.' }

# Exercise the same pure verdict function used after manual review. Probe mode does not launch Godot,
# write evidence, or claim that a person actually performed any check.
$inputNames = @('Num1','Num2','Num3','Num4','Num5','Num6','Num7','Num8','Num9','W','A','S','D','Space','Shift','J','MouseLeft','Esc')
$reviewNames = @('Display1920x1080','Fullscreen','ThreeTimesScale','WindowFocusLossReturn','PlayerHealthBar','RaiderHealthBars','Skill4AndSkill5Differ','EditorManualCreate','EditorManualModify','EditorManualSave','EditorManualReopen','EditorGameReapply','ArtIdentity','RunStride','TurnRotation','FramePops')
$allNames = $inputNames + $reviewNames
$allPass = [ordered]@{}
foreach ($name in $allNames) { $allPass[$name] = 'pass' }

function Invoke-DecisionProbe {
    param([System.Collections.IDictionary]$Case)
    $json = ConvertTo-Json -InputObject $Case.Controls -Compress
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runnerPath,'-DecisionProbe','-ProbeProcessExitCode',[string]$Case.ProcessExitCode,'-ProbeControlsBase64',$base64)
    if ($Case.FocusConfirmed) { $args += '-ProbeFocusConfirmed' }
    if ($Case.PhysicalConfirmed) { $args += '-ProbePhysicalConfirmed' }
    if ($Case.Unattended) { $args += '-ProbeUnattended' }
    $raw = @(& (Join-Path $PSHOME 'powershell.exe') @args 2>&1)
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "Decision probe failed: $($raw -join "`n")" }
    return (($raw -join "`n") | ConvertFrom-Json)
}

$cases = @(
    @{ Name='all direct checks pass'; Controls=$allPass; ProcessExitCode=0; FocusConfirmed=$true; PhysicalConfirmed=$true; Unattended=$false; Expected='MANUAL_REVIEW_RECORDED'; ExpectedExit=0 },
    @{ Name='unattended even with pass-shaped values'; Controls=$allPass; ProcessExitCode=0; FocusConfirmed=$true; PhysicalConfirmed=$true; Unattended=$true; Expected='BLOCKED_UNVERIFIED'; ExpectedExit=2 },
    @{ Name='game process failed'; Controls=$allPass; ProcessExitCode=1; FocusConfirmed=$true; PhysicalConfirmed=$true; Unattended=$false; Expected='BLOCKED_UNVERIFIED'; ExpectedExit=2 },
    @{ Name='focus confirmation missing'; Controls=$allPass; ProcessExitCode=0; FocusConfirmed=$false; PhysicalConfirmed=$true; Unattended=$false; Expected='BLOCKED_UNVERIFIED'; ExpectedExit=2 },
    @{ Name='physical device confirmation missing'; Controls=$allPass; ProcessExitCode=0; FocusConfirmed=$true; PhysicalConfirmed=$false; Unattended=$false; Expected='BLOCKED_UNVERIFIED'; ExpectedExit=2 }
)
$missingControl = [ordered]@{}
foreach ($name in $allNames) { $missingControl[$name] = 'pass' }
$missingControl['Num5'] = 'not_tested'
$cases += @{ Name='required control unverified'; Controls=$missingControl; ProcessExitCode=0; FocusConfirmed=$true; PhysicalConfirmed=$true; Unattended=$false; Expected='BLOCKED_UNVERIFIED'; ExpectedExit=2 }
$failedEditor = [ordered]@{}
foreach ($name in $allNames) { $failedEditor[$name] = 'pass' }
$failedEditor['EditorGameReapply'] = 'fail'
$cases += @{ Name='editor game reapply failed'; Controls=$failedEditor; ProcessExitCode=0; FocusConfirmed=$true; PhysicalConfirmed=$true; Unattended=$false; Expected='BLOCKED_UNVERIFIED'; ExpectedExit=2 }

foreach ($case in $cases) {
    $result = Invoke-DecisionProbe -Case $case
    if ($result.status -ne $case.Expected -or $result.exit_code -ne $case.ExpectedExit) {
        throw "Verdict regression '$($case.Name)': expected $($case.Expected)/$($case.ExpectedExit), got $($result.status)/$($result.exit_code)."
    }
}

# An unattended invocation must return 2 without launching the supplied executable, and must not
# truncate an event log or review file that already belongs to the user.
$preservationRoot = Join-Path ([IO.Path]::GetTempPath()) ('manual-input-preservation-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($preservationRoot)
$existingLog = Join-Path $preservationRoot 'input-events.jsonl'
$existingReview = Join-Path $preservationRoot 'manual-review.json'
[IO.File]::WriteAllText($existingLog, 'preserve-input-log', $utf8)
[IO.File]::WriteAllText($existingReview, 'preserve-review', $utf8)
try {
    $rawBlocked = @(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $runnerPath -ProjectRoot $root -GodotPath (Join-Path $PSHOME 'powershell.exe') -OutputDirectory $preservationRoot 2>&1)
    $blockedExit = $LASTEXITCODE
    if ($blockedExit -ne 2) { throw "Unattended runner must exit 2; got $blockedExit. Output: $($rawBlocked -join "`n")" }
    if ([IO.File]::ReadAllText($existingLog, [Text.Encoding]::UTF8) -ne 'preserve-input-log' -or [IO.File]::ReadAllText($existingReview, [Text.Encoding]::UTF8) -ne 'preserve-review') {
        throw 'Unattended runner modified existing user input/review evidence.'
    }
    $newReviews = @(Get-ChildItem -LiteralPath $preservationRoot -Filter manual-review.json -Recurse -File | Where-Object { $_.FullName -ne $existingReview })
    if ($newReviews.Count -ne 1) { throw "Expected one isolated blocked review; found $($newReviews.Count)." }
    $blockedReport = Get-Content -Encoding UTF8 -Raw -LiteralPath $newReviews[0].FullName | ConvertFrom-Json
    if ($blockedReport.status -ne 'BLOCKED_UNVERIFIED' -or $blockedReport.physical_origin_proven_by_log -ne $false) { throw 'Unattended review did not remain BLOCKED_UNVERIFIED.' }
} finally {
    Remove-Item -LiteralPath $preservationRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'manual_input_acceptance_contract_smoke: all checks passed'
