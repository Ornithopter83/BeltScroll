$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$root = Split-Path -Parent $PSScriptRoot
$suitePath = Join-Path $root 'tools\smoke_suite.cmd'
$suite = [IO.File]::ReadAllLines($suitePath, [Text.Encoding]::UTF8)
$failures = New-Object 'System.Collections.Generic.List[string]'

# This ordered inventory protects the established sequence as well as new coverage.
$expected = @(
    'headless:movement_smoke'
    'headless:ground_dust_smoke'
    'headless:player_combat_smoke'
    'headless:player_skill_smoke'
    'headless:player_pose_blender_smoke'
    'headless:training_dummy_smoke'
    'headless:forest_raider_smoke'
    'headless:raider_spacing_stress_smoke'
    'headless:raider_visual_animator_smoke'
    'headless:combat_hud_smoke'
    'headless:stage_tools_smoke'
    'headless:stage_integration_smoke'
    'headless:game_session_smoke'
    'headless:game_session_navigation_smoke'
    'headless:game_pause_smoke'
    'headless:gamepad_input_smoke'
    'headless:player_keypose_pipeline_smoke'
    'headless:player_keypose_relayout_smoke'
    'headless:player_reference_review_smoke'
    'headless:art_review_smoke'
    'headless:player_art_normalize_smoke'
    'headless:player_reference_compare_smoke'
    'headless:player_v5_art_smoke'
    'headless:forest_raider_matte_smoke'
    'headless:player_v5_final_matte_smoke'
    'headless:forest_raider_final_matte_smoke'
    'headless:player_v6_art_smoke'
    'headless:player_v7_ink_smoke'
    'headless:player_attack1_final_matte_smoke'
    'headless:player_attack1_edge_v2_smoke'
    'headless:player_attack1_contour_smoke'
    'headless:player_attack2_art_smoke'
    'headless:player_attack2_v2_art_smoke'
    'headless:player_attack2_v4_art_smoke'
    'headless:player_attack3_art_smoke'
    'headless:player_attack3_contour_smoke'
    'headless:combat_audio_smoke'
    'window:combat_art_overlap_smoke'
    'window:combat_art_candidate_capture_smoke'
    'window:forest_raider_art_integration_smoke'
    'window:player_art_integration_smoke'
    'window:player_visual_animator_smoke'
    'window:player_attack_pose_integration_smoke'
    'window:camera_boundary_window_smoke'
    'window:display_num_input_window_smoke'
    'window:gameplay_window_render_smoke'
    'window:combat_live_session_window_smoke'
    'window:raider_healthbar_window_smoke'
    'window:gameplay_endings_window_smoke'
    'headless:player_animation_bank_smoke'
    'headless:player_attack2_inbetween_safe_smoke'
    'headless:player_attack2_contact_v5_smoke'
    'headless:player_attack2_contact_v6_smoke'
    'headless:combat_vfx_visual_smoke'
    'headless:raider_attack_pose_window_smoke'
    'headless:player_attack2_contact_v6_safe_smoke'
    'headless:attack2_candidate_motion_review_smoke'
    'headless:player_attack3_startup_review_smoke'
    'headless:player_animation_state_matrix_smoke'
    'headless:player_attack1_startup_safe_smoke'
    'headless:player_attack3_startup_safe_smoke'
    'headless:player_run_stride_safe_smoke'
    'headless:player_run_cycle_review_smoke'
    'headless:m5_art_review_board_smoke'
)

$suiteLines = New-Object 'System.Collections.Generic.List[string]'
foreach ($line in $suite) {
    if ($line -match '^:run_smoke\s*$') { break }
    if ($line -match '^call :run_smoke\s+([a-z0-9_]+)') {
        $suiteLines.Add("headless:$($Matches[1])")
    } elseif ($line -match '^call :run_window_smoke\s+([a-z0-9_]+)') {
        $suiteLines.Add("window:$($Matches[1])")
    } elseif ($line -match '^call :run_gameplay_endings_window_smoke\s*$') {
        $suiteLines.Add('window:gameplay_endings_window_smoke')
    }
}

$actual = @($suiteLines)
$duplicates = @($actual | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) {
    $failures.Add('Duplicate smoke entries: ' + (($duplicates | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '))
}
if ($actual.Count -ne $expected.Count) {
    $failures.Add("Smoke inventory count differs: expected $($expected.Count), found $($actual.Count).")
}
$limit = [Math]::Min($actual.Count, $expected.Count)
for ($index = 0; $index -lt $limit; $index++) {
    if ($actual[$index] -cne $expected[$index]) {
        $failures.Add("Smoke inventory/order mismatch at position $($index + 1): expected '$($expected[$index])', found '$($actual[$index])'.")
    }
}

$required = @(
    'headless:player_animation_bank_smoke'
    'headless:raider_attack_pose_window_smoke'
    'headless:player_attack2_inbetween_safe_smoke'
    'headless:player_attack2_contact_v5_smoke'
    'headless:player_attack2_contact_v6_smoke'
    'headless:combat_vfx_visual_smoke'
    'headless:player_attack2_contact_v6_safe_smoke'
    'headless:attack2_candidate_motion_review_smoke'
    'headless:player_attack3_startup_review_smoke'
    'headless:player_animation_state_matrix_smoke'
    'headless:player_attack1_startup_safe_smoke'
    'headless:player_attack3_startup_safe_smoke'
    'headless:player_run_stride_safe_smoke'
    'headless:player_run_cycle_review_smoke'
    'headless:m5_art_review_board_smoke'
)
foreach ($entry in $required) {
    if (@($actual | Where-Object { $_ -ceq $entry }).Count -ne 1) {
        $failures.Add("Required regression check must appear exactly once: $entry")
    }
}

foreach ($entry in $expected) {
    $parts = $entry.Split(':', 2)
    $testPath = Join-Path $PSScriptRoot ($parts[1] + '.gd')
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
        $failures.Add("Registered smoke script is missing: $testPath")
    }
}

$joinedSuite = $suite -join "`n"
$recordedRegressionCalls = @($suite | Where-Object { $_ -match '^call :record_additional_check\s+' }).Count
if ($recordedRegressionCalls -ne 8) {
    $failures.Add("Expected 8 appended Godot checks in the additional-check recorder, found $recordedRegressionCalls.")
}
$parserGateRegistered = $joinedSuite.Contains('call :run_editor_executable_parse') -and
    $joinedSuite.Contains('editor_executable_parse_smoke.ps1') -and
    $joinedSuite.Contains('ADDITIONAL_TYPES=headless,powershell')
if (-not $parserGateRegistered) {
    $failures.Add('The ninth additional verification must be the separately reported Windows PowerShell parser gate.')
}
$checks = @(
    @($joinedSuite.Contains('set "SMOKE_ARGS=--headless --path ""%PROJECT_DIR%"" --script ""res://tests/%SMOKE_NAME%.gd"""'), 'Headless tests must invoke their Godot SceneTree scripts with --headless.'),
    @($joinedSuite.Contains('set "SMOKE_ARGS=--path ""%PROJECT_DIR%"" --script ""res://tests/%SMOKE_NAME%.gd"""'), 'Window tests must invoke their Godot SceneTree scripts without --headless.'),
    @($joinedSuite.Contains('set "SUCCESS_MARKER=%SMOKE_NAME%: all checks passed"'), 'Headless tests must default to the registered script-name success marker.'),
    @($joinedSuite.Contains('set "SMOKE_TIMEOUT=120"') -and $joinedSuite.Contains('call :run_bounded %SMOKE_TIMEOUT%'), 'Headless checks must have a bounded default timeout.'),
    @($joinedSuite.Contains('call :run_bounded 240'), 'Window checks must have a bounded timeout.'),
    @($joinedSuite.Contains('call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "%SUCCESS_MARKER%" "%ALLOW_MODE%"'), 'Headless checks must verify exit status, success marker, and diagnostics.'),
    @($joinedSuite.Contains('call "%PROBE%" "%RUN_LOG%" "%RUN_EXIT%" "%SMOKE_NAME%: all checks passed"'), 'Window checks must verify exit status and success marker.'),
    @($joinedSuite.Contains('copy /y "%RUN_LOG%" "%FAILED_LOG_CURRENT%"'), 'Every failed check must preserve its own diagnostic log.'),
    @($joinedSuite.Contains('Actual process exit code:') -and $joinedSuite.Contains('RESULT: TIMEOUT'), 'The bounded runner must record real exit status and timeout failures.')
    @($joinedSuite.Contains('set "ADDITIONAL_CHECKS=0"') -and $joinedSuite.Contains('set /a ADDITIONAL_CHECKS+=1') -and $joinedSuite.Contains('additional_checks=%ADDITIONAL_CHECKS%') -and $joinedSuite.Contains('ADDITIONAL_TYPES=headless,powershell'), 'Suite summary must record appended Godot checks and the PowerShell parser gate.')
    @($joinedSuite.Contains('additional_check=%~1 execution_type=headless process_exit=%RUN_EXIT%'), 'Each appended regression check must log its execution type and actual process exit code.')
    @($joinedSuite.Contains('additional_checks_process_exit=%~1'), 'Suite summary must record the overall process exit code alongside added-check totals.')
    @($joinedSuite.Contains('call :record_additional_check player_attack1_startup_safe_smoke') -and $joinedSuite.Contains('call :record_additional_check player_attack3_startup_safe_smoke') -and $joinedSuite.Contains('call :record_additional_check player_run_stride_safe_smoke') -and $joinedSuite.Contains('call :record_additional_check player_run_cycle_review_smoke') -and $joinedSuite.Contains('call :record_additional_check m5_art_review_board_smoke'), 'All five newly registered regressions must contribute to the additional-check total.')
    @($joinedSuite.Contains('if /I "%~1"=="--rebuild-live-review-captures" goto live_review_captures'), 'Actual review capture regeneration must require the explicit command-line mode.')
    @($joinedSuite.Contains('Rebuilding live review captures; execution_type=window_capture,visual_approval=not_granted'), 'Capture regeneration must identify Window capture execution and leave visual approval ungranted.')
    @($joinedSuite.Contains('res://tools/capture_attack2_candidate_motion_review.gd') -and $joinedSuite.Contains('res://tools/capture_player_animation_state_matrix.gd'), 'The explicit mode must invoke both real Window capture tools.')
    @($joinedSuite.Contains('--headless --path') -and $joinedSuite.Contains('res://tools/build_player_attack3_startup_review.gd'), 'Startup comparison generation must be identified separately from real Window capture.')
    @($joinedSuite.Contains('editor_executable_parse_smoke.ps1') -and $joinedSuite.Contains('call :run_bounded 45'), 'The Windows PowerShell parser check must run with a bounded timeout.')
)
foreach ($check in $checks) {
    if (-not $check[0]) { $failures.Add($check[1]) }
}

$explicitTimeouts = @{
    'player_animation_bank_smoke' = 120
    'raider_attack_pose_window_smoke' = 120
    'player_attack2_inbetween_safe_smoke' = 120
    'player_attack2_contact_v5_smoke' = 180
    'player_attack2_contact_v6_smoke' = 180
    'combat_vfx_visual_smoke' = 120
    'player_attack2_contact_v6_safe_smoke' = 180
    'attack2_candidate_motion_review_smoke' = 180
    'player_attack3_startup_review_smoke' = 120
    'player_animation_state_matrix_smoke' = 120
    'player_attack1_startup_safe_smoke' = 120
    'player_attack3_startup_safe_smoke' = 120
    'player_run_stride_safe_smoke' = 120
    'player_run_cycle_review_smoke' = 120
    'm5_art_review_board_smoke' = 120
}
foreach ($name in $explicitTimeouts.Keys) {
    $timeoutLine = "if /I `"%SMOKE_NAME%`"==`"$name`" set `"SMOKE_TIMEOUT=$($explicitTimeouts[$name])`""
    if (-not $joinedSuite.Contains($timeoutLine)) {
        $failures.Add("Explicit timeout is missing or incorrect for ${name}: $($explicitTimeouts[$name]) seconds.")
    }
}

$customMarkers = @(
    'player_attack2_inbetween_safe_smoke: all checks passed; visual approval pending',
    'player_attack2_contact_v5_smoke: all mechanical checks passed; visual approval remains human review',
    'player_attack2_contact_v6_smoke: mechanical checks passed; no image approval is implied',
    'player_attack2_contact_v6_safe_smoke: mechanical checks passed; visual approval remains pending'
	'attack2_candidate_motion_review_smoke: all checks passed; visual motion judgment remains pending'
    'player_animation_state_matrix_smoke: state coverage and capture evidence present; no art completeness claim'
    'player_attack1_startup_safe_smoke: mechanical checks passed; human visual approval is pending'
    'player_attack3_startup_safe_smoke: mechanical checks passed; human visual approval remains pending'
    'player_run_stride_safe_smoke: mechanical checks passed; human visual approval remains required'
    'player_run_cycle_review_smoke: isolated v1/v2 gate and Window evidence are present'
    'm5_art_review_board_smoke: all checks passed; human art approval remains independent'
)
foreach ($marker in $customMarkers) {
    if (-not $joinedSuite.Contains($marker)) { $failures.Add("Registered success marker is missing: $marker") }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { [Console]::Error.WriteLine("smoke_suite_coverage_smoke: FAIL: $failure") }
    exit 1
}

Write-Output "smoke_suite_coverage_smoke: inventory/order verified ($($actual.Count) Godot checks; 56 established retained, 8 appended Godot checks; 1 PowerShell parser gate; 9 added verifications total; no duplicates); execution routes, timeouts, markers, and failure logs verified"
Write-Output 'smoke_suite_coverage_smoke: all checks passed'
exit 0
