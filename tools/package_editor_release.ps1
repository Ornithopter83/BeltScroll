param(
    [string]$Version,
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\editor-release'),
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $projectRoot 'editor\build_editor.ps1'
$editorPath = Join-Path $projectRoot 'dist\BeltScrollEditor.exe'

if ([string]::IsNullOrWhiteSpace($Version)) {
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REF_NAME)) {
        $Version = $env:GITHUB_REF_NAME
    } else {
        $gitVersion = (& git -C $projectRoot describe --tags --always --dirty 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitVersion)) {
            $Version = $gitVersion.Trim()
        } elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_SHA)) {
            $Version = $env:GITHUB_SHA.Substring(0, [Math]::Min(12, $env:GITHUB_SHA.Length))
        } else {
            $Version = '0.0.0-local'
        }
    }
}
$safeVersion = $Version -replace '[^A-Za-z0-9._-]', '-'
if ([string]::IsNullOrWhiteSpace($safeVersion)) { throw 'Version must contain a letter or number.' }
$outputFullPath = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($outputFullPath)

& $buildScript -Configuration $Configuration -SelfTest
if ($LASTEXITCODE -ne 0) { throw "Editor publish/self-test failed with exit code $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath $editorPath -PathType Leaf)) { throw "Published executable not found: $editorPath" }

$hash = (Get-FileHash -LiteralPath $editorPath -Algorithm SHA256).Hash.ToLowerInvariant()
$packageName = "BeltScrollEditor-$safeVersion-win-x64.zip"
$packagePath = Join-Path $outputFullPath $packageName
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollEditorPackage_' + [Guid]::NewGuid().ToString('N'))
$stageDir = Join-Path $stageRoot 'BeltScrollEditor'
try {
    [void][IO.Directory]::CreateDirectory($stageDir)
    Copy-Item -LiteralPath $editorPath -Destination (Join-Path $stageDir 'BeltScrollEditor.exe')
    $readme = @"
BeltScrollEditor $Version (Windows x64)

This is a standalone, self-contained Windows x64 application. No repository checkout or .NET runtime installation is needed.

Quick start
1. Extract this ZIP to a folder you can write to.
2. Run BeltScrollEditor.exe.
3. Use Open/Save to edit numeric game data. The art and animation workspace is available from the editor.

Integrity
SHA-256  BeltScrollEditor.exe
$hash

Build provenance
Version: $Version
Runtime: win-x64, self-contained, single-file publish
"@
    [IO.File]::WriteAllText((Join-Path $stageDir 'README.txt'), $readme, (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $stageDir 'SHA256SUMS.txt'), "$hash  BeltScrollEditor.exe`r`n", (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $packagePath) { Remove-Item -LiteralPath $packagePath -Force }
    Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $packagePath -CompressionLevel Optimal
} finally {
    if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
}

$zipHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Editor release package: $packagePath"
Write-Host "Version: $Version"
Write-Host "Executable SHA-256: $hash"
Write-Host "ZIP SHA-256: $zipHash"
