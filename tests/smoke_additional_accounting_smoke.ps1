param(
    [string]$ValidateLogPath,
    [int]$ExpectedCount = 14,
    [int]$ReportedCount = 14,
    [int]$ExpectedSuiteExit = 0,
    [switch]$FixtureMode
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

function Assert-AccountingLog {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$Count,
        [Parameter(Mandatory = $true)][int]$SuiteExit,
        [string[]]$ExpectedNames,
        [switch]$FixtureValidation
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Accounting log is missing: $Path" }
    $lines = [IO.File]::ReadAllLines($Path, $utf8)
    $records = New-Object 'System.Collections.Generic.List[object]'
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { throw 'Accounting log contains a blank or damaged row.' }
        $parts = $line.Split(';')
        if ($parts.Count -ne 4) { throw "Malformed accounting record: $line" }
        $sequence = 0
        $exitCode = 0
        if (-not [int]::TryParse($parts[0], [ref]$sequence) -or $sequence -lt 1) { throw "Invalid cumulative number in accounting record: $line" }
        if (-not [int]::TryParse($parts[3], [ref]$exitCode) -or $exitCode -lt 0) { throw "Invalid process exit code in accounting record: $line" }
        if ($parts[1] -notmatch '^[a-z0-9_]+$') { throw "Invalid recorder name: $($parts[1])" }
        if ($parts[2] -notin @('headless', 'powershell')) { throw "Invalid execution type: $($parts[2])" }
        $records.Add([pscustomobject]@{ Sequence = $sequence; Name = $parts[1]; Type = $parts[2]; Exit = $exitCode })
    }

    if ($records.Count -ne $Count) { throw "additional_checks mismatch: expected $Count recorder completions, found $($records.Count)." }
    for ($index = 0; $index -lt $records.Count; $index++) {
        if ($records[$index].Sequence -ne ($index + 1)) { throw "Cumulative number mismatch at row $($index + 1): found $($records[$index].Sequence)." }
        if ($records[$index].Name -notmatch '^[a-z0-9_]+$') { throw "Invalid recorder name: $($records[$index].Name)" }
        if ($records[$index].Type -notin @('headless', 'powershell')) { throw "Invalid execution type: $($records[$index].Type)" }
        if (-not $FixtureValidation -and $records[$index].Type -ne $(if ($records[$index].Name -in @('editor_executable_parse_smoke', 'animation_candidate_coverage_smoke')) { 'powershell' } else { 'headless' })) {
            throw "Execution type mismatch for $($records[$index].Name): found $($records[$index].Type)."
        }
        if ($records[$index].Exit -lt 0) { throw "Invalid negative process exit code for $($records[$index].Name)." }
    }
    $duplicates = @($records | Group-Object Name | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) { throw ('Duplicate recorder names: ' + (($duplicates | ForEach-Object Name) -join ', ')) }
    if ($ExpectedNames) {
        if ($records.Count -ne $ExpectedNames.Count) { throw 'Expected recorder name inventory has the wrong length.' }
        for ($index = 0; $index -lt $ExpectedNames.Count; $index++) {
            if ($records[$index].Name -cne $ExpectedNames[$index]) { throw "Recorder order mismatch at cumulative $($index + 1): expected '$($ExpectedNames[$index])', found '$($records[$index].Name)'." }
        }
    }
    if (-not $FixtureValidation) {
        if ($records.Count -ne 14) { throw "Production additional-check ledger must contain exactly 14 records; found $($records.Count)." }
        $headlessCount = @($records | Where-Object Type -ceq 'headless').Count
        $powershellCount = @($records | Where-Object Type -ceq 'powershell').Count
        if ($headlessCount -ne 12 -or $powershellCount -ne 2) { throw "Execution type totals mismatch: expected headless=12,powershell=2; found headless=$headlessCount,powershell=$powershellCount." }
    }
    $hasFailures = @($records | Where-Object Exit -ne 0).Count -gt 0
    if ($hasFailures -and $SuiteExit -ne 1) { throw 'A nonzero recorder exit must make the suite exit nonzero.' }
    if ($SuiteExit -notin @(0, 1)) { throw "Unexpected suite exit code: $SuiteExit" }
    return ,$records.ToArray()
}

if ($ValidateLogPath) {
    $expectedNames = @(
        'attack2_candidate_motion_review_smoke', 'player_attack3_startup_review_smoke',
        'player_animation_state_matrix_smoke', 'player_attack1_startup_safe_smoke',
        'player_attack3_startup_safe_smoke', 'player_run_stride_safe_smoke',
        'player_run_cycle_review_smoke', 'm5_art_review_board_smoke',
        'player_run_stride_v2_safe_smoke', 'player_run_v3_antiphase_smoke',
        'player_jump_rise_safe_smoke', 'player_skill1_rush_safe_smoke',
        'editor_executable_parse_smoke', 'animation_candidate_coverage_smoke'
    )
    if ($FixtureMode) { $expectedNames = @('fixture_pass', 'fixture_failure', 'fixture_timeout', 'fixture_powershell_failure') }
    if (-not $FixtureMode -and ($ExpectedCount -ne 14 -or $ReportedCount -lt 0)) { throw 'Production accounting requires the fixed 14-record inventory and a nonnegative reported total.' }
    $records = Assert-AccountingLog -Path $ValidateLogPath -Count $ExpectedCount -SuiteExit $ExpectedSuiteExit -ExpectedNames $expectedNames -FixtureValidation:$FixtureMode
    if ($ReportedCount -ne $records.Count) { throw "Final additional_checks mismatch: batch summary variable is $ReportedCount, actual completed recorder count is $($records.Count)." }
    if ($FixtureMode) {
        $fixtureExits = @(0, 7, 124, 9)
        for ($index = 0; $index -lt $fixtureExits.Count; $index++) {
            if ($records[$index].Exit -ne $fixtureExits[$index]) { throw "Fixture process exit mismatch at cumulative $($index + 1): expected $($fixtureExits[$index]), found $($records[$index].Exit)." }
        }
        if ($records[0].Type -ne 'headless' -or $records[1].Type -ne 'headless' -or $records[2].Type -ne 'headless' -or $records[3].Type -ne 'powershell') { throw 'Fixture execution types do not match the four configured scenarios.' }
    }
    Write-Output "smoke_additional_accounting_smoke: verified additional_checks=$($records.Count), unique_names=$($records.Count), ordered cumulative numbers, execution types, process exits, suite_exit=$ExpectedSuiteExit"
    exit 0
}

$root = Split-Path -Parent $PSScriptRoot
$suitePath = Join-Path $root 'tools\smoke_suite.cmd'
$recorderPath = Join-Path $root 'tools\record_smoke_additional_check.ps1'
$outputPath = Join-Path ([IO.Path]::GetTempPath()) ('beltscroll_accounting_fixture_output_' + [Guid]::NewGuid().ToString('N') + '.log')
$fixturePassed = $false
try {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/d /c ""' + $suitePath + '" --accounting-fixture"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'cmd.exe fixture process did not start.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    [IO.File]::WriteAllText($outputPath, ($stdout + $stderr), $utf8)
    if ($process.ExitCode -ne 0) { throw "cmd.exe fixture failed with exit $($process.ExitCode). Output: $stdout$stderr" }

    $outputLines = [IO.File]::ReadAllLines($outputPath, [Text.Encoding]::UTF8)
    $records = @($outputLines | Where-Object { $_ -match '^\[smoke\] additional_check=' })
    $expected = @(
        [pscustomobject]@{ Name = 'fixture_pass'; Type = 'headless'; Exit = 0 },
        [pscustomobject]@{ Name = 'fixture_failure'; Type = 'headless'; Exit = 7 },
        [pscustomobject]@{ Name = 'fixture_timeout'; Type = 'headless'; Exit = 124 },
        [pscustomobject]@{ Name = 'fixture_powershell_failure'; Type = 'powershell'; Exit = 9 }
    )
    if ($records.Count -ne $expected.Count) { throw "cmd.exe fixture recorder output count mismatch: expected $($expected.Count), found $($records.Count). Full output: $stdout$stderr" }
    for ($index = 0; $index -lt $expected.Count; $index++) {
        $pattern = '^\[smoke\] additional_check=' + ($index + 1) + ' name=' + [regex]::Escape($expected[$index].Name) + ' execution_type=' + $expected[$index].Type + ' process_exit=' + $expected[$index].Exit + ' cumulative=' + ($index + 1) + '$'
        if ($records[$index] -notmatch $pattern) { throw "cmd.exe fixture log mismatch at row $($index + 1): $($records[$index])" }
    }
    $summary = @($outputLines | Where-Object { $_ -match '^\[smoke\] additional_checks=' })
    if ($summary.Count -ne 1 -or $summary[0] -notmatch '^\[smoke\] additional_checks=4 execution_types=headless,powershell additional_checks_process_exit=1$') { throw 'cmd.exe fixture must print one summary with the exact recorder total and failed suite result.' }
    $suiteSummary = @($outputLines | Where-Object { $_ -match '^\[smoke\] suite process_exit=' })
    if ($suiteSummary.Count -ne 1 -or $suiteSummary[0] -notmatch '^\[smoke\] suite process_exit=1 elapsed_seconds=') { throw 'cmd.exe fixture must print exactly one suite summary with the expected result.' }
    if (@($outputLines | Where-Object { $_ -ceq '[smoke] accounting_fixture: all checks passed' }).Count -ne 1) { throw 'cmd.exe fixture did not emit exactly one final success marker.' }

    $fixtureNames = @('fixture_pass', 'fixture_failure', 'fixture_timeout', 'fixture_powershell_failure')
    $fixtureLedger = @(
        '1;fixture_pass;headless;0',
        '2;fixture_failure;headless;7',
        '3;fixture_timeout;headless;124',
        '4;fixture_powershell_failure;powershell;9'
    )
    $badLedgerPath = Join-Path ([IO.Path]::GetTempPath()) ('beltscroll_accounting_bad_' + [Guid]::NewGuid().ToString('N') + '.log')
    try {
        $missingRejected = $false
        try { [void](Assert-AccountingLog -Path ($badLedgerPath + '.missing') -Count 4 -SuiteExit 1 -ExpectedNames $fixtureNames -FixtureValidation) } catch { $missingRejected = $true }
        if (-not $missingRejected) { throw 'Accounting validator accepted a missing ledger.' }
        foreach ($badCase in @(
            [pscustomobject]@{ Name = 'missing'; Lines = $fixtureLedger[0..2] },
            [pscustomobject]@{ Name = 'duplicate'; Lines = @($fixtureLedger[0], $fixtureLedger[1], $fixtureLedger[2], '4;fixture_pass;headless;0') },
            [pscustomobject]@{ Name = 'sequence_gap'; Lines = @($fixtureLedger[0], '3;fixture_failure;headless;7', $fixtureLedger[2], $fixtureLedger[3]) },
            [pscustomobject]@{ Name = 'damaged'; Lines = @($fixtureLedger[0], '2;fixture_failure;headless', $fixtureLedger[2], $fixtureLedger[3]) }
        )) {
            [IO.File]::WriteAllLines($badLedgerPath, [string[]]$badCase.Lines, $utf8)
            $rejected = $false
            try { [void](Assert-AccountingLog -Path $badLedgerPath -Count 4 -SuiteExit 1 -ExpectedNames $fixtureNames -FixtureValidation) } catch { $rejected = $true }
            if (-not $rejected) { throw "Accounting validator accepted $($badCase.Name) ledger damage." }
        }
        [IO.File]::WriteAllBytes($badLedgerPath, [byte[]]@(0x31, 0x3B, 0xFF, 0x0A))
        $invalidUtf8Rejected = $false
        try { [void](Assert-AccountingLog -Path $badLedgerPath -Count 4 -SuiteExit 1 -ExpectedNames $fixtureNames -FixtureValidation) } catch { $invalidUtf8Rejected = $true }
        if (-not $invalidUtf8Rejected) { throw 'Accounting validator accepted a ledger containing invalid UTF-8.' }

        $writeFailureOutput = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $recorderPath -LogPath ([IO.Path]::GetTempPath()) -Sequence 1 -Name fixture_write_failure -ExecutionType headless -ProcessExit 0 2>&1
        if ($LASTEXITCODE -eq 0) { throw 'Recorder did not fail when the ledger path was a directory.' }
        if (@($writeFailureOutput | Where-Object { $_ -match 'additional_check_record_failed' }).Count -ne 1) { throw 'Recorder write failure did not emit its diagnostic.' }
    } finally {
        Remove-Item -LiteralPath $badLedgerPath -Force -ErrorAction SilentlyContinue
    }

    Write-Output 'cmd.exe accounting fixture trace:'
    foreach ($line in $records) { Write-Output $line }
    Write-Output $summary[0]
    Write-Output $suiteSummary[0]
    Write-Output 'smoke_additional_accounting_smoke: normal, failure, timeout, PowerShell failure, missing, duplicate, damaged, invalid UTF-8, and write-failure cases verified; suite summaries emitted once'
    Write-Output 'smoke_additional_accounting_smoke: all checks passed'
    $fixturePassed = $true
    exit 0
} finally {
    if ($fixturePassed) {
        Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
    } else {
        [Console]::Error.WriteLine("smoke_additional_accounting_smoke: fixture diagnostics preserved at $outputPath")
    }
}
