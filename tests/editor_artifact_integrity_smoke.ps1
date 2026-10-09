param(
    [string]$PackagePath,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PackagePath)) {
    $releaseDir = Join-Path $root 'dist\editor-release'
    $localPackages = @(Get-ChildItem -LiteralPath $releaseDir -Filter 'BeltScrollEditor-*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($localPackages.Count -eq 0) { throw "No local BeltScrollEditor package ZIP found in $releaseDir; pass -PackagePath." }
    $PackagePath = $localPackages[0].FullName
}
$verificationDir = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollEditorLocalIntegrity_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($verificationDir)
$verifier = Join-Path $root 'tools\verify_actions_editor_artifact.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifier -PackagePath $PackagePath -OutputDirectory $verificationDir -TimeoutSeconds $TimeoutSeconds
$exitCode = $LASTEXITCODE
$reportPath = Join-Path $verificationDir 'verification-report.json'
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "Verifier did not write its report: $reportPath" }
$report = Get-Content -Encoding UTF8 -Raw -LiteralPath $reportPath | ConvertFrom-Json
if ($report.source -ne 'local-package') { throw 'Local integrity smoke was mislabeled as remote artifact verification.' }
if ($report.status -ne 'PASS' -or $exitCode -ne 0) { throw "Local package integrity smoke failed (status=$($report.status), exit=$exitCode)." }
Write-Output "editor_artifact_integrity_smoke: passed; report=$reportPath"
exit 0
