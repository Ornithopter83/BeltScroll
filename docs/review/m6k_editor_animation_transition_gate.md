# M6K 독립 애니메이션 전환 미리보기 검수 게이트

## 범위와 격리

Animation Workspace의 `전환 연속 미리보기 · 격리` 탭에서 `run → attack1/2/3` 또는 `skill1/2`를 선택해 실제 PNG 프레임을 연속 재생하고 수동으로 한 프레임씩 확인한다. run 경로는 run 클립의 배열 순서를 먼저, 공격 클립의 배열 순서를 다음으로 잇는다. skill 경로는 해당 클립의 배열 순서를 사용한다. 공격 startup/contact/recovery와 skill startup/contact/recovery는 JSON의 `phase` 값과 배열 순서를 그대로 따른다. 누락 단계는 임의 생성하지 않는다.

PNG를 가져올 때 파일 복사본은 OS 임시 폴더 아래 새 Animation Workspace 폴더의 `textures`에 저장된다. 가져온 프레임은 `review`로 시작한다. 불러온 후보도 작업 폴더 밖 texture 경로를 거부한다. 이 탭은 이 격리된 미리보기 문서만 재생하며 게임 씬이나 런타임 승인 목록에 프레임을 등록하지 않는다. PNG가 아직 승인되지 않았다면 격리 작업 폴더에 두고 검수한다. 자동 재생·미리보기·스모크 결과는 원화 승인이나 사람 검수 의견이 아니다.

## 연속성 확인

- 왼쪽 순서 목록은 프레임 순번, clip/phase, 개별 지속시간, normalized 발 anchor와 approval state를 표시한다. 재생은 WinForms Timer 횟수가 아닌 Stopwatch의 실제 경과시간으로 각 프레임 duration을 넘긴다. 마지막 프레임에서 멈춘다.
- 두 캔버스는 현재 프레임과 직전 실제 PNG의 낮은 불투명도 잔상을 보여준다. 설명에는 이전/현재 clip과 phase, 48×48 표본 픽셀의 차이 비율, anchor 좌표 변화, 현재 지속시간 및 approval state가 나타난다. 표본 차이 0% 또는 동일 PNG는 정지 이미지일 수 있으므로 움직임으로 판정하지 않는다.
- 하나의 PNG에 회전만 적용하는 것은 연속 원화 프레임이 아니다. 서로 다른 프레임 파일과 포즈 변화가 있는지 눈으로 확인한다. 파일 이름이나 프레임 개수만으로 자연스러운 동작을 승인하지 않는다.
- 미러 프리뷰는 방향만 뒤집으며 anchor는 원본 좌표를 반영한다. 지지발 미끄러짐, 포즈 점프, 알파 경계, 색·실루엣 변화와 startup→contact→recovery 연결을 실제 재생과 프레임 정지 상태에서 확인한다.

## JSON 및 수동 의견 보존

schema v1 JSON의 clip/frame 배열 순서, phase, duration, texture 상대 경로, `foot_anchor`, `approval_state` 내보내기와 재열기를 계속 지원한다. 전환 탭의 편집은 원본 프레임 데이터를 변경하지 않는다. 기존 수동 시각 검수 체크리스트와 의견 JSON 내보내기는 프레임별 사람 의견 기록으로 유지한다. 의견 내보내기는 approval state와 런타임 allowlist를 변경하지 않는다.

## 스모크 실행

Windows PowerShell 5.1에서 실행한다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
& .\tests\m6k_editor_animation_transition_smoke.ps1
```

GUI 수용 보고서는 run→attack 각 경로와 skill1/2 프레임 개수, 단계 순서, 지속시간/anchor/차이 표시, review 상태, JSON 왕복과 allowlist 불변성을 검사한다. 합성 PNG 스모크는 UI 데이터 흐름만 확인하므로 원화 품질, 동작의 자연스러움, anchor가 실제 발에 정확히 놓였는지, 출처의 진위 및 사람 승인은 검증하지 않는다. 최종 원화 승인과 게임 승격에는 별도 수동 검수 및 기존 승인 게이트가 필요하다.

2026-10-10 HIGH 재실행에서는 35ms 프레임 advance가 한 차례 재현되어 acceptance를 async yield로 바꿨습니다. 전체 GUI 수용 절차가 Timer의 기존 Tick 처리 안에서 중첩 `DoEvents` 루프를 돌지 않고, `Task.Delay`로 양보해 실제 WinForms 메시지 루프가 playback tick을 처리합니다. PowerShell 5.1 스크립트의 화살표 표기도 `[char]0x2192`로 만들어 UTF-8 파일 코드페이지 문제를 피했습니다. 수정 후 전체 WinForms GUI acceptance가 연속 2회 통과했고 `real Stopwatch-driven playback`, 35/50/105/200ms 경계, 정지·재개, JSON 왕복, 격리, review 상태, allowlist 불변을 확인했습니다. WinForms의 10ms 요청 타이머는 한 실행에서 median 31.495ms, max 32.120ms로 측정됐으므로 Stopwatch 누적시간으로 늦은 tick을 따라잡더라도 프레임 관찰은 부하에 영향을 받습니다. 프레임 원화의 자연스러움과 사람 승인은 별도 검토입니다.
