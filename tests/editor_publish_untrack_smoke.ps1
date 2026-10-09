[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$toolPath = Join-Path $repositoryRoot 'tools/untrack_editor_publish_binary.ps1'
$targetPath = '.qa_logs/editor-publish-current/BeltScrollEditor.exe'
$tempRoot = [IO.Path]::GetTempPath()
$fixtureRoot = Join-Path $tempRoot ('editor-publish-untrack-smoke-' + [Guid]::NewGuid().ToString('N'))
$fixturePath = Join-Path $fixtureRoot 'fixture'
$barePath = Join-Path $fixtureRoot 'origin.git'
$executablePath = Join-Path $fixturePath ($targetPath.Replace('/', [IO.Path]::DirectorySeparatorChar))
$expectedSize = [long]71625289

function Invoke-Git {
    param([string]$Root, [string[]]$GitArguments, [switch]$AllowFailure)

    $result = & git -C $Root @GitArguments 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "git $($GitArguments -join ' ') failed: $($result -join [Environment]::NewLine)"
    }
    $outputText = @($result | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    [pscustomobject]@{ ExitCode = $code; Output = $outputText }
}

function Invoke-Tool {
    param([string]$Mode)

    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    $output = & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $toolPath -RepositoryRoot $fixturePath -Mode $Mode 2>&1
    $outputText = @($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $outputText }
}

try {
    if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) { throw "Tool not found: $toolPath" }
    $null = New-Item -ItemType Directory -Path $fixturePath -Force
    $null = Invoke-Git -Root $fixtureRoot -GitArguments @('init', '--bare', $barePath)
    $null = Invoke-Git -Root $fixtureRoot -GitArguments @('init', $fixturePath)
    $null = Invoke-Git -Root $fixturePath -GitArguments @('config', 'user.name', 'Smoke Fixture')
    $null = Invoke-Git -Root $fixturePath -GitArguments @('config', 'user.email', 'smoke@example.invalid')
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $executablePath) -Force

    # A sparse all-zero file preserves the expected logical size without adding a large fixture payload.
    $stream = New-Object IO.FileStream($executablePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.SetLength($expectedSize) } finally { $stream.Dispose() }
    $null = Invoke-Git -Root $fixturePath -GitArguments @('add', '--', $targetPath)
    $null = Invoke-Git -Root $fixturePath -GitArguments @('commit', '-m', 'fixture publish executable')
    $null = Invoke-Git -Root $fixturePath -GitArguments @('update-ref', 'refs/remotes/origin/main', 'HEAD')

    $checkBefore = Invoke-Tool -Mode 'Check'
    if ($checkBefore.ExitCode -ne 1 -or $checkBefore.Text -notmatch 'SIZE VIOLATION' -or $checkBefore.Text -notmatch '71,625,289') {
        throw "Check did not report the fixture's tracked size violation:`n$($checkBefore.Text)"
    }

    $apply = Invoke-Tool -Mode 'Apply'
    if ($apply.ExitCode -ne 1 -or $apply.Text -notmatch 'Local executable preserved: 71,625,289 bytes\.') {
        throw "Apply did not preserve the fixture executable and keep hygiene blocked before push:`n$($apply.Text)"
    }
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf) -or (Get-Item -LiteralPath $executablePath).Length -ne $expectedSize) {
        throw 'Apply removed or changed the fixture working-copy executable.'
    }
    $indexAfterApply = Invoke-Git -Root $fixturePath -GitArguments @('ls-files', '--', $targetPath)
    if (-not [string]::IsNullOrWhiteSpace($indexAfterApply.Output)) { throw 'Apply left the executable in the fixture index.' }

    $checkBeforePush = Invoke-Tool -Mode 'Check'
    if ($checkBeforePush.ExitCode -ne 1 -or $checkBeforePush.Text -notmatch 'origin/main \(git ls-tree\): TRACKED') {
        throw "Check passed before the fixture remote baseline was updated:`n$($checkBeforePush.Text)"
    }

    $null = Invoke-Git -Root $fixturePath -GitArguments @('commit', '-m', 'fixture remove publish executable')
    $null = Invoke-Git -Root $fixturePath -GitArguments @('update-ref', 'refs/remotes/origin/main', 'HEAD')
    $checkAfterPush = Invoke-Tool -Mode 'Check'
    if ($checkAfterPush.ExitCode -ne 0 -or $checkAfterPush.Text -notmatch '(?m)^PASS:' -or $checkAfterPush.Text -notmatch 'origin/main \(git ls-tree\): absent') {
        throw "Check did not pass after the fixture remote baseline dropped the executable:`n$($checkAfterPush.Text)"
    }

    Write-Output 'PASS: Check reports the tracked size violation, Apply removes only the fixture index entry, and PASS requires an updated fixture origin/main.'
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
