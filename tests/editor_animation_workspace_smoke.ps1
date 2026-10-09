param(
    [string]$EditorPath,
    [int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot
$allowlistPath = Join-Path $root 'data\editor\overrides.json'
$allowlistHashBefore = if (Test-Path -LiteralPath $allowlistPath) { (Get-FileHash -LiteralPath $allowlistPath -Algorithm SHA256).Hash } else { $null }
& (Join-Path $root 'editor\build_editor.ps1') -SelfTest
if ($LASTEXITCODE -ne 0) { throw "Editor build/self-test failed: $LASTEXITCODE" }
if ([string]::IsNullOrWhiteSpace($EditorPath)) { $EditorPath = Join-Path $root 'dist\BeltScrollEditor.exe' }
$EditorPath = (Resolve-Path -LiteralPath $EditorPath).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollAnimationGui_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$process = Start-Process -FilePath $EditorPath -ArgumentList @('--animation-gui-acceptance', $work) -WorkingDirectory $work -PassThru
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    try { $process.Kill() } catch { }
    throw "Animation workspace GUI acceptance timed out. Artifacts: $work"
}
$reportPath = Join-Path $work 'animation-gui-acceptance.json'
if (-not (Test-Path -LiteralPath $reportPath)) { throw "GUI acceptance report missing (exit=$($process.ExitCode)). Artifacts: $work" }
$report = Get-Content -Encoding UTF8 -Raw -LiteralPath $reportPath | ConvertFrom-Json
if ($process.ExitCode -ne 0 -or -not $report.passed) { throw "Animation workspace GUI acceptance failed. Artifacts: $work`n$($report.error)" }
if (-not (Test-Path -LiteralPath (Join-Path $work 'animation-gui.png')) -or -not (Test-Path -LiteralPath $report.exportedPath)) { throw "GUI capture or exported JSON is missing. Artifacts: $work" }
if ($report.clipCount -ne 11 -or $report.frameCount -ne 4) { throw "GUI acceptance did not preserve all eleven clips and four attack phases. Artifacts: $work" }
$expectedEvents = @(
    'clip creation and selection',
    'all schema v1 clip IDs',
    'clip-specific phase validation',
    'multiple run stride frames',
    'new frame review default',
    'skill startup/contact/recovery selection',
    'four attack phase selection',
    'duration edit',
    'anchor pointer event',
    'frame reorder with duration identity',
    '35ms/50ms/105ms/200ms cumulative playback',
    '576px default review size',
    'side-by-side full-body and foot anchor',
    'overlay full-body and foot anchor',
    'independent 200% pixel zoom',
    'drag pan at pixel zoom',
    'source dimensions and display multiplier',
    'actual frame duration',
    'multi-clip JSON export',
    'JSON reload'
)
foreach ($event in $expectedEvents) {
    if ($report.guiControlEvents -notcontains $event) { throw "GUI event verification missing '$event'. Artifacts: $work" }
}
foreach ($capture in @('comparison-side-by-side.png', 'comparison-overlay.png', 'comparison-zoom.png', 'comparison-pan.png')) {
    $capturePath = Join-Path $work $capture
    if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf) -or (Get-Item -LiteralPath $capturePath).Length -lt 2048) {
        throw "GUI comparison capture missing or empty '$capture'. Artifacts: $work"
    }
}
if ($report.approvalDecisionCreated -or $report.gameAllowlistChanged -or $report.approvalState -ne 'review') { throw "Automated GUI acceptance must not create an approval decision or change the game allowlist. Artifacts: $work" }
$exportedDocument = Get-Content -Encoding UTF8 -Raw -LiteralPath $report.exportedPath | ConvertFrom-Json
$expectedClips = @('idle','attack1','attack2','attack3','run','turn','jump_rise','jump_fall','hit','skill1','skill2')
$actualClips = @($exportedDocument.clips | ForEach-Object { $_.id } | Sort-Object)
if (($actualClips -join ',') -ne (($expectedClips | Sort-Object) -join ',')) { throw "JSON export lost or added a schema v1 clip ID: $($actualClips -join ','). Artifacts: $work" }
$runFrames = @($exportedDocument.clips | Where-Object { $_.id -eq 'run' } | ForEach-Object { $_.frames })
if ($runFrames.Count -ne 3 -or @($runFrames | Where-Object { $_.phase -ne 'stride' -or $_.approval_state -ne 'review' }).Count -ne 0) { throw "Run stride frames did not roundtrip in review state. Artifacts: $work" }
$frameStates = @($exportedDocument.clips | Where-Object { $_.id -eq 'attack1' } | ForEach-Object { $_.frames } | ForEach-Object { $_.approval_state } | Select-Object -Unique)
if ($frameStates.Count -ne 1 -or $frameStates[0] -ne 'review') { throw "GUI smoke changed a frame approval state. Artifacts: $work" }
$allowlistHashAfter = if (Test-Path -LiteralPath $allowlistPath) { (Get-FileHash -LiteralPath $allowlistPath -Algorithm SHA256).Hash } else { $null }
if ($allowlistHashBefore -ne $allowlistHashAfter) { throw "GUI smoke changed the game allowlist file. Artifacts: $work" }
Write-Host "Animation workspace GUI smoke passed. Artifacts: $work"
