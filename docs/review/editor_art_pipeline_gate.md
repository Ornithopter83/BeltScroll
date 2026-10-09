# 독립 애니메이션 에디터 아트 파이프라인 게이트

## 편집 계약

WinForms 작업공간은 여러 클립을 생성하고 선택해 편집합니다. 클립 ID는 `idle`, `attack1`, `attack2`, `attack3`이며 중복 ID는 허용하지 않습니다. 공격 클립 프레임은 `startup`, `inbetween`, `contact`, `recovery` phase를, idle 클립 프레임은 `idle` phase를 사용합니다. 프레임 순서는 목록의 위/아래 동작으로 바꾸고, 각 프레임의 시간, anchor, 검수 상태를 편집합니다.

UTF-8 `schema_version: 1` JSON의 `clips[].id`와 `clips[].frames[]`에는 `texture`, `phase`, `duration`, `foot_anchor`, `approval_state`가 기록됩니다. Anchor는 `{ "x": 0.5, "y": 0.9 }` 형식의 0~1 정규화 좌표 객체입니다. 예전 `"alpha_bottom_center"` 문자열은 schema v1에서 거부합니다. 프레임 배열 순서와 초 단위 duration은 재정렬·내보내기·불러오기 후에도 유지됩니다. 임시 변환 프레임은 `texture: null`일 수 있습니다. 클립마다 하나 이상의 프레임이 있어야 합니다. 상태는 `review`, `approved`, `unapproved`, `temporary`를 보존하며 새 PNG 프레임은 `review`로 시작합니다.

PNG는 작업 폴더의 `textures/`로 복사하며 JSON 내보내기는 모든 클립이 참조하는 파일을 함께 둡니다. 프리뷰는 투명 격자, 알파 실루엣 경계, 좌우 반전 화면과 클릭 조정 anchor를 제공합니다. phase, 지속시간, 검수 상태, 재생/정지와 프레임 이동·삭제 편집을 포함합니다.

## 본편 아트 검수 게이트

GUI의 `approved` 선택은 작업 JSON에 검수 상태를 기록하는 편집 동작입니다. 그 선택만으로 새 원화가 게임 본편에 등록되지는 않습니다. 런타임 `PlayerAnimationBank`는 승인 프레임의 texture가 해당 공격 동작의 코드 allowlist에 지정된 contact 키포즈와 픽셀 단위로 동일한지 확인하며, 다른 phase의 승인은 등록하지 않습니다. Idle도 코드에 지정된 승인 still만 허용합니다. 따라서 임시 원화나 미검수 후보의 상태를 GUI에서 `approved`로 바꿔도 본편 사용 기준은 완화되지 않습니다.

## WinForms 및 EXE 스모크

Windows PowerShell 5.1에서 실행합니다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Get-Content -Encoding UTF8 .\docs\review\editor_art_pipeline_gate.md
.\tests\editor_animation_workspace_smoke.ps1
```

스모크는 독립 win-x64 EXE를 재빌드하고 `--self-test`를 실행한 뒤 실제 WinForms 메시지 루프를 표시합니다. GUI 컨트롤 이벤트로 PNG 가져오기, 4개 클립 생성·선택, 4개 공격 phase 편집, duration·승인 상태·anchor 포인터 변경, 프레임 재정렬, 재생/정지, 다중 클립 내보내기 및 다시 불러오기를 확인합니다. JSON 왕복 뒤 프레임 순서, 시간, anchor, 승인 상태 및 클립 ID를 비교하고 폼 화면 캡처를 생성합니다. 로그·캡처·내보낸 JSON은 스크립트가 출력하는 임시 폴더에 보존됩니다.

자동 확인은 보이는 폼의 이벤트 핸들러를 GUI 메시지 루프에서 호출합니다. OS 마우스/키보드 입력과 사람의 미술 검수는 포함하지 않습니다. 게임 런타임 적용은 별도의 게임 브리지 검증 범위입니다.
