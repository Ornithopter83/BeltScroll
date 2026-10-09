param(
    [string]$Configuration = 'Release',
    [switch]$SelfTest
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
Write-Host "Built standalone editor: $exe"
