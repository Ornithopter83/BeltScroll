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

$targetPath = '.qa_logs/editor-publish-current/BeltScrollEditor.exe'
function Get-GitLines {
    param([string[]]$GitArguments)

    $result = & git -C $RepositoryRoot @GitArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArguments -join ' ') failed: $($result -join [Environment]::NewLine)"
    }
    return @($result | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

$indexedTarget = @(Get-GitLines -GitArguments @('ls-files', '--stage', '--', $targetPath))
$remoteTarget = @(Get-GitLines -GitArguments @(
    'ls-tree', '-r', '-l', '--full-tree', $BaselineRef, '--', $targetPath))
$isIndexed = $indexedTarget.Count -gt 0
$isRemoteTracked = $remoteTarget.Count -gt 0

$powershellExe = Join-Path $PSHOME 'powershell.exe'
$output = & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $checker -RepositoryRoot $RepositoryRoot -BaselineRef $BaselineRef 2>&1
$exitCode = $LASTEXITCODE
$text = [string]::Join([Environment]::NewLine, [string[]]$output)

# The checker must report the exact path for every source that still tracks it.
# A local file is not a violation when neither the index nor baseline tracks it.
$targetMention = $text.Contains($targetPath)
if ($isIndexed -and $text -notmatch '명시적 위생 차단: index에서 추적 중') {
    throw 'Checker did not report the explicit index tracking block.'
}
if ($isRemoteTracked -and $text -notmatch ([regex]::Escape("명시적 위생 차단: $BaselineRef 에서 추적 중"))) {
    throw "Checker did not report the explicit $BaselineRef tracking block."
}
if (-not $isIndexed -and -not $isRemoteTracked -and $targetMention) {
    throw 'Checker treated a local-only editor executable as a Git tracking violation.'
}

$targetIsTracked = $isIndexed -or $isRemoteTracked
if ($targetIsTracked -and $exitCode -eq 0) {
    throw 'Checker returned success while the target executable is tracked.'
}
if (-not $targetIsTracked -and $exitCode -eq 0) {
    Write-Output 'PASS: repository hygiene checker reports no tracked violations.'
    exit 0
}
if ($targetIsTracked -and $exitCode -eq 1 -and $targetMention) {
    Write-Output 'PASS: checker blocks the tracked editor executable in the index and/or baseline.'
    exit 0
}

throw "Checker failed unexpectedly (exit $exitCode):`n$text"
