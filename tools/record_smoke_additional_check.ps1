param(
    [Parameter(Mandatory = $true)][string]$LogPath,
    [Parameter(Mandatory = $true)][int]$Sequence,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][ValidateSet('headless', 'powershell')][string]$ExecutionType,
    [Parameter(Mandatory = $true)][int]$ProcessExit
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
if ($Sequence -lt 1) { throw 'Recorder sequence must be positive.' }
if ($Name -notmatch '^[a-z0-9_]+$') { throw "Invalid recorder name: $Name" }
if ($ProcessExit -lt 0) { throw "Invalid recorder process exit code: $ProcessExit" }
$record = '{0};{1};{2};{3}' -f $Sequence, $Name, $ExecutionType, $ProcessExit
[IO.File]::AppendAllText([IO.Path]::GetFullPath($LogPath), ($record + [Environment]::NewLine), $utf8)
Write-Output ("[smoke] additional_check={0} name={1} execution_type={2} process_exit={3} cumulative={0}" -f $Sequence, $Name, $ExecutionType, $ProcessExit)
