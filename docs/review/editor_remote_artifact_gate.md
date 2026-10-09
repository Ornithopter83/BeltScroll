# GitHub Actions 편집기 artifact 검증 게이트

## 검증 대상

기본 대상은 `Ornithopter83/BeltScroll`의 Actions run `37921763731`과 `BeltScrollEditor-win-x64-1` artifact입니다. 검증기는 원격 run이 완료 상태이며 conclusion이 `success`인지와 artifact가 run에 속하고 만료되지 않았는지 확인한 뒤 `gh run download`로 artifact를 내려받고 압축을 풉니다. GitHub API가 보고하는 outer artifact digest는 기록하지만, `gh run download`가 outer ZIP을 내부에서 풀어 저장하므로 그 wrapper 바이트의 digest를 별도 대조하지는 않습니다. 대신 내려받은 배포 ZIP에서 EXE를 추출하고 `SHA256SUMS.txt`의 해시와 직접 대조합니다.

Artifact ZIP을 풀면 배포용 `BeltScrollEditor-*.zip`이 있습니다. 배포 ZIP도 프로젝트 밖 임시 검증 폴더에 풀고 EXE SHA-256을 `SHA256SUMS.txt`와 확인합니다. 이어서 `--self-test`, 외부 작업 폴더에서의 실행, 숫자 편집기 GUI의 파일 생성·수정·저장·재열기, animation workspace GUI의 편집·JSON/texture export·reload를 확인합니다. 로그, 캡처, 보고서는 `-OutputDirectory`에 남습니다.

## 원격 artifact 검증

Windows PowerShell 5.1, 네트워크 연결, GitHub CLI(`gh`)가 필요합니다. private 저장소에서는 대상 저장소를 읽을 수 있고 Actions artifact를 읽을 권한이 있는 GitHub 인증이 필요합니다. `gh auth login`으로 로그인합니다. 기본 저장소는 현재 checkout에서 읽으므로 BeltScroll 프로젝트 루트에서 실행합니다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
gh auth status
.\tools\verify_actions_editor_artifact.ps1
```

다른 run, artifact, 저장 폴더를 지정할 수 있습니다.

```powershell
.\tools\verify_actions_editor_artifact.ps1 `
  -RunId 37921763731 `
  -ArtifactName 'BeltScrollEditor-win-x64-1' `
  -Repository 'Ornithopter83/BeltScroll' `
  -OutputDirectory "$env:TEMP\BeltScrollEditorRemoteCheck"
```

종료 코드 `0`은 원격 다운로드와 전체 검증 통과, `1`은 검증 실패 또는 원격 run/artifact 불일치, `2`는 인증·권한·네트워크 문제로 원격 다운로드를 하지 못한 상태입니다. `UNVERIFIED`는 성공으로 계산하지 않습니다. artifact는 workflow 보존 정책에 따라 만료될 수 있습니다. 보고서의 `source`가 `github-actions-artifact`이고 `status`가 `PASS`일 때 원격 artifact의 배포 ZIP과 EXE 검증이 통과한 결과입니다. GitHub outer digest는 보고서 검사 항목에 기록되어 있고 digest 직접 비교는 수행하지 않습니다.

GUI smoke는 실제 Windows 데스크톱 세션이 필요할 수 있습니다. GUI를 표시할 수 없는 세션에서 실패하면 해당 실행 환경의 제한을 확인하고, 대화형 Windows 세션에서 재실행합니다. 원격 스크립트의 성공 상태만으로 artifact 바이트 검증을 대신하지 않습니다.

## 로컬 패키지 검증과 구분

로컬에서 만든 ZIP은 원격 artifact 검증으로 보고하지 않습니다. 로컬 패키지의 포함 EXE 해시, self-test, 외부 경로 실행과 GUI 파일 입출력은 다음 별도 smoke로 확인합니다.

```powershell
.\tests\editor_artifact_integrity_smoke.ps1
```

다른 로컬 ZIP을 검사하려면 `-PackagePath 'D:\build\BeltScrollEditor.zip'`을 전달합니다. 결과 보고서에는 `source: local-package`가 기록됩니다. 이 결과는 GitHub run의 성공이나 artifact digest를 입증하지 않습니다. 가장 최신 로컬 패키지 단위 검증만 원한다면 `tests/editor_release_package_smoke.ps1`를 직접 사용할 수도 있습니다.
