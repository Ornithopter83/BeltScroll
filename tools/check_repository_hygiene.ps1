[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$BaselineRef = 'origin/main',
    [long]$LargeExecutableBytes = 10MB
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

function Invoke-GitText {
    param([string[]]$GitArguments)

    $result = & git -C $RepositoryRoot @GitArguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArguments -join ' ') failed: $($result -join [Environment]::NewLine)"
    }
    return $result
}

function Get-TrackedPaths {
    param([string]$Revision)

    $raw = Invoke-GitText -GitArguments @('ls-tree', '-r', '--name-only', $Revision)
    return @($raw | Where-Object { -not [string]::IsNullOrEmpty($_) })
}

function Get-IndexedEntries {
    $raw = Invoke-GitText -GitArguments @('ls-files', '--stage')
    foreach ($record in $raw) {
        $separator = $record.IndexOf([char]9)
        if ($separator -lt 0) { continue }
        $metadata = $record.Substring(0, $separator).Split(' ')
        if ($metadata.Length -lt 3) { continue }
        [pscustomobject]@{
            Mode = $metadata[0]
            ObjectId = $metadata[1]
            Stage = $metadata[2]
            Path = $record.Substring($separator + 1)
        }
    }
}

try {
    $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
    $trackedEntries = @(Get-IndexedEntries)

    $baselinePaths = @{}
    try {
        foreach ($path in (Get-TrackedPaths -Revision $BaselineRef)) {
            $baselinePaths[$path] = $true
        }
    }
    catch {
        Write-Error "기준 ref '$BaselineRef'를 읽을 수 없습니다. 원격 기준선을 갱신하거나 -BaselineRef를 지정하세요. $_"
        exit 2
    }

    $findings = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $trackedEntries) {
        $relativePath = $entry.Path
        $normalized = $relativePath.Replace('\', '/')
        $inBaseline = $baselinePaths.ContainsKey($relativePath)

        if ($normalized -match '(^|/)(\.godot|\.vs|\.cache|obj|build|publish|artifacts)(/|$)' -or
            $normalized -match '^(bin|editor/bin|editor/obj|tools/bin|tools/obj)/') {
            $findings.Add("빌드 캐시/산출물 추적: $relativePath")
            continue
        }

        if ($normalized -match '\.(log|stderr|stdout|tmp|cache)$' -and -not $inBaseline) {
            $findings.Add("새 자동 생성 로그/임시 파일 추적: $relativePath")
            continue
        }

        if ($normalized.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
            $sizeText = Invoke-GitText -GitArguments @('cat-file', '-s', $entry.ObjectId)
            $sizeValue = [string]::Join('', [string[]]$sizeText).Trim()
            $indexedSize = [long]::Parse($sizeValue, [Globalization.CultureInfo]::InvariantCulture)
            if ($indexedSize -ge $LargeExecutableBytes) {
                $findings.Add(("대용량 실행 파일 추적 ({0:N0} bytes): {1}" -f $indexedSize, $relativePath))
            }
            elseif (-not $inBaseline) {
                $findings.Add("새 임시 실행 파일 추적: $relativePath")
            }
        }
        elseif ($normalized.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase) -and
            $normalized -match '(^|/)(\.qa_logs|dist|build|publish)/' -and -not $inBaseline) {
            $findings.Add("새 배포 ZIP 추적: $relativePath")
        }
    }

    if ($findings.Count -gt 0) {
        foreach ($finding in $findings) { Write-Output "FAIL: $finding" }
        Write-Output ("Repository hygiene failed with {0} finding(s)." -f $findings.Count)
        exit 1
    }

    Write-Output 'Repository hygiene passed.'
    exit 0
}
catch {
    Write-Error $_
    exit 2
}
