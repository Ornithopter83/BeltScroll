$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$root = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $root 'tools\run_m6e_manual_acceptance.ps1'
$gatePath = Join-Path $root 'docs\review\m6e_manual_acceptance_handoff.md'
$runner = [IO.File]::ReadAllText($runnerPath, [Text.Encoding]::UTF8)
$gate = [IO.File]::ReadAllText($gatePath, [Text.Encoding]::UTF8)

foreach ($marker in @('Console]::IsInputRedirected','UserInteractive','BLOCKED_UNVERIFIED','exit 2','capture_manual_input_audit.gd','capture_m6d_full_playthrough.gd','--manual','1920x1080','--fullscreen','physical-keyboard','human-observed','human-gui','Num$key','boss-encounter','boss-defeated','restart','player-defeat','apply-to-game','evidenceHashes','Get-FileHash','automaticPaths','m6d_full_playthrough_evidence.png','manual-review.json','m6d_manual_acceptance.json','physicalOriginProvenByLog = $false','automatedInputOrCaptureSubstitutesForHumanAcceptance = $false','selfTestUsedAsHumanEvidence = $false')) {
    if ($runner -notmatch [regex]::Escape($marker)) { throw "Runner contract is missing: $marker" }
}
foreach ($forbidden in @('Input.parse_input_event','SendKeys','SendInput','--self-test','--gui-acceptance')) {
    if ($runner -match [regex]::Escape($forbidden)) { throw "Runner must not simulate or self-test human input: $forbidden" }
}
foreach ($marker in @('Num1~9','실제 키보드','전체화면','3배','타이틀','보스','승리','패배','재시작','저장','재열기','게임 재적용','BLOCKED_UNVERIFIED','다음 행동','자동 캡처')) {
    if ($gate -notmatch [regex]::Escape($marker)) { throw "Handoff is missing: $marker" }
}

# A redirected invocation must block before it attempts to resolve or start Godot.
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('m6e_manual_acceptance_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tempRoot)
try {
    $shell = Join-Path $PSHOME 'powershell.exe'
    $args = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$runnerPath,'-ProjectRoot',$root,'-GodotPath',(Join-Path $tempRoot 'must-not-be-started.exe'),'-OutputDirectory',$tempRoot) | ForEach-Object { '"' + ([string]$_).Replace('"','\"') + '"' }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $shell
    $startInfo.Arguments = $args -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $code = $process.ExitCode
    $output = @($stdout,$stderr)
    if ($code -ne 2) { throw "Redirected invocation must exit 2; got $code. $($output -join "`n")" }
    $reportPath = Join-Path $tempRoot 'm6d_manual_acceptance.json'
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Blocked invocation did not write a manual acceptance report.' }
    if (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'manual-review.json') -PathType Leaf)) { throw 'Blocked invocation did not write the compatible manual-review.json record.' }
    $report = Get-Content -Encoding UTF8 -Raw -LiteralPath $reportPath | ConvertFrom-Json
    if ($report.status -ne 'BLOCKED_UNVERIFIED' -or $report.physicalKeyboard.status -ne 'NOT_VERIFIED' -or
        $report.display.status -ne 'NOT_VERIFIED' -or $report.editorGuiRoundtrip.status -ne 'NOT_VERIFIED' -or
        $report.physicalOriginProvenByLog -ne $false -or $report.automatedInputOrCaptureSubstitutesForHumanAcceptance -ne $false -or
        $report.selfTestUsedAsHumanEvidence -ne $false -or $report.nextActions.Count -lt 1) {
        throw 'Blocked report must preserve unverified status, separation of evidence, and next actions.'
    }
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'm6e_manual_acceptance_contract_smoke: all checks passed'
