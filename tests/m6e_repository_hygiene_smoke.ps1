[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$toolPath = Join-Path $repositoryRoot 'tools/untrack_editor_publish_binary.ps1'
$targetPath = '.qa_logs/editor-publish-current/BeltScrollEditor.exe'
$historicalPath = '.qa_logs/historical-preserved.log'
$expectedSize = [long]71625289
$tempRoot = [IO.Path]::GetTempPath()
$fixtureRoot = Join-Path $tempRoot ('m6e-repository-hygiene-' + [Guid]::NewGuid().ToString('N'))
$fixturePath = Join-Path $fixtureRoot 'fixture'
$executablePath = Join-Path $fixturePath ($targetPath.Replace('/', [IO.Path]::DirectorySeparatorChar))
$historicalFilePath = Join-Path $fixturePath ($historicalPath.Replace('/', [IO.Path]::DirectorySeparatorChar))

function Invoke-Git {
    param([string[]]$GitArguments, [switch]$AllowFailure)

    $result = & git -C $fixturePath @GitArguments 2>&1
    $code = $LASTEXITCODE
    $outputText = @($result | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "git $($GitArguments -join ' ') failed: $outputText"
    }
    [pscustomobject]@{ ExitCode = $code; Text = $outputText }
}

function Invoke-HygieneCheck {
    $result = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $toolPath -RepositoryRoot $fixturePath 2>&1
    $outputText = @($result | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $outputText }
}

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw "$Message`n$Text" }
}

try {
    $null = New-Item -ItemType Directory -Path $fixturePath -Force
    $null = Invoke-Git -GitArguments @('init', '--quiet')
    $null = Invoke-Git -GitArguments @('config', 'user.name', 'M6E Hygiene Smoke')
    $null = Invoke-Git -GitArguments @('config', 'user.email', 'm6e-hygiene-smoke@example.invalid')

    Set-Content -LiteralPath (Join-Path $fixturePath '.gitignore') -Encoding UTF8 -Value @('.qa_logs/', '*.exe')
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $executablePath) -Force
    $stream = [IO.File]::Open($executablePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.SetLength($expectedSize) } finally { $stream.Dispose() }
    Set-Content -LiteralPath $historicalFilePath -Encoding UTF8 -Value 'Historical QA evidence retained by the hygiene gate.'

    $null = Invoke-Git -GitArguments @('add', '--', '.gitignore')
    $null = Invoke-Git -GitArguments @('add', '-f', '--', $targetPath, $historicalPath)
    $null = Invoke-Git -GitArguments @('commit', '--quiet', '-m', 'fixture initial hygiene state')
    $null = Invoke-Git -GitArguments @('update-ref', 'refs/remotes/origin/main', 'HEAD')

    Write-Output 'BEFORE INDEX REMOVAL'
    $beforeFiles = Invoke-Git -GitArguments @('ls-files', '--', $targetPath)
    $beforeTree = Invoke-Git -GitArguments @('ls-tree', '-r', '--long', 'origin/main', '--', $targetPath)
    Assert-Contains -Text $beforeFiles.Text -Pattern ([regex]::Escape($targetPath)) -Message 'ls-files did not show the target before removal.'
    Assert-Contains -Text $beforeTree.Text -Pattern '71625289' -Message 'ls-tree did not show the expected 71,625,289-byte target before removal.'
    Write-Output ("git ls-files: {0}" -f $beforeFiles.Text.Trim())
    Write-Output ("git ls-tree: {0}" -f $beforeTree.Text.Trim())
    $beforeCheck = Invoke-HygieneCheck
    if ($beforeCheck.ExitCode -ne 1) { throw "Expected hygiene Check to fail before removal.`n$($beforeCheck.Text)" }
    Assert-Contains -Text $beforeCheck.Text -Pattern 'SIZE VIOLATION' -Message 'Pre-removal hygiene result did not report the size violation.'
    Write-Output ("hygiene: FAIL as expected (exit {0})" -f $beforeCheck.ExitCode)

    $apply = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $toolPath -RepositoryRoot $fixturePath -Mode Apply 2>&1
    $applyText = @($apply | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 1) { throw "Expected Apply to leave hygiene blocked until remote ref update.`n$applyText" }
    Assert-Contains -Text $applyText -Pattern 'Local executable preserved: 71,625,289 bytes\.' -Message 'Apply did not confirm that the local executable was preserved.'

    Write-Output 'AFTER INDEX REMOVAL, BEFORE PUSH'
    $indexOnlyFiles = Invoke-Git -GitArguments @('ls-files', '--', $targetPath)
    $indexOnlyTree = Invoke-Git -GitArguments @('ls-tree', '-r', '--long', 'origin/main', '--', $targetPath)
    if (-not [string]::IsNullOrWhiteSpace($indexOnlyFiles.Text)) { throw 'ls-files still contains the target after cached-only removal.' }
    Assert-Contains -Text $indexOnlyTree.Text -Pattern '71625289' -Message 'The fixture remote tree should still contain the target before push.'
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf) -or (Get-Item -LiteralPath $executablePath).Length -ne $expectedSize) {
        throw 'The local fixture executable was removed or changed.'
    }
    if (-not (Test-Path -LiteralPath $historicalFilePath -PathType Leaf)) { throw 'Historical QA log was removed.' }
    $historicalIndexed = Invoke-Git -GitArguments @('ls-files', '--', $historicalPath)
    Assert-Contains -Text $historicalIndexed.Text -Pattern ([regex]::Escape($historicalPath)) -Message 'Historical QA log is no longer tracked.'
    $ignoreResult = Invoke-Git -GitArguments @('check-ignore', '-v', '--no-index', '--', $targetPath)
    Assert-Contains -Text $ignoreResult.Text -Pattern '\.gitignore:.*\.qa_logs/' -Message 'Existing .qa_logs ignore rule did not match the untracked target.'
    Write-Output 'git ls-files: absent (target); historical QA log remains tracked'
    Write-Output ("git ls-tree: {0}" -f $indexOnlyTree.Text.Trim())
    Write-Output ("ignore rule: {0}" -f $ignoreResult.Text.Trim())
    $betweenCheck = Invoke-HygieneCheck
    if ($betweenCheck.ExitCode -ne 1) { throw "Expected hygiene Check to remain blocked before remote ref update.`n$($betweenCheck.Text)" }
    Assert-Contains -Text $betweenCheck.Text -Pattern 'origin/main \(git ls-tree\): TRACKED' -Message 'Check did not identify the target remaining in origin/main.'
    Write-Output ("hygiene: FAIL as expected before push (exit {0})" -f $betweenCheck.ExitCode)

    $null = Invoke-Git -GitArguments @('commit', '--quiet', '-m', 'fixture remove target from index')
    $null = Invoke-Git -GitArguments @('update-ref', 'refs/remotes/origin/main', 'HEAD')
    Write-Output 'AFTER PUSH SIMULATION, REMOTE BASELINE UPDATED'
    $afterFiles = Invoke-Git -GitArguments @('ls-files', '--', $targetPath)
    $afterTree = Invoke-Git -GitArguments @('ls-tree', '-r', '--long', 'origin/main', '--', $targetPath)
    if (-not [string]::IsNullOrWhiteSpace($afterFiles.Text)) { throw 'ls-files contains the target after the simulated push.' }
    if (-not [string]::IsNullOrWhiteSpace($afterTree.Text)) { throw 'ls-tree contains the target after the simulated push.' }
    Write-Output 'git ls-files: absent'
    Write-Output 'git ls-tree: absent'
    $afterCheck = Invoke-HygieneCheck
    if ($afterCheck.ExitCode -ne 0) { throw "Expected hygiene Check to pass after remote baseline update.`n$($afterCheck.Text)" }
    Assert-Contains -Text $afterCheck.Text -Pattern '(?m)^PASS:' -Message 'Post-push hygiene Check did not report PASS.'
    Write-Output 'hygiene: PASS after remote baseline update'

    Write-Output 'PASS: pre-removal, index-only removal, and post-push states were distinguished; local executable and historical QA log were preserved.'
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
        if (-not $resolvedFixture.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove fixture outside temp root: $resolvedFixture"
        }
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
