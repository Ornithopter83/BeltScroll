param(
    [string]$Repository,
    [long]$ExpectedRunId,
    [string]$ExpectedArtifactName,
    [string]$OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollEditorArtifact_' + [Guid]::NewGuid().ToString('N'))),
    [string]$PackagePath,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$isLocal = -not [string]::IsNullOrWhiteSpace($PackagePath)
$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($resolvedOutput)
$reportPath = Join-Path $resolvedOutput 'verification-report.json'
$checks = New-Object System.Collections.Generic.List[object]
$overall = 'FAIL'
$package = $null
$packageSha = $null
$packageExtract = $null
$outerArchive = $null
$outerArchiveSha = $null
$runId = $null
$runSha = $null
$artifactName = $null
$artifactId = $null
$artifactDigest = $null
$source = if ($isLocal) { 'local-package' } else { 'github-actions-artifact' }

function Add-Check([string]$Name, [string]$Status, [string]$Details) {
    $checks.Add([pscustomobject]@{ name = $Name; status = $Status; details = $Details })
    Write-Output ('[{0}] {1}: {2}' -f $Status, $Name, $Details)
}

function Save-Report([string]$Status, [string]$PackagePathValue, [string]$Sha256, [string]$Extracted) {
    $report = [ordered]@{
        source = $source
        repository = $Repository
        mainSha = $runSha
        runId = $runId
        artifactName = $artifactName
        artifactId = $artifactId
        artifactDigest = $artifactDigest
        outerArtifactZipPath = $outerArchive
        outerArtifactZipSha256 = $outerArchiveSha
        packagePath = $PackagePathValue
        packageSha256 = $Sha256
        extractedPath = $Extracted
        status = $Status
        checks = $checks.ToArray()
        checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-GhJson([string[]]$Arguments, [string]$FailureName) {
    # Native stderr is surfaced as an ErrorRecord by Windows PowerShell 5.1.
    # With the script-wide Stop preference, that used to jump to the outer
    # catch before the nonzero exit could be classified as UNVERIFIED.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $text = & gh @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        Add-Check $FailureName 'UNVERIFIED' ('GitHub API request failed (network, authentication, or permission): ' + ($text -join ' '))
        $script:overall = 'UNVERIFIED'
        throw '__UNVERIFIED__'
    }
    try { return (($text -join "`n") | ConvertFrom-Json) }
    catch {
        Add-Check $FailureName 'UNVERIFIED' ('GitHub API returned unreadable JSON: ' + $_.Exception.Message)
        $script:overall = 'UNVERIFIED'
        throw '__UNVERIFIED__'
    }
}

function Invoke-GhDownload([string]$RepositoryName, [long]$ArtifactIdentifier, [string]$Destination) {
    $ghCommand = Get-Command gh -ErrorAction Stop
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ghCommand.Source
    $startInfo.Arguments = ('api -H "Accept: application/vnd.github+json" "repos/{0}/actions/artifacts/{1}/zip"' -f $RepositoryName, $ArtifactIdentifier)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $fileStream = [IO.File]::Create($Destination)
    try { $process.StandardOutput.BaseStream.CopyTo($fileStream) }
    finally { $fileStream.Dispose() }
    $process.WaitForExit()
    return [pscustomobject]@{ exitCode = $process.ExitCode; stderr = $stderrTask.Result }
}

try {
    if ($isLocal) {
        $package = [IO.Path]::GetFullPath($PackagePath)
        if (-not (Test-Path -LiteralPath $package -PathType Leaf)) { throw "Local package not found: $package" }
        Add-Check 'Evidence scope' 'PASS' 'Local deployment ZIP inspection only; no GitHub run or artifact claim is made.'
    } else {
        $gh = Get-Command gh -ErrorAction SilentlyContinue
        if (-not $gh) {
            Add-Check 'Remote access' 'UNVERIFIED' 'GitHub CLI (gh) is not installed.'
            $overall = 'UNVERIFIED'
            throw '__UNVERIFIED__'
        }
        # Keep native stderr from becoming a terminating PowerShell error so
        # authentication failures follow the explicit UNVERIFIED path below.
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $authText = & gh auth status 2>&1
            $authExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($authExitCode -ne 0) {
            Add-Check 'Remote access' 'UNVERIFIED' 'GitHub CLI authentication is unavailable; authenticate with gh auth login and grant Actions read access.'
            $overall = 'UNVERIFIED'
            throw '__UNVERIFIED__'
        }
        if ([string]::IsNullOrWhiteSpace($Repository)) {
            $repoInfo = Invoke-GhJson @('repo', 'view', '--json', 'nameWithOwner') 'Repository lookup'
            $Repository = [string]$repoInfo.nameWithOwner
        }
        if ([string]::IsNullOrWhiteSpace($Repository) -or $Repository -notmatch '^[^/]+/[^/]+$') { throw "Invalid repository name: $Repository" }
        Add-Check 'GitHub authentication' 'PASS' "Authenticated to GitHub for $Repository."

        $mainCommit = Invoke-GhJson @('api', "repos/$Repository/commits/main") 'Current main SHA lookup'
        $mainSha = [string]$mainCommit.sha
        if ($mainSha -cnotmatch '^[0-9a-fA-F]{40}$') { throw 'GitHub main commit response has no valid SHA.' }
        $runList = Invoke-GhJson @('api', "repos/$Repository/actions/workflows/editor-package.yml/runs?branch=main&per_page=100") 'Package run lookup'
        $successfulRuns = @($runList.workflow_runs | Where-Object {
            $_.head_sha -eq $mainSha -and $_.status -eq 'completed' -and $_.conclusion -eq 'success'
        } | Sort-Object @{ Expression = { [datetime]$_.created_at }; Descending = $true })
        if ($successfulRuns.Count -eq 0) { throw "No completed successful editor-package run is attached to current main SHA $mainSha." }
        $run = $successfulRuns[0]
        $runId = [long]$run.id
        $runSha = [string]$run.head_sha
        if ($ExpectedRunId -gt 0 -and $runId -ne $ExpectedRunId) { throw "Latest successful package run for main is $runId; expected run $ExpectedRunId." }
        Add-Check 'Latest successful package run for current main' 'PASS' ("run={0}; status={1}; conclusion={2}; headSha={3}" -f $runId, $run.status, $run.conclusion, $runSha)

        $artifactList = Invoke-GhJson @('api', "repos/$Repository/actions/runs/$runId/artifacts") 'Artifact metadata lookup'
        $runNumber = [long]$run.run_number
        $requiredName = "BeltScrollEditor-win-x64-$runNumber"
        if (-not [string]::IsNullOrWhiteSpace($ExpectedArtifactName) -and $requiredName -cne $ExpectedArtifactName) {
            throw "Latest run artifact name is derived as '$requiredName'; expected '$ExpectedArtifactName'."
        }
        $matches = @($artifactList.artifacts | Where-Object { $_.name -ceq $requiredName })
        if ($matches.Count -ne 1) { throw "Expected exactly one artifact named '$requiredName' for run $runId; found $($matches.Count)." }
        $artifact = $matches[0]
        $artifactName = [string]$artifact.name
        $artifactId = [long]$artifact.id
        $artifactDigest = [string]$artifact.digest
        if ($artifact.expired) { throw "Artifact '$artifactName' (id $artifactId) has expired." }
        if ($artifactDigest -cnotmatch '^sha256:[0-9a-fA-F]{64}$') { throw "Artifact '$artifactName' has no valid SHA-256 digest in GitHub API metadata." }
        Add-Check 'Artifact name and ID from run API' 'PASS' ("name={0}; id={1}; size={2}; digest={3}" -f $artifactName, $artifactId, $artifact.size_in_bytes, $artifactDigest)

        $outerArchive = Join-Path $resolvedOutput 'actions-artifact-outer.zip'
        $outerExtract = Join-Path $resolvedOutput 'actions-artifact-outer-extracted'
        if (Test-Path -LiteralPath $outerExtract) { Remove-Item -LiteralPath $outerExtract -Recurse -Force }
        if (Test-Path -LiteralPath $outerArchive) { Remove-Item -LiteralPath $outerArchive -Force }
        $downloadResult = Invoke-GhDownload $Repository $artifactId $outerArchive
        if ($downloadResult.exitCode -ne 0) {
            Add-Check 'Outer Actions archive download' 'UNVERIFIED' ('Download failed (network or Actions artifact read permission): ' + $downloadResult.stderr)
            $overall = 'UNVERIFIED'
            throw '__UNVERIFIED__'
        }
        if (-not (Test-Path -LiteralPath $outerArchive -PathType Leaf)) { throw 'GitHub CLI reported success but did not save the outer Actions ZIP.' }
        $outerArchiveSha = (Get-FileHash -LiteralPath $outerArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        $expectedOuterSha = $artifactDigest.Substring('sha256:'.Length).ToLowerInvariant()
        if ($outerArchiveSha -cne $expectedOuterSha) { throw "Outer Actions ZIP SHA-256 differs from GitHub API digest: expected $expectedOuterSha, got $outerArchiveSha." }
        Add-Check 'Outer Actions ZIP download and digest' 'PASS' ("path=$outerArchive; sha256=$outerArchiveSha")

        [void][IO.Directory]::CreateDirectory($outerExtract)
        Expand-Archive -LiteralPath $outerArchive -DestinationPath $outerExtract -Force
        $packages = @(Get-ChildItem -LiteralPath $outerExtract -Filter 'BeltScrollEditor-*.zip' -File -Recurse)
        if ($packages.Count -ne 1) { throw "Expected one inner deployment ZIP in the outer Actions ZIP; found $($packages.Count)." }
        $package = $packages[0].FullName
        Add-Check 'Inner deployment ZIP identified' 'PASS' ("$package (outer Actions archive was separately retained and digest-checked)")
    }

    $packageSha = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
    $packageExtract = Join-Path $resolvedOutput 'deployment-package-extracted'
    if (Test-Path -LiteralPath $packageExtract) { Remove-Item -LiteralPath $packageExtract -Recurse -Force }
    [void][IO.Directory]::CreateDirectory($packageExtract)
    Expand-Archive -LiteralPath $package -DestinationPath $packageExtract -Force
    $editorPath = Join-Path $packageExtract 'BeltScrollEditor.exe'
    $sumsPath = Join-Path $packageExtract 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $editorPath -PathType Leaf)) { throw 'Deployment ZIP does not contain BeltScrollEditor.exe at its root.' }
    if (-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)) { throw 'Deployment ZIP does not contain SHA256SUMS.txt.' }
    $exeSha = (Get-FileHash -LiteralPath $editorPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sumText = Get-Content -Encoding UTF8 -Raw -LiteralPath $sumsPath
    if ($sumText -notmatch '(?im)^([0-9a-f]{64})\s+\*?BeltScrollEditor\.exe\s*$') { throw 'SHA256SUMS.txt does not contain a valid BeltScrollEditor.exe checksum entry.' }
    $manifestSha = $Matches[1].ToLowerInvariant()
    if ($exeSha -cne $manifestSha) { throw "EXE SHA-256 does not match deployment manifest: expected $manifestSha, got $exeSha." }
    Add-Check 'Extracted deployment EXE SHA-256' 'PASS' $exeSha
    Add-Check 'Inner deployment ZIP SHA-256' 'PASS' $packageSha

    $smokeScript = Join-Path $PSScriptRoot '..\tests\editor_release_package_smoke.ps1'
    $smokeOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $smokeScript -PackagePath $package -TimeoutSeconds $TimeoutSeconds 2>&1
    $smokeExitCode = $LASTEXITCODE
    if ($smokeExitCode -ne 0) { throw ("Release package self-test and GUI verification failed with exit code {0}: {1}" -f $smokeExitCode, ($smokeOutput -join ' ')) }
    Add-Check 'Extracted EXE self-test and GUI verification' 'PASS' 'editor_release_package_smoke.ps1 passed --self-test, numeric edit/save/reopen, animation workspace, export, and GUI capture checks.'
    $overall = 'PASS'
} catch {
    if ($_.Exception.Message -ne '__UNVERIFIED__') {
        Add-Check 'Verification' 'FAIL' $_.Exception.Message
        if ($overall -ne 'UNVERIFIED') { $overall = 'FAIL' }
    }
} finally {
    Save-Report $overall $package $packageSha $packageExtract
    Write-Output "Verification report: $reportPath"
    Write-Output "Verification status: $overall"
}

if ($overall -eq 'PASS') { exit 0 }
if ($overall -eq 'UNVERIFIED') { exit 2 }
exit 1
