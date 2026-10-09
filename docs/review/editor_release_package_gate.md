# 독립 편집기 릴리스 패키지 게이트

## 재현 및 패키징

저장소 루트에서 Windows PowerShell 5.1 또는 PowerShell 7과 .NET 8 SDK를 사용합니다.

```powershell
./tools/package_editor_release.ps1 -Version 1.2.3
```

스크립트는 기존 `editor/build_editor.ps1`을 호출해 `win-x64`, self-contained, single-file EXE를 publish하고 `--self-test`를 실행합니다. 버전, EXE SHA-256, 실행 안내가 ZIP 안에 포함됩니다. 결과 ZIP은 `dist/editor-release/`에 생성됩니다. 생략한 버전은 GitHub ref 이름, Git describe 결과 또는 로컬 기본값에서 결정합니다.

## 패키지 스모크

```powershell
$package = Get-ChildItem dist/editor-release/BeltScrollEditor-*.zip | Select-Object -First 1
./tests/editor_release_package_smoke.ps1 -PackagePath $package.FullName
```

스모크는 ZIP을 저장소 밖 임시 경로에 풀고 해시를 확인한 다음 추출된 EXE에서 `--self-test`를 실행합니다. 편집기 GUI 자동 승인 시나리오에서 수치 데이터 생성·편집·저장·재열기와 애니메이션 작업공간을 검증합니다. 애니메이션 검사는 schema v1의 11개 클립 ID, `attack1`의 startup/inbetween/contact/recovery 4프레임, 내보낸 JSON 안의 texture PNG, 그리고 디코딩 가능한 GUI 캡처 PNG를 검사합니다. 결과 JSON과 프로세스 로그는 저장소 밖 임시 폴더에 보존됩니다.

Windows PowerShell 5.1 및 PowerShell 7에서 패키지 스모크를 각각 실행하고 둘 다 확인하려면:

```powershell
./tests/editor_release_contract_smoke.ps1 -PackagePath $package.FullName
```

`-AllowGuiUnverified`는 GUI 런타임에 접근할 수 없어 GUI 프로세스를 시작하지 못한 경우에만 GUI 확인을 `UNVERIFIED`로 기록합니다. acceptance 실패, 클립 수·프레임 수 불일치, JSON/PNG 누락 및 손상 같은 검증 실패는 이 스위치로 통과되지 않습니다. CI에서도 압축 해제, 해시 및 self-test 실패는 빌드를 실패시킵니다.

## GitHub Actions 산출물

`.github/workflows/editor-package.yml`은 `main` push와 수동 `workflow_dispatch`에서 패키지를 만듭니다. Actions 실행의 `BeltScrollEditor-win-x64-*` artifact를 다운로드할 수 있고 보존 기간은 90일입니다. 이 artifact 업로드는 GitHub Release 게시가 아니므로, 원격 Actions 실행이 성공하고 artifact가 실제 존재하기 전에는 배포 완료로 취급하지 않습니다.

## 검토 기록

| 게이트 | 상태 | 증거 |
| --- | --- | --- |
| 원격 ZIP 다운로드·압축 해제·SHA-256 | `PASS` | 실행 `37951799265`, artifact `11625958097`, ZIP SHA-256 기록 아래 참조 |
| 독립 EXE self-test | `PASS` (Windows PowerShell 5.1 / PowerShell 7.6.6) | 추출 EXE SHA-256 및 두 `release-smoke-report.json` |
| 숫자 편집 및 애니메이션 GUI 입출력 | `PASS` (두 PowerShell 런타임) | schema v1 11개 클립, attack1 4프레임, JSON/PNG acceptance 보고서 |
| 원격 다운로드 artifact | `PASS` | `BeltScrollEditor-win-x64-9`, artifact ID `11625958097` |

### 복구 대상 실행

2026-10-09의 [실행 37946203045](https://github.com/Ornithopter83/BeltScroll/actions/runs/37946203045) 및 [실행 37949283761](https://github.com/Ornithopter83/BeltScroll/actions/runs/37949283761)은 빌드·패키징 단계가 성공하고 추출 패키지 스모크가 실패했습니다. 두 job 로그의 실패 문구는 당시 애니메이션 보고서/JSON/캡처 통합 검사에서 나왔으며, 수정 전 스모크의 clipCount 기대치가 실제 schema v1 데이터와 달랐습니다. 두 실행 모두 artifact가 없었습니다. 수정 이후 실행 37951799265에서 package workflow 성공과 다운로드 artifact를 확인했습니다.

현재 소스에서 생성한 framework-dependent 검증용 ZIP으로 Windows PowerShell 5.1과 PowerShell 7.6.6 계약 스모크를 각각 통과했습니다. ZIP과 로그는 저장소 밖 임시 폴더에 두었습니다. 두 실행 모두 추출, SHA-256, self-test, schema v1의 11개 클립과 4개 attack1 프레임, texture PNG 및 GUI 캡처 PNG 디코딩이 `PASS`였습니다. 이 ZIP은 로컬 검증용이므로 GitHub Actions의 self-contained 배포 ZIP과 원격 artifact 성공을 대신하지 않습니다.

### 원격 배포 ZIP 검증 결과

[GitHub Actions 실행 37951799265](https://github.com/Ornithopter83/BeltScroll/actions/runs/37951799265)은 commit `838cf60af75eac3a5a2205fcfffb499a1adb9867`에서 `completed/success`였습니다. artifact `BeltScrollEditor-win-x64-9` (ID `11625958097`, 66,237,280 bytes)는 다운로드 가능했고, API의 artifact archive digest는 `sha256:5a6aeb1f63d7ef5aca8ce867478b77137e2f857e148cfd09465fc9328e42016c`입니다.

다운로드한 실제 배포 ZIP `BeltScrollEditor-main-9-win-x64.zip`의 SHA-256은 `595b857ca58fe3eb3c720987ee629d4aa40798055be394cb2aa738e00a1d5a29`입니다. Windows PowerShell 5.1과 PowerShell 7.6.6 양쪽에서 저장소 외부로 추출해 실행했고, ZIP 내 EXE SHA-256 `d9a0dba9def435401af17c289de9344d22846042f0ab51220f977828853760ed`, 독립 `--self-test`, GUI acceptance, schema v1 11개 클립, `attack1`의 startup/inbetween/contact/recovery 4프레임, JSON/texture와 실제 캡처 PNG 디코딩이 모두 `PASS`였습니다. 양쪽 스모크의 `release-smoke-report.json`도 `passed: true`였습니다.
