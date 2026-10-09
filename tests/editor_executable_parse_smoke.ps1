$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$scriptPath = Join-Path $PSScriptRoot 'editor_executable_smoke.ps1'
$source = Get-Content -Encoding UTF8 -Raw -LiteralPath $scriptPath
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)

if ($parseErrors.Count -gt 0) {
    foreach ($parseError in $parseErrors) {
        [Console]::Error.WriteLine(('editor_executable_parse_smoke: FAIL: line {0}, column {1}: {2}' -f $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message))
    }
    exit 1
}

if (-not $source.Contains("[Console]::IsInputRedirected") -or -not $source.Contains('Read-Host')) {
    [Console]::Error.WriteLine('editor_executable_parse_smoke: FAIL: interactive Y/N gate or redirected-input block is missing')
    exit 1
}

Write-Output ('editor_executable_parse_smoke: parsed {0} with PowerShell {1}; interactive Y/N gate and redirected-input block verified' -f $scriptPath, $PSVersionTable.PSVersion)
Write-Output 'editor_executable_parse_smoke: all checks passed'
exit 0
