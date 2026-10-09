param(
    [string]$Configuration = 'Release',
    [switch]$SelfTest,
    [switch]$GuiAcceptance
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $PSScriptRoot 'BeltScrollEditor.csproj'
$output = Join-Path $projectRoot 'dist'
$buildTemp = Join-Path $env:TEMP 'BeltScrollEditor-build'
New-Item -ItemType Directory -Force -Path $output | Out-Null
New-Item -ItemType Directory -Force -Path $buildTemp | Out-Null
$stalePdb = Join-Path $output 'BeltScrollEditor.pdb'
if (Test-Path -LiteralPath $stalePdb) { [System.IO.File]::Delete($stalePdb) }
dotnet publish $project -c $Configuration -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true -p:RuntimeFrameworkVersion=8.0.30 `
    -p:NuGetAudit=false -p:RestoreIgnoreFailedSources=true -p:DebugType=None `
    -p:DebugSymbols=false -p:BaseIntermediateOutputPath="$buildTemp\obj\" `
    -p:BaseOutputPath="$buildTemp\bin\" -o $output
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }
$exe = Join-Path $output 'BeltScrollEditor.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "Publish did not create $exe" }
if ($SelfTest) {
    & $exe --self-test
    if ($LASTEXITCODE -ne 0) { throw "Self-test failed with exit code $LASTEXITCODE" }
}
if ($GuiAcceptance) {
    $acceptanceDir = Join-Path $env:TEMP ('BeltScrollEditorGuiAcceptance_' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($acceptanceDir)
    $acceptance = Start-Process -FilePath $exe -ArgumentList @('--gui-acceptance', $acceptanceDir) `
        -WorkingDirectory $acceptanceDir -PassThru
    if (-not $acceptance.WaitForExit(120000)) {
        try { $acceptance.Kill() } catch { }
        throw "GUI acceptance timed out; artifacts: $acceptanceDir"
    }
    $report = Join-Path $acceptanceDir 'gui-acceptance.json'
    if ($acceptance.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $report)) {
        throw "GUI acceptance failed (exit=$($acceptance.ExitCode)); artifacts: $acceptanceDir"
    }
    $result = Get-Content -Encoding UTF8 -Raw -LiteralPath $report | ConvertFrom-Json
    if (-not $result.passed) { throw "GUI acceptance report failed; artifacts: $acceptanceDir" }
    Write-Host "GUI acceptance artifacts: $acceptanceDir"
}
Write-Host "Built standalone editor: $exe"
