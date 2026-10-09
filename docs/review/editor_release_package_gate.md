# 독립 편집기 릴리스 패키지 게이트

## 재현 및 패키징

저장소 루트에서 Windows PowerShell 5.1 이상과 .NET 8 SDK를 사용합니다.

```powershell
./tools/package_editor_release.ps1 -Version 1.2.3
```

스크립트는 기존 `editor/build_editor.ps1`을 호출해 `win-x64`, self-contained, single-file EXE를 publish하고 `--self-test`를 실행합니다. 버전, EXE SHA-256, 실행 안내가 ZIP 안에 포함됩니다. 결과 ZIP은 `dist/editor-release/`에 생성됩니다. 생략한 버전은 GitHub ref 이름, Git describe 결과 또는 로컬 기본값에서 결정합니다.

## 패키지 스모크

```powershell
$package = Get-ChildItem dist/editor-release/BeltScrollEditor-*.zip | Select-Object -First 1
./tests/editor_release_package_smoke.ps1 -PackagePath $package.FullName
```

스모크는 ZIP을 저장소 밖 임시 경로에 풀고 해시를 확인한 다음 추출된 EXE에서 `--self-test`를 실행합니다. 편집기 GUI 자동 승인 시나리오에서 수치 데이터 생성·편집·저장·재열기와 애니메이션 작업공간 편집·JSON/텍스처 입출력을 확인합니다. 결과 JSON과 로그는 임시 폴더에 보존됩니다. GUI 런타임이 없는 CI에서는 `-AllowGuiUnverified`를 전달할 수 있으며, 이때 GUI 부분은 성공으로 위장하지 않고 `UNVERIFIED`로 남깁니다. CI에서도 압축 해제, 해시 및 self-test 실패는 빌드를 실패시킵니다.

## GitHub Actions 산출물

`.github/workflows/editor-package.yml`은 `main` push와 수동 `workflow_dispatch`에서 패키지를 만듭니다. Actions 실행의 `BeltScrollEditor-win-x64-*` artifact를 다운로드할 수 있고 보존 기간은 90일입니다. 이 artifact 업로드는 GitHub Release 게시가 아니므로, 원격 Actions 실행이 성공하고 artifact가 실제 존재하기 전에는 배포 완료로 취급하지 않습니다.

## 검토 기록

| 게이트 | 상태 | 증거 |
| --- | --- | --- |
| 로컬 빌드·패키지 생성 | 실행 환경에서 수행 후 기록 | `dist/editor-release/` ZIP 및 SHA-256 |
| 추출 EXE self-test | 패키지 스모크 결과 기록 | `release-smoke-report.json` |
| 숫자 편집 및 애니메이션 GUI 입출력 | 실행 환경별 `PASS` 또는 `UNVERIFIED` | 같은 JSON 보고서 및 acceptance 산출물 |
| 원격 다운로드 artifact | GitHub Actions 완료 후 확인 | 워크플로 실행 링크와 artifact 이름 |
