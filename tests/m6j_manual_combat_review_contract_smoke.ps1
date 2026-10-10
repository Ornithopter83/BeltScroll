[CmdletBinding()]
param([string]$ProjectRoot = '')

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$runnerPath = Join-Path $ProjectRoot 'tools/run_m6j_manual_combat_editor_review.ps1'
$guidePath = Join-Path $ProjectRoot 'docs/review/m6j_manual_combat_editor_gate.md'
foreach ($path in @($runnerPath, $guidePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "필수 M6J 검수 파일이 없습니다: $path" }
}

$source = Get-Content -Encoding UTF8 -Raw -LiteralPath $runnerPath
$guide = Get-Content -Encoding UTF8 -Raw -LiteralPath $guidePath
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "검수 실행기 PowerShell 구문 오류: $($parseErrors[0].Message)" }

$requiredRunnerTokens = @(
    'godot_j_three_combo', 'godot_num4', 'godot_num5', 'godot_enemy_counterattack',
    'godot_hit_stun', 'godot_recovery', 'godot_restart_r', 'editor_save_value',
    'editor_arena_button_launch', 'editor_saved_value_applied', 'BLOCKED_UNVERIFIED',
    'physical-keyboard', 'physical-mouse', 'human-visual-observation',
    'Get-FileHash', 'SHA256', 'evidenceSha256', 'targetCommitSha', 'Test-PngFile', '89-50-4E-47-0D-0A-1A-0A',
    'IsInputRedirected', 'IsOutputRedirected', 'I_VISUALLY_APPROVE',
    'automatedInputAccepted = $false', 'automatedCaptureAccepted = $false',
    'BeltScrollEditor.exe', '전투 연습장 실행'
)
foreach ($token in $requiredRunnerTokens) {
    if (-not $source.Contains($token)) { throw "실행기에 필요한 계약이 없습니다: $token" }
}

$requiredGuideTokens = @(
    'F6', '물리 J', '3콤보', 'Num4', 'Num5', '적 반격', '경직', '복귀', 'R 재시작',
    '저장', '전투 연습장 실행', 'SHA-256', 'BLOCKED_UNVERIFIED', '자동 입력', '자동 캡처', '시각 승인'
)
foreach ($token in $requiredGuideTokens) {
    if (-not $guide.Contains($token)) { throw "안내서에 필요한 검수 항목이 없습니다: $token" }
}

$forbiddenAutomation = @('SendKeys', 'keybd_event', 'mouse_event', 'CopyFromScreen', 'PrintWindow', 'BitBlt', 'Start-Process')
foreach ($token in $forbiddenAutomation) {
    if ($source.Contains($token)) { throw "사람 검수 실행기에 자동 입력/캡처/실행 코드를 넣을 수 없습니다: $token" }
}

Write-Host 'M6J manual combat review contract smoke passed.'
exit 0
