param(
    [string]$EditorPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\BeltScrollEditor.exe')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$resolvedEditor = [IO.Path]::GetFullPath($EditorPath)
if (-not (Test-Path -LiteralPath $resolvedEditor -PathType Leaf)) {
    throw "Standalone editor executable not found: $resolvedEditor"
}

# This is a code-level preparation smoke test. It does not claim a human GUI review
# or launch a game window; those remain an explicit operator playtest. Run through
# cmd.exe so PowerShell 5.1 captures the native process exit code reliably.
$quotedEditor = '"' + $resolvedEditor.Replace('"', '""') + '"'
$selfTestOutput = & $env:ComSpec /d /s /c ($quotedEditor + ' --self-test')
$selfTestExitCode = $LASTEXITCODE
if ($selfTestOutput) { $selfTestOutput | Write-Output }
if ($selfTestExitCode -ne 0) { throw "Editor self-test failed with exit code $selfTestExitCode" }

$projectRoot = Split-Path -Parent $PSScriptRoot
$editorSource = Join-Path $projectRoot 'editor\BeltScrollEditor.cs'
$source = Get-Content -Encoding UTF8 -Raw -LiteralPath $editorSource
foreach ($required in @('ValidateGodotExecutable', 'ValidateProjectRoot', 'CreatePlaytestWorkspace', 'scenes/review/m6i_combat_test_arena.tscn', 'ArgumentList.Add("--scene")', '미저장 편집값은 적용되지 않음', '전투 테스트 종료 코드')) {
    if (-not $source.Contains($required)) { throw "Combat playtest implementation contract is missing: $required" }
}
Write-Output 'Combat playtest preparation smoke passed. No manual GUI review was performed.'
