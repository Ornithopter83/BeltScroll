param(
    [long]$RunId = 37921763731,
    [string]$ArtifactName = 'BeltScrollEditor-win-x64-1',
    [string]$Repository,
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
$packageSha = $null
$packageExtract = $null
$source = if ($isLocal) { 'local-package' } else { 'github-actions-artifact' }

function Add-Check([string]$Name, [string]$Status, [string]$Details) {
    $checks.Add([pscustomobject]@{ name = $Name; status = $Status; details = $Details })
    Write-Output ('[{0}] {1}: {2}' -f $Status, $Name, $Details)
}

function Save-Report([string]$Status, [string]$Package, [string]$Sha256, [string]$Extracted) {
    $report = [ordered]@{
        source = $source
        runId = if ($isLocal) { $null } else { $RunId }
        artifactName = if ($isLocal) { $null } else { $ArtifactName }
        repository = $Repository
        packagePath = $Package
        extractedPath = $Extracted
        packageSha256 = $Sha256
        status = $Status
        checks = $checks.ToArray()
        checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
}

try {
    $package = $null
    if ($isLocal) {
        $package = [IO.Path]::GetFullPath($PackagePath)
        if (-not (Test-Path -LiteralPath $package -PathType Leaf)) { throw "Local package not found: $package" }
        Add-Check 'Source selection' 'PASS' 'Local package mode; no remote claim is made.'
    } else {
        $gh = Get-Command gh -ErrorAction SilentlyContinue
        if (-not $gh) {
            Add-Check 'Remote access' 'UNVERIFIED' 'GitHub CLI (gh) is not installed.'
            $overall = 'UNVERIFIED'
            throw '__UNVERIFIED__'
        }
        if ([string]::IsNullOrWhiteSpace($Repository)) {
            $repoJson = & gh repo view --json nameWithOwner 2>&1
            if ($LASTEXITCODE -ne 0) { throw ('Cannot identify repository: ' + ($repoJson -join ' ')) }
            $Repository = (($repoJson -join "`n") | ConvertFrom-Json).nameWithOwner
        }
        $authText = & gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Check 'Remote access' 'UNVERIFIED' 'GitHub CLI authentication is unavailable; authenticate with gh auth login and grant Actions read access.'
            $overall = 'UNVERIFIED'
            throw '__UNVERIFIED__'
        }
        Add-Check 'GitHub authentication' 'PASS' "Authenticated to GitHub for $Repository."

        $runText = & gh api "repos/$Repository/actions/runs/$RunId" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Check 'Run metadata access' 'UNVERIFIED' ('Could not read run metadata (network or repository permission): ' + ($runText -join ' '))
            $overall = 'UNVERIFIED'
            throw '__UNVERIFIED__'
        }
        $run = ($runText -join "`n") | ConvertFrom-Json
        $runOk = $run.status -eq 'completed' -and $run.conclusion -eq 'success'
        Add-Check 'Workflow run completed successfully' $(if ($runOk) { 'PASS' } else { 'FAIL' }) ("run={0}; status={1}; conclusion={2}; headSha={3}" -f $RunId, $run.status, $run.conclusion, $run.head_sha)
        if (-not $runOk) { throw 'The specified GitHub Actions run did not complete successfully.' }

        $artifactText = & gh api "repos/$Repository/actions/runs/$RunId/artifacts" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Check 'Artifact metadata access' 'UNVERIFIED' ('Could not list artifacts: ' + ($artifactText -join ' '))
            $overall = 'UNVERIFIED'
            throw '__UNVERIFIED__'
        }
        $artifactList = ($artifactText -join "`n") | ConvertFrom-Json
        $matches = @($artifactList.artifacts | Where-Object { $_.name -eq $ArtifactName })
        if ($matches.Count -ne 1) {
            Add-Check 'Expected artifact exists' 'FAIL' ("Expected exactly one '$ArtifactName'; found $($matches.Count).")
            throw 'Expected GitHub Actions artifact is missing or duplicated.'
        }
        $artifact = $matches[0]
        if ($artifact.expired) { throw "Artifact '$ArtifactName' has expired." }
        Add-Check 'Expected artifact exists and is unexpired' 'PASS' ("id={0}; size={1}; digest={2}" -f $artifact.id, $artifact.size_in_bytes, $artifact.digest)

        $artifactContents = Join-Path $resolvedOutput 'artifact-content'
        [void][IO.Directory]::CreateDirectory($artifactContents)
        $downloadText = & gh run download $RunId --repo $Repository --name $ArtifactName --dir $artifactContents 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Check 'Artifact ZIP download' 'UNVERIFIED' ('Download failed (network or Actions artifact read permission): ' + ($downloadText -join ' '))
            $overall = 'UNVERIFIED'
            throw '__UNVERIFIED__'
        }
        Add-Check 'Artifact download and extraction' 'PASS' ("Downloaded '$ArtifactName' with gh; GitHub metadata digest=$($artifact.digest). gh run download extracts the outer Actions archive before saving the uploaded file.")
        $packages = @(Get-ChildItem -LiteralPath $artifactContents -Filter 'BeltScrollEditor-*.zip' -File -Recurse)
        if ($packages.Count -ne 1) { throw "Expected one packaged editor ZIP inside the artifact; found $($packages.Count)." }
        $package = $packages[0].FullName
        Add-Check 'Artifact package extraction' 'PASS' $package
    }

    $packageSha = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
    $packageExtract = Join-Path $resolvedOutput 'extracted-package'
    [void][IO.Directory]::CreateDirectory($packageExtract)
    Expand-Archive -LiteralPath $package -DestinationPath $packageExtract -Force
    $editorPath = Join-Path $packageExtract 'BeltScrollEditor.exe'
    $sumsPath = Join-Path $packageExtract 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $editorPath -PathType Leaf)) { throw 'Package ZIP does not contain BeltScrollEditor.exe at its root.' }
    if (-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)) { throw 'Package ZIP does not contain SHA256SUMS.txt.' }
    $exeSha = (Get-FileHash -LiteralPath $editorPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifestSha = ((Get-Content -Encoding UTF8 -Raw -LiteralPath $sumsPath) -split '\s+')[0].ToLowerInvariant()
    if ($exeSha -ne $manifestSha) { throw "EXE SHA-256 does not match packaged manifest: expected $manifestSha, got $exeSha" }
    Add-Check 'Extracted EXE SHA-256' 'PASS' $exeSha
    Add-Check 'Package ZIP SHA-256' 'PASS' $packageSha

    $smokeScript = Join-Path $PSScriptRoot '..\tests\editor_release_package_smoke.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $smokeScript -PackagePath $package -TimeoutSeconds $TimeoutSeconds
    if ($LASTEXITCODE -ne 0) { throw "Release package smoke failed with exit code $LASTEXITCODE." }
    Add-Check 'Self-test, external working directory, GUI edit/save/reopen' 'PASS' 'editor_release_package_smoke.ps1 completed; extracted-package smoke validates the shipped EXE and GUI file output.'
    $overall = 'PASS'
} catch {
    if ($checks.Count -eq 0 -or $checks[$checks.Count - 1].status -ne 'UNVERIFIED') {
        Add-Check 'Verification' 'FAIL' $_.Exception.Message
    }
    if ($overall -ne 'UNVERIFIED') { $overall = 'FAIL' }
} finally {
    Save-Report $overall $package $packageSha $packageExtract
    Write-Output "Verification report: $reportPath"
    Write-Output "Verification status: $overall"
}

if ($overall -eq 'PASS') { exit 0 }
if ($overall -eq 'UNVERIFIED') { exit 2 }
exit 1
