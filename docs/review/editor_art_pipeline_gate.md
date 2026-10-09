# 독립 편집기 아트·애니메이션 작업공간 게이트

## 제공 기능

기존 게임 수치 편집 화면의 `아트·애니메이션 작업공간` 버튼으로 별도 WinForms 창을 엽니다. PNG를 프레임으로 가져오면 별도 임시 작업 폴더의 `textures/`에 복사됩니다. 투명 격자 위에서 확대 이미지를 확인하고, 알파 경계를 표시하며, 이미지 위를 클릭해 정규화된 발 anchor를 조정할 수 있습니다. 미러 프리뷰, 프레임 순서 변경, 프레임별 지속시간, startup/contact/recovery 페이즈, 승인 상태, 재생/정지를 제공합니다.

작업 폴더의 `animation.json`은 UTF-8 `schema_version: 1` 문서이며 `clips[].frames[]`에 `texture`, `phase`, `duration`, `foot_anchor: {x,y}`, `approval_state`를 저장합니다. 미승인 기본값은 `review`이며 승인 체크를 명시적으로 켠 프레임만 `approved`로 저장됩니다. 텍스처 경로는 JSON 파일을 기준으로 한 상대 경로입니다. 내보내기와 불러오기는 폴더와 참조 텍스처가 함께 있는 형식을 사용합니다.

## 빌드와 자동 GUI 확인

Windows PowerShell 5.1에서:

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Get-Content -Encoding UTF8 .\docs\review\editor_art_pipeline_gate.md
.\tests\editor_animation_workspace_smoke.ps1
```

스모크 스크립트 독립 EXE를 다시 발행하고 기존 모델 self-test를 실행한 뒤, 별도 임시 폴더에서 실제 WinForms 메시지 루프를 시작합니다. GUI 컨트롤 이벤트로 PNG 가져오기, phase/duration/승인 편집, anchor 포인터 이벤트, 프레임 재정렬, 재생/정지, JSON 내보내기와 다시 불러오기를 확인합니다. 실행 보고서, 화면 캡처, 프레임 PNG와 JSON은 출력된 임시 경로에 보존됩니다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Get-Content -Encoding UTF8 (Join-Path $env:TEMP '<출력된 작업 폴더>\animation-gui-acceptance.json')
```

자동 GUI 경로는 OS 마우스/키보드 장치 입력을 흉내 내지 않고, 실제 표시된 폼의 컨트롤 이벤트를 GUI 메시지 루프에서 호출합니다. 수동 미술 검수와 게임 런타임으로 애니메이션을 적용하는 연결은 이 게이트의 자동 검증 범위에 포함되지 않습니다.
