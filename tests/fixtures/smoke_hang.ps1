param([Parameter(Mandatory = $true)][string]$ChildPidPath)

$child = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
    -ArgumentList '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 600"' `
    -WindowStyle Hidden -PassThru
[IO.File]::WriteAllText($ChildPidPath, [string]$child.Id, [Text.Encoding]::ASCII)

# Deliberately produce no output and never exit; the bounded runner must time out.
while ($true) { Start-Sleep -Seconds 30 }
