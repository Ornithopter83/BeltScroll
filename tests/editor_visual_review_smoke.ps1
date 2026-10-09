param(
    [string]$EditorPath,
    [int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($EditorPath)) { $EditorPath = Join-Path $root 'dist\BeltScrollEditor.exe' }
$EditorPath = (Resolve-Path -LiteralPath $EditorPath).Path
$allowlistPath = Join-Path $root 'data\editor\overrides.json'
$allowlistHash = if (Test-Path -LiteralPath $allowlistPath) { (Get-FileHash -LiteralPath $allowlistPath -Algorithm SHA256).Hash } else { $null }
$work = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollVisualReview_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$process = Start-Process -FilePath $EditorPath -ArgumentList @('--animation-gui-acceptance', $work) -WorkingDirectory $work -PassThru
if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { try { $process.Kill() } catch { }; throw "Visual review GUI timed out. Artifacts: $work" }
$reportPath = Join-Path $work 'animation-gui-acceptance.json'
if (-not (Test-Path -LiteralPath $reportPath)) { throw "Visual review report missing (exit=$($process.ExitCode)). Artifacts: $work" }
$report = Get-Content -Encoding UTF8 -Raw -LiteralPath $reportPath | ConvertFrom-Json
if ($process.ExitCode -ne 0 -or -not $report.passed) { throw "Visual review GUI failed. Artifacts: $work`n$($report.error)" }
foreach ($event in @('50ms inbetween playback', '3x artwork side-by-side and overlay', 'anchor pointer event')) {
    if ($report.guiControlEvents -notcontains $event) { throw "Visual review event not verified: $event. Artifacts: $work" }
}
$capturePath = Join-Path $work 'animation-gui.png'
if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf) -or (Get-Item -LiteralPath $capturePath).Length -lt 4096) { throw "Rebuilt WinForms capture is missing or empty. Artifacts: $work" }
if ($report.approvalDecisionCreated -or $report.gameAllowlistChanged -or $report.approvalState -ne 'review') { throw "Automated visual review created an approval decision or changed allowlist. Artifacts: $work" }
$afterHash = if (Test-Path -LiteralPath $allowlistPath) { (Get-FileHash -LiteralPath $allowlistPath -Algorithm SHA256).Hash } else { $null }
if ($allowlistHash -ne $afterHash) { throw "Visual review GUI changed the game allowlist. Artifacts: $work" }
Write-Host "Visual review GUI smoke passed. Capture: $capturePath"
