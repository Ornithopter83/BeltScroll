[CmdletBinding()]
param(
    [ValidateSet('Check', 'Apply')]
    [string]$Mode = 'Check',
    [string]$RepositoryRoot,
    [string]$BaselineRef = 'origin/main'
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

$EditorPublishExecutable = '.qa_logs/editor-publish-current/BeltScrollEditor.exe'
$ViolationBytes = [long]71625289

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

function Invoke-GitText {
    param([string[]]$GitArguments)

    $result = & git -C $RepositoryRoot @GitArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArguments -join ' ') failed: $($result -join [Environment]::NewLine)"
    }
    return @($result | ForEach-Object { [string]$_ })
}

function Get-IndexedTarget {
    $records = @(Invoke-GitText -GitArguments @('ls-files', '--stage', '--', $EditorPublishExecutable))
    foreach ($record in $records) {
        if ([string]::IsNullOrWhiteSpace($record)) { continue }
        $separator = $record.IndexOf([char]9)
        if ($separator -lt 0) { continue }
        $metadata = $record.Substring(0, $separator) -split '\s+'
        if ($metadata.Length -lt 3) { continue }
        $sizeLines = @(Invoke-GitText -GitArguments @('cat-file', '-s', $metadata[1]))
        $size = [long]::Parse(([string]::Join('', [string[]]$sizeLines)).Trim(), [Globalization.CultureInfo]::InvariantCulture)
        [pscustomobject]@{ Path = $record.Substring($separator + 1); Size = $size }
    }
}

function Get-BaselineTarget {
    $records = @(Invoke-GitText -GitArguments @('ls-tree', '-r', '-l', '--full-tree', $BaselineRef, '--', $EditorPublishExecutable))
    foreach ($record in $records) {
        if ([string]::IsNullOrWhiteSpace($record)) { continue }
        $separator = $record.IndexOf([char]9)
        if ($separator -lt 0) { continue }
        $metadata = $record.Substring(0, $separator) -split '\s+'
        if ($metadata.Length -lt 4 -or $metadata[3] -eq '-') { continue }
        $size = [long]::Parse($metadata[3], [Globalization.CultureInfo]::InvariantCulture)
        [pscustomobject]@{ Path = $record.Substring($separator + 1); Size = $size }
    }
}

function Write-TargetState {
    param([string]$Label, [object[]]$Entries)

    if ($Entries.Count -eq 0) {
        Write-Output ("{0}: absent" -f $Label)
        return
    }
    foreach ($entry in $Entries) {
        $sizeLabel = ('{0:N0} bytes' -f [long]$entry.Size)
        if ([long]$entry.Size -ge $ViolationBytes) {
            Write-Output ("{0}: TRACKED, SIZE VIOLATION ({1}; threshold {2:N0} bytes): {3}" -f $Label, $sizeLabel, $ViolationBytes, $entry.Path)
        }
        else {
            Write-Output ("{0}: TRACKED ({1}): {2}" -f $Label, $sizeLabel, $entry.Path)
        }
    }
}

try {
    $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
    $localExecutable = Join-Path $RepositoryRoot ($EditorPublishExecutable.Replace('/', [IO.Path]::DirectorySeparatorChar))

    if ($Mode -eq 'Apply') {
        $localExistedBefore = Test-Path -LiteralPath $localExecutable -PathType Leaf
        $localLengthBefore = if ($localExistedBefore) { (Get-Item -LiteralPath $localExecutable).Length } else { $null }
        $indexedBefore = @(Get-IndexedTarget)
        if ($indexedBefore.Count -gt 0) {
            # This is the only repository-mutating command in this tool.
            $null = Invoke-GitText -GitArguments @('rm', '--cached', '--', $EditorPublishExecutable)
            Write-Output "Apply: removed the index entry for $EditorPublishExecutable."
        }
        else {
            Write-Output "Apply: no index entry to remove for $EditorPublishExecutable."
        }

        $localExistsAfter = Test-Path -LiteralPath $localExecutable -PathType Leaf
        if ($localExistedBefore -and (-not $localExistsAfter -or (Get-Item -LiteralPath $localExecutable).Length -ne $localLengthBefore)) {
            throw 'Local editor executable changed during Apply; expected cached-only removal to preserve it.'
        }
        if ($localExistedBefore) {
            Write-Output ("Local executable preserved: {0:N0} bytes." -f $localLengthBefore)
        }
    }

    $indexed = @(Get-IndexedTarget)
    $baseline = @(Get-BaselineTarget)
    Write-TargetState -Label 'index (git ls-files)' -Entries $indexed
    Write-TargetState -Label ("{0} (git ls-tree)" -f $BaselineRef) -Entries $baseline

    $sizeViolation = @($indexed + $baseline | Where-Object { [long]$_.Size -ge $ViolationBytes }).Count -gt 0
    if ($indexed.Count -gt 0 -or $baseline.Count -gt 0) {
        if ($sizeViolation) {
            Write-Output ("FAIL: hygiene blocked; tracked {0:N0}-byte publish executable remains in the index and/or {1}." -f $ViolationBytes, $BaselineRef)
        }
        else {
            Write-Output ("FAIL: hygiene blocked; publish executable remains tracked in the index and/or {0}." -f $BaselineRef)
        }
        exit 1
    }

    Write-Output ("PASS: publish executable is absent from both the index and {0}. A local-only copy is allowed." -f $BaselineRef)
    exit 0
}
catch {
    Write-Error $_
    exit 2
}
