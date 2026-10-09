param(
    [Parameter(Mandatory = $true)][string]$LogPath,
    [Parameter(Mandatory = $true)][int]$Sequence,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][ValidateSet('headless', 'powershell')][string]$ExecutionType,
    [Parameter(Mandatory = $true)][int]$ProcessExit
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)

try {
    if ($Sequence -lt 1 -or $Sequence -gt 14) { throw "Recorder sequence must be between 1 and 14: $Sequence" }
    if ($Name -notmatch '^[a-z0-9_]+$') { throw "Invalid recorder name: $Name" }
    if ($ProcessExit -lt 0) { throw "Invalid recorder process exit code: $ProcessExit" }

    $fullPath = [IO.Path]::GetFullPath($LogPath)
    $records = New-Object 'System.Collections.Generic.List[object]'
    if (Test-Path -LiteralPath $fullPath) {
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Accounting log path is not a file: $fullPath" }
        $existingLines = [IO.File]::ReadAllLines($fullPath, $utf8)
        foreach ($line in $existingLines) {
            if ([string]::IsNullOrWhiteSpace($line)) { throw 'Accounting log contains a blank or damaged row.' }
            $parts = $line.Split(';')
            $existingSequence = 0
            $existingExit = 0
            if ($parts.Count -ne 4 -or -not [int]::TryParse($parts[0], [ref]$existingSequence) -or -not [int]::TryParse($parts[3], [ref]$existingExit)) {
                throw "Accounting log contains a malformed row: $line"
            }
            if ($existingSequence -ne ($records.Count + 1)) { throw "Accounting log sequence is not continuous at row $($records.Count + 1)." }
            if ($parts[1] -notmatch '^[a-z0-9_]+$' -or $parts[2] -notin @('headless', 'powershell') -or $existingExit -lt 0) {
                throw "Accounting log contains an invalid row: $line"
            }
            if (@($records | Where-Object { $_.Name -ceq $parts[1] }).Count -gt 0) { throw "Accounting log contains duplicate name: $($parts[1])" }
            $records.Add([pscustomobject]@{ Name = $parts[1] })
        }
    }
    if ($Sequence -ne ($records.Count + 1)) { throw "Recorder sequence mismatch: expected $($records.Count + 1), received $Sequence." }
    if (@($records | Where-Object { $_.Name -ceq $Name }).Count -gt 0) { throw "Duplicate recorder name: $Name" }

    $record = '{0};{1};{2};{3}' -f $Sequence, $Name, $ExecutionType, $ProcessExit
    [IO.File]::AppendAllText($fullPath, ($record + [Environment]::NewLine), $utf8)
    Write-Output ("[smoke] additional_check={0} name={1} execution_type={2} process_exit={3} cumulative={0}" -f $Sequence, $Name, $ExecutionType, $ProcessExit)
} catch {
    [Console]::Error.WriteLine("[smoke] additional_check_record_failed sequence=$Sequence name=$Name error=$($_.Exception.Message)")
    exit 1
}
