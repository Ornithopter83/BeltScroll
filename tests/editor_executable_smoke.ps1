param(
    [string]$EditorPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\BeltScrollEditor.exe'),
    [int]$SelfTestTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$script:Results = New-Object System.Collections.Generic.List[object]

function Add-Result([string]$Name, [bool]$Passed, [string]$Details) {
    $script:Results.Add([pscustomobject]@{
        check = $Name
        passed = $Passed
        details = $Details
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
    $selfProcess = Start-Process -FilePath $resolvedEditor -ArgumentList @('--self-test') -WorkingDirectory $testRoot `
        -RedirectStandardOutput $selfOut -RedirectStandardError $selfErr -PassThru
    if (-not $selfProcess.WaitForExit($SelfTestTimeoutSeconds * 1000)) {
        try { $selfProcess.Kill() } catch { }
        Add-Result '--self-test 완료' $false ("제한 시간 {0}초 초과" -f $SelfTestTimeoutSeconds)
    } else {
        $selfProcess.Refresh()
        $selfOutput = ''
        $selfError = ''
        if (Test-Path -LiteralPath $selfOut) { $selfOutput = Get-Content -Encoding UTF8 -Raw -LiteralPath $selfOut }
        if (Test-Path -LiteralPath $selfErr) { $selfError = Get-Content -Encoding UTF8 -Raw -LiteralPath $selfErr }
        $exitOk = $selfProcess.ExitCode -eq 0
        $details = "exit={0}; stdout={1}; stderr={2}" -f $selfProcess.ExitCode, $selfOutput.Trim(), $selfError.Trim()
        Add-Result '--self-test 완료' $exitOk $details
    }

    Write-Output ''
    Write-Output ('잘못된 JSON 시험 파일: {0}' -f $badJsonPath)
    $guiProcess = Start-Process -FilePath $resolvedEditor -WorkingDirectory $testRoot -PassThru
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
        Confirm-Gate 'GUI 정상 종료' '인수 검증 후 편집기를 정상 종료합니다. 종료가 완료되었으면 Y를 입력하세요.'
    } else {
        Add-Result '비정상 JSON 거부' $false 'GUI 시작 실패로 미검증'
        Add-Result '생성·복제·수정·저장' $false 'GUI 시작 실패로 미검증'
        Add-Result '재열기 및 저장값 유지' $false 'GUI 시작 실패로 미검증'
        Add-Result '게임 데이터 재적용' $false 'GUI 시작 실패로 미검증'
        Add-Result 'GUI 정상 종료' $false 'GUI 시작 실패로 미검증'
    }
} catch {
    Add-Result '스크립트 실행' $false $_.Exception.Message
} finally {
    $report = [pscustomobject]@{
        product = 'BeltScrollEditor'
        editorPath = $resolvedEditor
        externalWorkingDirectory = $testRoot
        invalidJsonFixture = $badJsonPath
        passed = (@($script:Results | Where-Object { -not $_.passed }).Count -eq 0)
        results = @($script:Results)
    } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($reportPath, $report, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output ''
    Write-Output ("보고서: {0}" -f $reportPath)
    Write-Output ("시험 자료: {0}" -f $testRoot)
}

if (@($script:Results | Where-Object { -not $_.passed }).Count -gt 0) {
    exit 1
}
Write-Output 'editor_executable_smoke: all acceptance checks passed'
exit 0
