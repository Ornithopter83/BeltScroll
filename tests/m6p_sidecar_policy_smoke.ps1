[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$auditor = Join-Path $repositoryRoot 'tools/audit_m6p_generated_sidecars.ps1'
$gitIgnorePath = Join-Path $repositoryRoot '.gitignore'
$ignoreText = [IO.File]::ReadAllText($gitIgnorePath, [Text.Encoding]::UTF8)
if ($ignoreText -match '(?m)^\s*\*\.uid\s*$' -or $ignoreText -match '(?m)^\s*\*\.import\s*$') {
    throw '.gitignore must not blanket-ignore Godot .uid or .import sidecars.'
}
if (-not (Test-Path -LiteralPath $auditor -PathType Leaf)) {
    throw "Audit script not found: $auditor"
}

$output = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $auditor -RepositoryRoot $repositoryRoot 2>&1
$exitCode = $LASTEXITCODE
$text = [string]::Join([Environment]::NewLine, [string[]]$output)
if ($exitCode -ne 0) { throw "Audit failed (exit $exitCode):`n$text" }
foreach ($required in @('read-only', 'PATH | TYPE | GIT', 'godot-uid-review', 'Policy: audit only')) {
    if ($text -notmatch [regex]::Escape($required)) {
        throw "Audit output missing expected policy/classification '$required'.`n$text"
    }
}
if ($text -match '(?m)^\s*[*].uid\s*$') { throw 'Audit output suggests blanket UID ignore.' }

Write-Output 'PASS: M6P sidecar audit classifies paths without mutating the repository.'
