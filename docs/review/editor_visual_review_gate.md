# 독립 편집기 시각 검수 게이트

## 비교 및 동작 미리보기

- `원화 3× 비교` 탭에서 선택한 프레임과 별도 비교 원화를 나란히 보거나 겹쳐 볼 수 있다. 최근접 보간을 사용해 원본 픽셀을 3배 게임 크기로 표시하고, 겹침 불투명도와 좌우 미러를 조절한다.
- `프레임 미리보기`는 투명 격자, 투명 경계선, 드래그 가능한 발 anchor와 미러 프리뷰를 제공한다. 지속시간은 프레임 편집값으로 보이며, `50ms 중간동작` 재생은 다음 프레임과 50ms마다 혼합해 동작 연결을 확인한다.
- 실제 원화의 의미 판단은 사람이 체크리스트의 얼굴, 귀, 의상, 지지발, 모션 연결을 검토해 수행한다.

## 의견과 승인 경계

- 검수 의견은 사용자가 보류·반려·승인 중 하나를 선택하고 `의견 내보내기`를 실행했을 때 별도 JSON 파일로 저장한다. 파일에는 체크리스트와 코멘트가 들어간다.
- 의견 내보내기는 애니메이션 문서의 프레임 `approval_state`를 바꾸거나 게임 allowlist를 수정하지 않는다. 실제 게임 적용/허용은 기존 런타임 경계에서 별도로 통제된다.
- 자동 GUI 수용 모드는 사람 검수 의견 내보내기를 차단한다. 테스트는 프레임을 `review`로 유지하고, export JSON 및 `data/editor/overrides.json`의 SHA-256을 확인해 승인 결정이나 allowlist 변경이 없음을 검증한다.

## GUI 게이트 실행

Windows PowerShell 5.1에서 다음 명령은 편집기를 재빌드한 뒤 독립 EXE의 WinForms 메시지 루프, 실제 컨트롤 이벤트, JSON 왕복, 화면 캡처를 검증한다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
& .\tests\editor_animation_workspace_smoke.ps1
& .\tests\editor_visual_review_smoke.ps1
```

첫 스크립트는 빌드/self-test까지 실행한다. 두 번째는 지정된 `-EditorPath`를 사용할 수 있고, 재빌드 EXE의 시각 검수 캡처 및 기능 이벤트를 확인한다. 산출물은 시스템 임시 폴더에 남는다.

## 보존 계약

- 문서 스키마는 계속 `schema_version: 1`이며 기존 클립 ID·프레임 순서·페이즈·지속시간·anchor·상태의 JSON 왕복을 유지한다.
- 다중 클립 및 숫자 편집 동작을 보존한다. 검수 의견은 animation schema에 추가하지 않는 별도 파일이다.
