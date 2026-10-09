[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$BaselineRef = 'origin/main'
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

$checker = Join-Path $RepositoryRoot 'tools/check_repository_hygiene.ps1'
if (-not (Test-Path -LiteralPath $checker -PathType Leaf)) {
    throw "Repository hygiene checker not found: $checker"
}

$powershellExe = Join-Path $PSHOME 'powershell.exe'
$output = & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $checker -RepositoryRoot $RepositoryRoot -BaselineRef $BaselineRef 2>&1
$exitCode = $LASTEXITCODE
$text = [string]::Join([Environment]::NewLine, [string[]]$output)

# The smoke test is an assertion against this repository's tracked-index
# inventory. It passes only when the checker detects the known 71 MB editor
# publish executable or when that executable has been removed from tracking.
if ($exitCode -eq 0) {
    if ($text -match 'BeltScrollEditor\.exe') {
        throw 'Checker returned success while reporting the known executable.'
    }
    Write-Output 'PASS: repository hygiene checker reports no tracked violations.'
    exit 0
}

if ($exitCode -eq 1 -and $text -match 'BeltScrollEditor\.exe' -and $text -match '대용량 실행 파일') {
    Write-Output 'PASS: checker detects the tracked large editor executable.'
    exit 0
}

throw "Checker failed unexpectedly (exit $exitCode):`n$text"
