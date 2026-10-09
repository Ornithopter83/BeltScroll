# M5D 사람 직접 수행 최종 인수 체크리스트

이 체크리스트는 최종 통합 인수 기록지다. 자동 smoke, 입력 주입, 자동 캡처 또는 편집기 self-test가 대신 체크할 수 없다. 실제 표시·동작을 사람이 확인한 뒤 실행기의 `manual-review.json`에 항목별로 `pass`를 기록한다. 실패/미실시/확인 불가는 `fail`/`not_tested`로 남겨 전체 결과를 `BLOCKED_UNVERIFIED`로 유지한다.

## 세션 정보

- 날짜/시간 및 시간대:
- 검사자:
- 빌드/커밋 또는 실행 파일 경로:
- 디스플레이 실제 해상도:
- 게임 증거 디렉터리 (`input-events.jsonl`, `manual-review.json` 포함):
- 추가 캡처 폴더와 파일 경로:
- 별도 편집기 실행 파일/작업 폴더:

## 게임 표시와 조작

| 항목 | 사람이 직접 확인할 것 | 결과 | 캡처/메모 |
|---|---|---|---|
| 1920×1080 | 실제 화면/게임 렌더가 1920×1080 기준인지 | ☐ pass ☐ fail ☐ not_tested | |
| 전체화면 | 창 테두리 없이 전체화면 표시 및 화면 잘림/왜곡 여부 | ☐ pass ☐ fail ☐ not_tested | |
| 3배 표시 | 원화가 목표 게임 표시 크기의 3배 기준에 맞고 nearest/blur 등 표시 이상이 없는지 | ☐ pass ☐ fail ☐ not_tested | |
| Num1–Num9 | 숫자 키를 하나씩 실제로 눌러 각각의 본편 화면 반응 확인 | ☐ pass ☐ fail ☐ not_tested | 키패드 여부: |
| W/A/S/D | 각 방향 이동과 좌우 전환/복귀 | ☐ pass ☐ fail ☐ not_tested | |
| Space | 점프/착지 반응 | ☐ pass ☐ fail ☐ not_tested | |
| Shift | 연결된 기능의 화면 반응 | ☐ pass ☐ fail ☐ not_tested | |
| J | 기본 공격 반응 | ☐ pass ☐ fail ☐ not_tested | |
| 마우스 좌클릭 | 연결 동작 및 클릭 후 복귀 | ☐ pass ☐ fail ☐ not_tested | |
| Esc | 본편 일시정지/메뉴 반응과 복귀 | ☐ pass ☐ fail ☐ not_tested | |
| 창 포커스 | 포커스를 다른 창으로 옮겼다가 복귀, 게임 입력 회복 및 별도 로그 확인 | ☐ pass ☐ fail ☐ not_tested | |
| Player 체력바 | 피격/회복 상황에서 Player 바가 보이고 변하는지 | ☐ pass ☐ fail ☐ not_tested | |
| Raider 체력바 | 전투 중 각 Raider 머리 위 바가 보이고 대상 피격에 따라 변하는지 | ☐ pass ☐ fail ☐ not_tested | |
| Num4/Num5 차이 | 슬롯명/준비·사용·쿨다운 표시와 실제 동작이 각각 식별되는지 | ☐ pass ☐ fail ☐ not_tested | |

## 별도 편집기 수동 왕복

[편집기 인수 게이트](editor_acceptance_gate.md)의 실행 파일을 독립 작업 디렉터리에서 열어 아래 작업을 실제 UI로 완료한다. 생성부터 게임 재적용까지 순서를 유지하고 파일/항목 이름과 재적용 방법을 기록한다.

| 순서 | 실제 GUI 작업 | 결과 | 항목/경로/메모 |
|---:|---|---|---|
| 1 | 새 게임 데이터 항목 생성 | ☐ pass ☐ fail ☐ not_tested | |
| 2 | 해당 항목을 수정하고 값 확인 | ☐ pass ☐ fail ☐ not_tested | |
| 3 | 저장 후 편집기를 닫음 | ☐ pass ☐ fail ☐ not_tested | |
| 4 | 다시 열어 저장값과 원본/복제본 구분을 확인 | ☐ pass ☐ fail ☐ not_tested | |
| 5 | 수정 데이터를 게임에 재적용/동기화하고 실제 반영 확인 | ☐ pass ☐ fail ☐ not_tested | |

자동 `--self-test`와 `--gui-acceptance`는 이 직접 관찰의 대체 자료가 아니다. 수정 데이터나 증거는 사용자가 지정한 별도 작업 폴더에 보존하고, 기존 게임 데이터나 입력 로그를 재사용해 덮어쓰지 않는다.

## 원화 identity와 움직임 검수

각 항목은 실제 게임 크기와 3배 표시를 모두 살핀다. 비교 보드와 자동 픽셀/프레임 수치는 위치를 찾는 보조 자료이며 시각 승인 자체가 아니다. 미승인 후보가 보이면 후보임을 기록하고 승인 원화로 승격하지 않는다.

| 항목 | 직접 살필 것 | 결과 | 캡처/메모 |
|---|---|---|---|
| 원화 identity | 얼굴, 귀, 머리/포니테일, 의상 색·구성, 장갑/장화가 동일 캐릭터로 유지되는지 | ☐ pass ☐ fail ☐ not_tested | |
| 보폭 | 달리기 반복에서 지지발과 앞/뒤 리드가 번갈아 바뀌는지, 발 접지·골반이 튀지 않는지 | ☐ pass ☐ fail ☐ not_tested | |
| 회전 | 방향 전환과 Num5 회전 동작에서 몸통·골반·팔 교차·지지발이 읽히는지 | ☐ pass ☐ fail ☐ not_tested | |
| 프레임 팝 | 루프 경계와 상태 전환에서 신체/머리카락/무기 실루엣이 순간 이동하거나 깜빡이지 않는지 | ☐ pass ☐ fail ☐ not_tested | |

관련 비교 자료: [run 보폭 게이트](player_run_cycle_gate.md), [방향 전환 게이트](player_turn_motion_gate.md), [Num5 회전 원화 게이트](player_skill2_spin_art_gate.md), [통합 원화 결정 게이트](m5_art_visual_decision_gate.md). 기존 보폭 후보들이 미수용 상태라는 제약도 확인하고, 새로운 인수에서 결함이 보이면 그대로 기록한다.

## 종료 판정과 증거 보관

- [ ] 모든 입력/표시/체력바/스킬/편집기/원화 체크가 직접 관찰되어 `pass`다.
- [ ] 실제 물리 키보드·마우스 조작을 검사자가 확인했다.
- [ ] 창 포커스 상실과 복귀 후 입력 회복을 확인했다.
- [ ] `input-events.jsonl`, `manual-review.json`, 화면/편집기/원화 증거를 보존했다.
- [ ] 자동 입력·자동 GUI 결과만으로 pass를 적지 않았다.

하나라도 실패/미실시거나 증거가 불명확하면 전체를 `BLOCKED_UNVERIFIED`로 유지한다. 무인 실행은 언제나 종료 코드 `2`이며 인수 완료가 아니다. 기록 완료(`MANUAL_REVIEW_RECORDED`)도 별도 제품/원화 승인 절차를 자동 통과시키지 않는다.
