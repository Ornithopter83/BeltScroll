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

function Invoke-GitLines {
    param([string[]]$GitArguments)

    $result = & git -C $script:RepositoryRoot @GitArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArguments -join ' ') failed: $($result -join [Environment]::NewLine)"
    }
    return @($result | ForEach-Object { [string]$_ } | Where-Object { $_.Length -gt 0 })
}

function Add-PathMap {
    param([hashtable]$Map, [string[]]$Paths)
    foreach ($path in $Paths) {
        $normalized = $path.Replace('\', '/')
        $Map[$normalized] = $true
    }
}

try {
    $script:RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
    $null = Invoke-GitLines -GitArguments @('rev-parse', '--show-toplevel')

    $indexed = @{}
    Add-PathMap -Map $indexed -Paths (Invoke-GitLines -GitArguments @(
        'ls-files', '--full-name', '--', '*.import', '*.uid'))

    $remote = @{}
    $remoteRefs = @(Invoke-GitLines -GitArguments @('for-each-ref', '--format=%(refname)', 'refs/remotes'))
    foreach ($ref in $remoteRefs) {
        $remotePaths = Invoke-GitLines -GitArguments @(
            'ls-tree', '-r', '--name-only', '--full-tree', $ref, '--', '*.import', '*.uid')
        Add-PathMap -Map $remote -Paths $remotePaths
    }
    $baselineAvailable = $true
    try {
        $null = Invoke-GitLines -GitArguments @('rev-parse', '--verify', '--quiet', "$BaselineRef^{commit}")
    }
    catch {
        $baselineAvailable = $false
    }

    $untrackedSidecars = Invoke-GitLines -GitArguments @(
        'ls-files', '--others', '--exclude-standard', '--full-name', '--', '*.import', '*.uid')
    $statusLines = Invoke-GitLines -GitArguments @(
        '-c', 'core.quotepath=false', 'status', '--porcelain=v1', '--untracked-files=all')
    $statusByPath = @{}
    foreach ($statusLine in $statusLines) {
        if ($statusLine.Length -lt 4) { continue }
        $statusCode = $statusLine.Substring(0, 2).Trim()
        $statusPath = $statusLine.Substring(3).Replace('\', '/')
        $statusByPath[$statusPath] = $statusCode
    }
    $trackedSidecars = @($indexed.Keys)
    $candidatePaths = @{}
    Add-PathMap -Map $candidatePaths -Paths $untrackedSidecars
    Add-PathMap -Map $candidatePaths -Paths $trackedSidecars
    Add-PathMap -Map $candidatePaths -Paths @($remote.Keys)

    # Also report untracked PNG sources adjacent to import sidecars so that
    # review evidence and user assets are explicitly distinguished.
    foreach ($sidecar in @($candidatePaths.Keys)) {
        if ($sidecar.EndsWith('.import', [StringComparison]::OrdinalIgnoreCase)) {
            $source = $sidecar.Substring(0, $sidecar.Length - '.import'.Length)
            if ([IO.Path]::GetExtension($source) -ieq '.png') {
                $absoluteSource = Join-Path $RepositoryRoot ($source.Replace('/', [IO.Path]::DirectorySeparatorChar))
                if ((Test-Path -LiteralPath $absoluteSource -PathType Leaf) -and -not $indexed.ContainsKey($source)) {
                    $candidatePaths[$source] = $true
                }
            }
        }
    }

    Write-Output 'M6P generated sidecar audit (read-only; no files changed)'
    Write-Output ("Repository: {0}" -f $RepositoryRoot)
    Write-Output ("Remote refs checked: {0}" -f $remoteRefs.Count)
    if (-not $baselineAvailable) {
        Write-Output ("BASELINE-UNAVAILABLE: {0} (remote protection checks use available remote refs and the index)" -f $BaselineRef)
    }
    Write-Output 'PATH | TYPE | GIT | CLASSIFICATION | ACTION | POLICY REASON'

    $counts = @{}
    foreach ($path in @($candidatePaths.Keys | Sort-Object)) {
        $normalized = $path.Replace('\', '/')
        $absolutePath = Join-Path $RepositoryRoot ($normalized.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $exists = Test-Path -LiteralPath $absolutePath -PathType Leaf
        $isIndexed = $indexed.ContainsKey($normalized)
        $isRemote = $remote.ContainsKey($normalized)
        if ($statusByPath.ContainsKey($normalized)) { $workState = $statusByPath[$normalized] }
        else { $workState = 'CLEAN' }
        if ($isIndexed -and $isRemote) { $trackingState = 'INDEX+REMOTE' }
        elseif ($isIndexed) { $trackingState = 'INDEX' }
        elseif ($isRemote) { $trackingState = 'REMOTE' }
        else { $trackingState = 'UNTRACKED' }
        $gitState = "$workState/$trackingState"

        $extension = [IO.Path]::GetExtension($normalized).ToLowerInvariant()
        $sourcePath = ''
        $classification = ''
        $action = 'KEEP'
        $reason = ''
        if ($extension -eq '.import') {
            $sourcePath = $normalized.Substring(0, $normalized.Length - '.import'.Length)
            $sourceAbsolute = Join-Path $RepositoryRoot ($sourcePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
            $sourceExists = Test-Path -LiteralPath $sourceAbsolute -PathType Leaf
            if ($isIndexed -or $isRemote) {
                $classification = 'tracked-import-metadata'
                $reason = '원격 또는 index 추적 파일이므로 보존'
            }
            elseif (-not $sourceExists) {
                $classification = 'orphan-import-sidecar'
                $action = 'CANDIDATE-BLOCKED'
                $reason = '짝이 되는 원본 파일이 없음; 파일별 검토 및 명시적 정리 권한 필요'
            }
            elseif ($sourcePath -match '(^|/)assets/art/review/.*\.png$') {
                $classification = 'review-png-import-sidecar'
                $reason = '검수 PNG의 import 설정 sidecar; 원본 검수 증거와 함께 보존'
            }
            else {
                $classification = 'user-asset-import-sidecar'
                $action = 'REGENERABLE-CANDIDATE-BLOCKED'
                $reason = '재생성 가능성이 있으나 Godot import 설정 보존 여부 불명; 삭제/무시 정책 권한 필요'
            }
        }
        elseif ($extension -eq '.uid') {
            $sourcePath = $normalized.Substring(0, $normalized.Length - '.uid'.Length)
            $sourceAbsolute = Join-Path $RepositoryRoot ($sourcePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
            $sourceExists = Test-Path -LiteralPath $sourceAbsolute -PathType Leaf
            if ($isIndexed -or $isRemote) {
                $classification = 'tracked-godot-uid'
                $reason = '원격 또는 index 추적 파일이므로 보존'
            }
            elseif ($sourceExists) {
                $classification = 'godot-uid-review'
                $action = 'REVIEW-REQUIRED'
                $reason = 'Godot 안정 리소스 UID; 의도적 식별자인지 확인 전 보존'
            }
            else {
                $classification = 'orphan-uid-review'
                $action = 'REVIEW-REQUIRED'
                $reason = '원본 파일이 없지만 UID 용도 불명; 참조 여부 확인 전 보존'
            }
        }
        else {
            $classification = 'png-source-asset'
            if ($normalized -match '(^|/)assets/art/review/') {
                $reason = '검수 PNG 증거; 보존'
            }
            else {
                $reason = '사용자 자산 원본; 보존'
            }
        }

        if (-not $exists -and $extension -ne '.png') {
            $reason = "index 추적 경로가 작업 트리에 없음; $reason"
        }
        if (-not $counts.ContainsKey($classification)) { $counts[$classification] = 0 }
        $counts[$classification]++
        Write-Output ("{0} | {1} | {2} | {3} | {4} | {5}" -f $normalized, $extension.TrimStart('.'), $gitState, $classification, $action, $reason)
    }

    Write-Output 'SUMMARY'
    foreach ($name in @($counts.Keys | Sort-Object)) {
        Write-Output ("{0}: {1}" -f $name, $counts[$name])
    }
    Write-Output 'Policy: audit only. No delete, move, git add, or ignore-rule mutation is performed.'
    Write-Output 'Repeat-run check: capture git status before and after each Godot run; compare changes against this per-file classification.'
    exit 0
}
catch {
    Write-Error $_
    exit 2
}
