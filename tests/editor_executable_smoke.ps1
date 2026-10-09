param(
    [string]$EditorPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\BeltScrollEditor.exe'),
    [int]$SelfTestTimeoutSeconds = 120,
    [switch]$AutomatedOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$script:Results = New-Object System.Collections.Generic.List[object]
$script:ManualAcceptanceBlocked = $false
$script:ManualAcceptanceSkipped = $false

function Add-Result([string]$Name, [bool]$Passed, [string]$Details) {
    $script:Results.Add([pscustomobject]@{
        check = $Name
        passed = $Passed
        details = $Details
        category = if ($Name -in @('--self-test 완료', '--gui-acceptance 완료', 'EXE 존재', '스크립트 실행')) { 'automated' } else { 'manual' }
        checkedAt = (Get-Date).ToString('o')
    })
    $state = if ($Passed) { 'PASS' } else { 'FAIL' }
    Write-Output ('[{0}] {1}: {2}' -f $state, $Name, $Details)
}

function Confirm-Gate([string]$Name, [string]$Instruction) {
    Write-Output ''
    Write-Output $Instruction
    do {
        $answer = Read-Host '확인 결과를 입력하세요 (Y/N)'
    } while ($answer -notmatch '^(?i:y|n)$')
    $passed = $answer -match '^(?i:y)$'
    Add-Result $Name $passed $(if ($passed) { '작업자가 확인함' } else { '작업자가 실패 또는 미확인으로 표시함' })
}

function Start-EditorProcess([string[]]$Arguments, [string]$WorkingDirectory, [string]$StdoutPath, [string]$StderrPath) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $resolvedEditor
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    $startInfo.RedirectStandardOutput = -not [string]::IsNullOrEmpty($StdoutPath)
    $startInfo.RedirectStandardError = -not [string]::IsNullOrEmpty($StderrPath)
    $quotedArguments = foreach ($argument in $Arguments) {
        '"' + ([string]$argument).Replace('"', '\"') + '"'
    }
    $startInfo.Arguments = (@($quotedArguments) -join ' ')
    if ($startInfo.RedirectStandardOutput) { $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8 }
    if ($startInfo.RedirectStandardError) { $startInfo.StandardErrorEncoding = [Text.Encoding]::UTF8 }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Process.Start returned false.' }
    $stdoutTask = if ($startInfo.RedirectStandardOutput) { $process.StandardOutput.ReadToEndAsync() } else { $null }
    $stderrTask = if ($startInfo.RedirectStandardError) { $process.StandardError.ReadToEndAsync() } else { $null }
    return [pscustomobject]@{ Process = $process; StdoutTask = $stdoutTask; StderrTask = $stderrTask }
}

function Save-ProcessOutput($Started, [string]$StdoutPath, [string]$StderrPath) {
    if ($null -ne $Started.StdoutTask) { [IO.File]::WriteAllText($StdoutPath, $Started.StdoutTask.GetAwaiter().GetResult(), (New-Object System.Text.UTF8Encoding($false))) }
    if ($null -ne $Started.StderrTask) { [IO.File]::WriteAllText($StderrPath, $Started.StderrTask.GetAwaiter().GetResult(), (New-Object System.Text.UTF8Encoding($false))) }
}

$resolvedEditor = [IO.Path]::GetFullPath($EditorPath)
if (-not (Test-Path -LiteralPath $resolvedEditor -PathType Leaf)) {
    Add-Result 'EXE 존재' $false ("파일 없음: {0}" -f $resolvedEditor)
    throw 'dist/BeltScrollEditor.exe가 없습니다. 배포 인수 검증을 완료할 수 없습니다.'
}
Add-Result 'EXE 존재' $true $resolvedEditor

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('BeltScrollEditorAcceptance_' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$badJsonPath = Join-Path $testRoot 'malformed-editor-data.json'
$selfOut = Join-Path $testRoot 'self-test.stdout.txt'
$selfErr = Join-Path $testRoot 'self-test.stderr.txt'
$reportPath = Join-Path $testRoot 'acceptance-report.json'
[IO.File]::WriteAllText($badJsonPath, '{ "acceptance": [ this is not valid JSON }', (New-Object System.Text.UTF8Encoding($false)))

try {
    $selfStarted = Start-EditorProcess -Arguments @('--self-test') -WorkingDirectory $testRoot -StdoutPath $selfOut -StderrPath $selfErr
    $selfProcess = $selfStarted.Process
    if (-not $selfProcess.WaitForExit($SelfTestTimeoutSeconds * 1000)) {
        try { $selfProcess.Kill() } catch { }
        Add-Result '--self-test 완료' $false ("제한 시간 {0}초 초과" -f $SelfTestTimeoutSeconds)
    } else {
        $selfProcess.Refresh()
        Save-ProcessOutput $selfStarted $selfOut $selfErr
        $selfOutput = ''
        $selfError = ''
        if (Test-Path -LiteralPath $selfOut) { $selfOutput = Get-Content -Encoding UTF8 -Raw -LiteralPath $selfOut }
        if (Test-Path -LiteralPath $selfErr) { $selfError = Get-Content -Encoding UTF8 -Raw -LiteralPath $selfErr }
        $exitOk = $selfProcess.ExitCode -eq 0
        $details = 'exit=' + [string]$selfProcess.ExitCode + '; stdout=' + [string]$selfOutput + '; stderr=' + [string]$selfError
        Add-Result '--self-test 완료' $exitOk $details
    }

    $acceptanceOut = Join-Path $testRoot 'gui-acceptance.stdout.txt'
    $acceptanceErr = Join-Path $testRoot 'gui-acceptance.stderr.txt'
    $acceptanceStarted = Start-EditorProcess -Arguments @('--gui-acceptance', $testRoot) -WorkingDirectory $testRoot -StdoutPath $acceptanceOut -StderrPath $acceptanceErr
    $acceptanceProcess = $acceptanceStarted.Process
    if (-not $acceptanceProcess.WaitForExit($SelfTestTimeoutSeconds * 1000)) {
        try { $acceptanceProcess.Kill() } catch { }
        Add-Result '--gui-acceptance 완료' $false ("제한 시간 {0}초 초과" -f $SelfTestTimeoutSeconds)
    } else {
        $acceptanceProcess.Refresh()
        Save-ProcessOutput $acceptanceStarted $acceptanceOut $acceptanceErr
        $acceptanceExit = $acceptanceProcess.ExitCode
        $acceptanceReport = Join-Path $testRoot 'gui-acceptance.json'
        $capture = Join-Path $testRoot 'gui-capture.png'
        $acceptancePassed = $acceptanceExit -eq 0 -and (Test-Path -LiteralPath $acceptanceReport) -and (Test-Path -LiteralPath $capture)
        $acceptanceDetails = "exit={0}; report={1}; capture={2}" -f $acceptanceExit, (Test-Path -LiteralPath $acceptanceReport), (Test-Path -LiteralPath $capture)
        if (Test-Path -LiteralPath $acceptanceReport) {
            $guiReport = Get-Content -Encoding UTF8 -Raw -LiteralPath $acceptanceReport | ConvertFrom-Json
            $savedJson = Join-Path $testRoot 'overrides.json'
            $backupJson = $savedJson + '.bak'
            $acceptancePassed = $acceptancePassed -and $guiReport.passed -and ($guiReport.actualOsMouseInput -eq $false) -and
                (Test-Path -LiteralPath $savedJson -PathType Leaf) -and (Test-Path -LiteralPath $backupJson -PathType Leaf)
            if (Test-Path -LiteralPath $savedJson) {
                $savedDocument = Get-Content -Encoding UTF8 -Raw -LiteralPath $savedJson | ConvertFrom-Json
                $savedPlayer = @($savedDocument.characters | Where-Object { $_.id -eq 'Player' })[0]
                $acceptancePassed = $acceptancePassed -and ($null -ne $savedPlayer) -and ([int]$savedPlayer.max_health -eq 6)
            } else { $acceptancePassed = $false }
            $acceptanceDetails += '; output=' + $guiReport.output + '; actualOsMouseInput=' + $guiReport.actualOsMouseInput
            $acceptanceDetails += '; ' + (Get-Content -Encoding UTF8 -Raw -LiteralPath $acceptanceReport).Trim()
        }
        Add-Result '--gui-acceptance 완료' $acceptancePassed $acceptanceDetails
    }

    Write-Output ''
    Write-Output ('잘못된 JSON 시험 파일: {0}' -f $badJsonPath)
    if ($AutomatedOnly) {
        $script:ManualAcceptanceSkipped = $true
        $blocked = '미검증: AutomatedOnly 모드에서는 사용자 GUI 조작과 Y/N 수동 확인을 수행하지 않음.'
        Add-Result 'GUI 실행 및 프로젝트 외부 경로 실행' $false $blocked
        Add-Result '비정상 JSON 거부' $false $blocked
        Add-Result '생성·복제·수정·저장' $false $blocked
        Add-Result '재열기 및 저장값 유지' $false $blocked
        Add-Result '게임 데이터 재적용' $false $blocked
        Add-Result 'GUI 정상 종료' $false $blocked
        Write-Output 'editor_executable_smoke: automated checks only; manual_status=blocked_unverified'
    } elseif ([Console]::IsInputRedirected) {
        $script:ManualAcceptanceBlocked = $true
        $blocked = '차단됨: Y/N 수동 인수 확인은 대화형 입력이 필요합니다. 콘솔에서 다시 실행하세요.'
        Add-Result 'GUI 실행 및 프로젝트 외부 경로 실행' $false $blocked
        Add-Result '비정상 JSON 거부' $false $blocked
        Add-Result '생성·복제·수정·저장' $false $blocked
        Add-Result '재열기 및 저장값 유지' $false $blocked
        Add-Result '게임 데이터 재적용' $false $blocked
        Add-Result 'GUI 정상 종료' $false $blocked
        Write-Output 'editor_executable_smoke: manual acceptance blocked (redirected input; rerun in an interactive console)'
    } else {
    $guiStartedProcess = Start-EditorProcess -Arguments @() -WorkingDirectory $testRoot -StdoutPath '' -StderrPath ''
    $guiProcess = $guiStartedProcess.Process
    Start-Sleep -Seconds 2
    $guiProcess.Refresh()
    $guiStarted = -not $guiProcess.HasExited
    Add-Result 'GUI 실행 및 프로젝트 외부 경로 실행' $guiStarted `
        ("PID={0}; WorkingDirectory={1}; HasExited={2}" -f $guiProcess.Id, $testRoot, $guiProcess.HasExited)

    if ($guiStarted) {
        Confirm-Gate '비정상 JSON 거부' `
            ("편집기에서 위 malformed-editor-data.json을 열거나 가져오세요. 형식 오류를 알리고 데이터 적용을 거부하며 기존 데이터가 유지되는지 확인합니다. GUI가 응답하고 오류를 표시하면 Y: {0}" -f $badJsonPath)
        Confirm-Gate '생성·복제·수정·저장' `
            'GUI에서 새 데이터 항목을 생성하고, 복제본을 만든 뒤 복제본의 필드 하나를 수정해 저장합니다. 원본과 복제본이 구분되고 수정값이 저장되면 Y를 입력하세요.'
        Confirm-Gate '재열기 및 저장값 유지' `
            '저장한 복제본을 닫았다가 다시 열어 수정한 값이 유지되는지 확인합니다.'
        Confirm-Gate '게임 데이터 재적용' `
            '편집기에서 게임 데이터를 다시 적용하거나 동기화하고, 생성·수정한 항목이 게임 데이터에 반영되며 재적용 후에도 유지되는지 확인합니다.'
        Confirm-Gate 'GUI 정상 종료' '인수 검증을 마치고 실제 편집기 창을 정상 종료합니다. 창이 닫힌 것을 확인한 뒤 Y를 입력하세요.'
        $guiProcess.Refresh()
        $closeDetails = if ($guiProcess.HasExited) { '실제 편집기 프로세스가 종료됨' } else { '수동 종료 확인 뒤에도 편집기 프로세스가 실행 중임' }
        Add-Result 'GUI 프로세스 종료 확인' ([bool]$guiProcess.HasExited) `
            $closeDetails
    } else {
        Add-Result '비정상 JSON 거부' $false 'GUI 시작 실패로 미검증'
        Add-Result '생성·복제·수정·저장' $false 'GUI 시작 실패로 미검증'
        Add-Result '재열기 및 저장값 유지' $false 'GUI 시작 실패로 미검증'
        Add-Result '게임 데이터 재적용' $false 'GUI 시작 실패로 미검증'
        Add-Result 'GUI 정상 종료' $false 'GUI 시작 실패로 미검증'
    }
    }
} catch {
    Add-Result '스크립트 실행' $false ($_.Exception.ToString() + "`n" + $_.ScriptStackTrace)
} finally {
    $failedResults = @($script:Results | Where-Object { -not $_.passed })
    $failedCount = 0
    foreach ($result in $script:Results) { if (-not $result.passed) { $failedCount++ } }
    $resultsArray = $script:Results.ToArray()
    $report = [pscustomobject]@{
        product = 'BeltScrollEditor'
        editorPath = $resolvedEditor
        externalWorkingDirectory = $testRoot
        invalidJsonFixture = $badJsonPath
        automated_status = if (@($resultsArray | Where-Object { $_.category -eq 'automated' -and -not $_.passed }).Count -eq 0) { 'passed' } else { 'failed' }
        manual_status = if ($script:ManualAcceptanceSkipped -or $script:ManualAcceptanceBlocked) { 'blocked_unverified' } elseif (@($resultsArray | Where-Object { $_.category -eq 'manual' -and -not $_.passed }).Count -gt 0) { 'failed' } else { 'passed' }
        mode = if ($AutomatedOnly) { 'AutomatedOnly' } else { 'ManualAcceptance' }
        status = if ($script:ManualAcceptanceBlocked -or $script:ManualAcceptanceSkipped) { 'blocked_unverified' } elseif ($failedCount -gt 0) { 'failed' } else { 'passed' }
        passed = if ($AutomatedOnly) { @($resultsArray | Where-Object { $_.category -eq 'automated' -and -not $_.passed }).Count -eq 0 } else { ($failedCount -eq 0) }
        results = $resultsArray
    } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($reportPath, $report, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output ''
    Write-Output ("보고서: {0}" -f $reportPath)
    Write-Output ("시험 자료: {0}" -f $testRoot)
}

$failedCount = 0
foreach ($result in $script:Results) { if (-not $result.passed) { $failedCount++ } }
if ($script:ManualAcceptanceBlocked) {
    Write-Output 'editor_executable_smoke: manual acceptance blocked (exit 2; no approval recorded)'
    exit 2
}
if ($AutomatedOnly) {
    $automatedFailures = @($script:Results | Where-Object { $_.category -eq 'automated' -and -not $_.passed })
    if ($automatedFailures.Count -gt 0) { exit 1 }
    Write-Output 'editor_executable_smoke: automated checks passed; manual_status=blocked_unverified'
    exit 0
}
if ($failedCount -gt 0) {
    exit 1
}
Write-Output 'editor_executable_smoke: all acceptance checks passed'
exit 0
