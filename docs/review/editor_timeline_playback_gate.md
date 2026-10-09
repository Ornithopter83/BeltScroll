# WinForms 타임라인 재생 검수 게이트

## 재생 시계와 타이머 측정

- `Stopwatch`의 실제 경과시간을 현재 프레임 Duration에 누적한다. WinForms Timer는 10ms 갱신 트리거로만 쓰며, 프레임 Duration으로 Timer 간격을 재설정하지 않는다. UI 처리나 이미지 렌더링이 늦으면 다음 Tick에서 지난 실제 시간을 반영해 해당 위치까지 따라간다.
- `재생` 버튼은 재생 중 일시정지, 다시 누르면 현재 프레임과 프레임 내부 경과시간을 유지해 재개한다. `정지`는 위치를 초기화한다. 클립 변경은 이전 클립의 시계를 정지하고 새 클립 첫 프레임을 선택한다. 프레임 선택·재정렬은 새 순서와 선택 프레임에 맞춰 기준 시계를 다시 맞춘다.
- 중간동작 혼합량은 고정 50ms 누적이 아니라 현재 프레임에서 측정한 경과시간/Duration으로 구한다. 35ms, 50ms, 105ms, 200ms가 각각 독립 프레임 Duration이다.
- 수용 실행은 실제 WinForms Timer의 40개 이상 연속 Tick 간격을 `Stopwatch`로 측정한다. 출력 JSON의 `timerPrecision`에는 요청 간격, 측정 개수, 최소·중앙·평균·최대(ms)가 저장된다. 이 측정치는 해당 Windows 실행 환경의 값이며, 10ms보다 큰 지연과 흔들림은 Windows 메시지 루프·스케줄링에 따른 갱신 해상도 한계로 기록한다. 프레임 시계는 이 측정값을 누적하지 않고 단조 증가 Stopwatch 경과시간을 쓴다.

2026-10-09 최종 스모크 실행에서 10ms 요청으로 40개 간격을 측정한 값은 최소 0.008ms, 중앙값 30.384ms, 평균 21.933ms, 최대 46.713ms였다. 최소값은 메시지 처리 지연 뒤 짧은 간격으로 관측된 Tick을 포함한다. 따라서 Timer 간격은 재생 정밀도 보장치가 아니며, 프레임 전환은 UI Tick 횟수 대신 Stopwatch 경과시간으로 판정한다. 스모크를 다른 PC에서 실행하면 그 실행의 개별 측정 결과가 acceptance JSON과 콘솔에 남는다.

## 실행 및 확인 항목

Windows PowerShell 5.1에서 아래 스모크는 편집기를 빌드하고 GUI 수용 모드를 실행한다. JSON 왕복, 화면 캡처, 실제 Timer 간격을 임시 산출물에 남긴다.

```powershell
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
& .\tests\editor_timeline_playback_smoke.ps1
```

검증 내용은 다음과 같다.

- 35ms/50ms/105ms/200ms 프레임의 순서, 각 누적 경계, 390ms 루프 경계와 긴 지연 뒤 위치 복구.
- 프레임 재정렬 시 Duration과 프레임 데이터 결합, 일시정지/재개 위치 유지, 10ms UI 갱신 트리거 및 실측 Timer 간격 보고.
- 원화 비교의 576px 기준 표시, 나란히/겹침/줌/팬 캡처와 anchor·Duration 표시.
- schema v1 JSON 내보내기/불러오기에서 프레임 순서와 Duration 보존.
- 자동 검수는 프레임을 `review`로 유지하고 수동 검수 의견을 만들지 않는다. `data/editor/overrides.json` 승인 allowlist 해시도 전후 동일해야 한다. 기존 수동 검수 의견 내보내기와 런타임 승인 차단은 그대로 유지한다.

자동 GUI 통과는 사람의 시각 검수나 승인으로 간주하지 않는다. 얼굴, 귀, 의상, 지지발, 모션 연결의 수동 체크리스트와 별도 의견 내보내기 절차가 유효하다.
