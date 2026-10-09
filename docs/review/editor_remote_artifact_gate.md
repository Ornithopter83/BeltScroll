# GitHub Actions 편집기 artifact 검증 게이트

`tools/verify_actions_editor_artifact.ps1`는 현재 `main` 커밋에 연결된 최신 성공 `editor-package.yml` 실행의 배포 패키지를 검증합니다. 저장소의 `main` SHA를 API에서 읽고, `head_sha`가 그 SHA와 같으며 `completed`/`success`인 실행을 고릅니다. 실행 번호로 artifact 이름을 계산한 뒤 Actions API에서 실제 이름·ID·digest를 확인합니다. 과거 run ID나 artifact ID를 기본값으로 사용하지 않습니다.

2026-10-10에 GitHub API에서 확인한 현재 대상:

- 저장소: `Ornithopter83/BeltScroll`
- `main` SHA: `838cf60af75eac3a5a2205fcfffb499a1adb9867`
- 최신 성공 package run: `37951799265` (run number `9`)
- Artifact: `BeltScrollEditor-win-x64-9`, ID `11625958097`
- GitHub artifact digest: `sha256:5a6aeb1f63d7ef5aca8ce867478b77137e2f857e148cfd09465fc9328e42016c`

저장소 루트에서 기본 원격 검증을 실행합니다. 필요하면 `-Repository owner/name`을 전달합니다.

```powershell
./tools/verify_actions_editor_artifact.ps1
```

`-ExpectedRunId`, `-ExpectedArtifactName` 옵션은 API에서 동적으로 찾은 결과가 지정한 대상인지 추가로 단언합니다. 현재 확인 대상에 고정해 실행하려면 다음과 같습니다.

```powershell
./tools/verify_actions_editor_artifact.ps1 -Repository Ornithopter83/BeltScroll -ExpectedRunId 37951799265 -ExpectedArtifactName BeltScrollEditor-win-x64-9
```

검증기는 artifact ID로 Actions 바깥 ZIP을 내려받아 `actions-artifact-outer.zip`에 보존합니다. GitHub API digest와 바이트 단위 SHA-256을 대조한 뒤 `actions-artifact-outer-extracted`에 압축을 풀고, 내부의 단일 `BeltScrollEditor-*.zip` 배포 패키지를 식별합니다. 배포 ZIP의 SHA-256을 별도로 기록하고 압축 해제한 `BeltScrollEditor.exe`를 UTF-8 `SHA256SUMS.txt`와 비교합니다. 그 다음 `tests/editor_release_package_smoke.ps1`를 실행해 self-test와 GUI 편집·저장·재열기 검증을 수행합니다. JSON 보고서의 `outerArtifactZipSha256`와 `packageSha256`는 서로 다른 ZIP을 가리키며, run SHA·ID 및 artifact 이름·ID·digest도 포함합니다.

성공 run 부재, artifact 부재·중복·만료, 올바르지 않은 digest, 예상 이름 불일치, SHA 불일치는 `FAIL`이며 `PASS`가 될 수 없습니다. `gh` 미설치, 인증 실패, GitHub API 또는 다운로드 네트워크/권한 오류는 `UNVERIFIED`(종료 코드 2)입니다. 종료 코드는 `PASS` 0, `FAIL` 1, `UNVERIFIED` 2입니다.

로컬 ZIP 검증 결과는 원격 검증과 분리됩니다. `-PackagePath path/to/BeltScrollEditor-*.zip`을 주면 같은 배포 ZIP·EXE 체크섬·self-test·GUI 검증을 로컬에서 수행하고 보고서에 `source: local-package`를 기록합니다. 이 모드에서는 원격 run/artifact 증거를 주장하지 않습니다. `tests/editor_artifact_integrity_smoke.ps1`는 이 로컬 모드를 사용합니다. `tests/editor_remote_artifact_smoke.ps1`는 동적 run 조회, artifact 식별과 digest 검사, 바깥/안쪽 ZIP 분리, 원격 상태 분류, 로컬/원격 레이블을 확인하는 회귀 smoke입니다.

위 대상에서 실제 원격 검증을 수행했습니다. run/artifact 조회, 바깥 ZIP digest, 내부 배포 ZIP, EXE SHA-256, `--self-test`, 숫자 편집기와 Animation workspace GUI acceptance가 모두 통과해 전체 결과는 `PASS`입니다. 보고서는 `%TEMP%\BeltScrollEditorArtifact_7e5973eb83f848aab8a78d97590b54b0\verification-report.json`에 기록됐습니다.

## HIGH 재검증 기록 (2026-10-10)

- 이전 원격 보고서에 기록된 외부 Actions ZIP과 내부 배포 ZIP을 다시 해시했다. 외부 ZIP은 `5a6aeb1f63d7ef5aca8ce867478b77137e2f857e148cfd09465fc9328e42016c`, 내부 배포 ZIP은 `595b857ca58fe3eb3c720987ee629d4aa40798055be394cb2aa738e00a1d5a29`, 압축 해제 EXE는 `d9a0dba9def435401af17c289de9344d22846042f0ab51220f977828853760ed`로 기존 API digest와 보고서 해시에 일치했다.
- 보존된 내부 ZIP을 저장소 밖으로 다시 풀어 `--self-test`, 숫자 편집 저장·재열기, Animation workspace GUI acceptance를 실행했다. schema v1 11개 clip, `attack1` startup/inbetween/contact/recovery 4 phase, JSON 및 texture PNG, GUI 캡처 PNG 디코딩이 모두 통과했다. 재실행 보고서는 `%TEMP%\BeltScrollEditorReleaseSmoke_7a86921dc03f42deacbf6d4679255785\release-smoke-report.json`이다. 이 검사는 앞서 다운로드해 digest를 검증한 원격 artifact 파일의 재검사이며 새로운 네트워크 다운로드는 아니다.
- 이번 직접 GitHub 재조회는 `gh auth status` 실패로 `UNVERIFIED`다. 검증기가 PowerShell 5.1에서 native stderr를 FAIL로 오분류하던 결함을 수정했으며, 재시도 보고서는 `%TEMP%\BeltScrollArtifactHighRerun3\verification-report.json`에 `UNVERIFIED`로 남았다. 따라서 현재 새 원격 API 확인 상태와 과거에 확인된 정확한 run/artifact 상태를 별도 유지한다.
- 현재 checkout `HEAD`는 `838cf60af75eac3a5a2205fcfffb499a1adb9867`이다. GitHub의 현재 main SHA를 이번 재실행에서 조회할 수 없으므로 이 실행에서 최신 여부를 새로 단정하지 않는다.
