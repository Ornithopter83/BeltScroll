$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$verifierPath = Join-Path $PSScriptRoot '..\tools\verify_actions_editor_artifact.ps1'
$source = Get-Content -Encoding UTF8 -Raw -LiteralPath $verifierPath
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($verifierPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ("Remote artifact verifier has PowerShell parse errors: " + (($parseErrors | ForEach-Object { $_.Message }) -join '; ')) }

$checks = New-Object System.Collections.Generic.List[string]
function Assert-Contains([string]$Pattern, [string]$Message) {
    if ($script:source -notmatch $Pattern) { throw $Message }
    $script:checks.Add($Message)
}
function Assert-NotContains([string]$Pattern, [string]$Message) {
    if ($script:source -match $Pattern) { throw $Message }
    $script:checks.Add($Message)
}

Assert-NotContains '37921763731|BeltScrollEditor-win-x64-1(?=["''])' 'Verifier contains a stale hard-coded run or artifact default.'
Assert-Contains '\$ExpectedRunId\s*,\s*\[string\]\$ExpectedArtifactName' 'Expected run and artifact are not optional caller assertions.'
Assert-Contains 'repos/\$Repository/commits/main' 'Verifier does not query the repository main SHA.'
Assert-Contains 'actions/workflows/editor-package\.yml/runs\?branch=main&per_page=100' 'Verifier does not query editor package runs on main.'
Assert-Contains '\$_.head_sha\s+-eq\s+\$mainSha\s+-and\s+\$_.status\s+-eq\s+''completed''\s+-and\s+\$_.conclusion\s+-eq\s+''success''' 'Verifier does not bind a completed successful run to the current main SHA.'
Assert-Contains 'BeltScrollEditor-win-x64-\$runNumber' 'Verifier does not check artifact name against its run number.'
Assert-Contains 'actions/artifacts/\{1\}/zip' 'Verifier download endpoint does not include the artifact ID.'
Assert-Contains 'Invoke-GhDownload\s+\$Repository\s+\$artifactId' 'Verifier does not download the outer archive by the API artifact ID.'
Assert-Contains '\$outerArchiveSha\s+-cne\s+\$expectedOuterSha' 'Verifier does not reject an outer ZIP digest mismatch.'
Assert-Contains 'actions-artifact-outer\.zip|actions-artifact-outer-extracted' 'Verifier does not retain and extract the outer Actions ZIP separately.'
Assert-Contains 'Inner deployment ZIP identified' 'Verifier does not identify the inner deployment ZIP separately.'
Assert-Contains 'Extracted deployment EXE SHA-256' 'Verifier does not check the extracted executable checksum.'
Assert-Contains 'editor_release_package_smoke\.ps1' 'Verifier does not invoke the package self-test and GUI acceptance smoke.'
Assert-Contains 'Local deployment ZIP inspection only; no GitHub run or artifact claim is made' 'Local ZIP results are not explicitly separated from remote evidence.'
Assert-Contains '\$overall\s*=\s*''UNVERIFIED''' 'Remote access failures are not classified as UNVERIFIED.'

Write-Output ("PASS: editor remote artifact verifier contract ({0} checks)." -f $checks.Count)
foreach ($check in $checks) { Write-Output ("  - {0}" -f $check) }
