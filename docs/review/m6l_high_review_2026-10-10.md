# M6L HIGH 검토 결과 (2026-10-10)

## 최종 판정

**BLOCKED — 자동화된 Window 동작과 코드 검증은 통과했지만, HQ 인수 조건인 기준 MP4 프레임 비교, 물리 입력, F6 수동 검토와 사람의 시각 승인이 확보되지 않았다.** #650 보행 원화는 미승인 상태다. 임시 전신 변형을 실제 다리 관절 보행이나 승인 원화로 보지 않는다.

## #650 보행 후보 연속 프리뷰

- 기존 `run_stride` v1–v5는 모두 같은 전진 보폭 phase로 표시하고 **FAIL** 처리한다. v2의 파일명에 `opposite`가 있어도 실제 판정은 기존 반복 보폭 분류를 따른다.
- 확보된 `walk_opposite_stride`와 존재하는 `walk_passing`은 별도 미승인 프레임으로 표시한다. passing은 파일이 있을 때만 추가한다. `_safe` 매트 파생본은 프레임에서 제외하고, 본편 manifest·allowlist·Player에 넣지 않는다.
- 192px 프리뷰 스모크가 Godot 4.7.2에서 통과했다. 후보 처리 `748.9ms`; Space 재생·일시정지와 좌우 stepping, 후보 발견, 중복·동일 phase FAIL 표시, 격리 조건을 검사했다. Window 캡처 `frame_00.png`–`frame_06.png`는 `.godot/m6l_high_review_captures/`에 있다.
- 반대 보폭과 passing은 각각 한 장뿐이다. 교대 접지, 든 발, 반대 팔, 지지발 고정, 골반 높이와 좌우 이동의 사이클 검증 근거가 없어 통과시키지 않는다.

## #651 PlayerArt ↔ PoseBlender 연속 전환

최신 GUI Window 테스트 `tests/m6l_pose_handoff_window_smoke.gd`는 `frame_post_draw` 연속 프레임 69개를 수집하고 **fail=0**이었다. 실제 출력은 다음과 같다.

- 완결 외부 handoff 7회: `111.11–116.67ms` 표본 간격. 런타임 전환 상수 `105ms` 유지.
- 최대 인접 프레임 알파 변화 `0.40476`; 합성 유효 알파 오차 `0.00005`.
- 최대 발점 오차 `0.00006px`; 회전 변화 `0.17498rad`; 크기 변화 `0.04449`.
- 기존 공격 hitbox 활성시간 `[0.105, 0.12, 0.14]`와 KO·피격·스킬·공격 우선순위 유지 확인.

알파 수치가 이중 합성 오류를 보이지 않아도 서로 다른 실루엣의 겹침이 미관상 잔상인지 자동 검증할 수 없다. 해당 시각 승인은 계속 대기다.

## #652 Num4 / Num5 실 Player 비교

`tests/m6l_skill_readability_window_smoke.gd`를 실제 Window에서 통과시켰다. 두 production Player의 준비·활성·회복, 실제 판정과 대상 적중, 취소·피격·KO 후 효과 소거를 확인했다. Num4는 직선으로 70px 초과 전진해 실제 직사각형 hitbox로 대상을 맞혔다. Num5는 시작 위치에서 8px 이내에 머물며 회전하고 실제 원형 hitbox로 대상을 맞혔다. 회전 최대 절댓값 `0.55752rad`, 최대 표본 간 변화 `0.15846rad`다. 실제 Window 캡처는 `.godot/m6l_high_review_skill_captures/`에 있다.

이 자동 결과는 이동·상태·판정 확인이지 몸 실루엣만으로 구분된다는 사람의 승인 기록이 아니다. F6 수동 관찰이 수행되지 않았으므로 비교장 검수표와 최종 판정은 보류다. 후보 원화는 분리 참고패널에만 표시한다.

## #653 기준 MP4 프레임 증거

- 입력 MP4 크기 `62,174,216 bytes`, SHA256 `7C1129069189F35E4BBE1FEBB789D0CA552A45DF688320AE6A93C3DF13F596BE`.
- 최신 decoder probe: ffmpeg/ffprobe 경로 없음, Media Foundation 구성요소는 있으나 `ExtractionReady=false`, WMP COM 가능, 검증된 순차 디코더 없음. probe와 smoke는 통과했고 상태는 **UNVERIFIED**다.
- 타임스탬프 순차 디코딩을 보증할 수 없으므로 원본 프레임, PTS, 프레임 차이 비교 목록은 생성하지 않았다. 반복 프레임이나 임의 seek를 증거로 인정하지 않았다.

## HIGH 회귀와 수정

- 공격 상태의 `inbetween` 설명 분기가 일반 공격 설명에 가려져 있던 순서를 수정했다. 접촉 원화의 승인 출처와 임시 변형 상태를 별도로 반환한다.
- `player_visual_animator_smoke.gd`는 zero-delta 호출 뒤 105ms 전환 완료를 요구하던 검증 타이밍을 실제 경과 시간 호출로 고쳤다. 재실행에서 synthetic attack frame 경계 이동과 스킬 중단 뒤 PlayerArt 복귀를 모두 통과했다.
- 후보 미리보기는 파일명에 `stride`가 없는 `passing`도 찾아 추가하며 `_safe` 변형을 걸러낸다. 알파 픽셀 스캔은 packed RGBA 경로를 사용한다.
- Num5의 효과 오프셋 누적을 제거하고 공격 지지점 정렬을 두 PoseSprite에 모두 적용했다. 이 수정들은 hitbox 활성 시간이나 애니메이션 우선순위를 바꾸지 않는다.
- 기존 QA가 실행한 `editor_executable_parse_smoke.ps1`와 자동 GUI 모드 스모크는 통과했다. WinForms 수동 acceptance는 `blocked_unverified`이며, 이번 변경은 `editor/*.cs`·Num4 파서·WinForms 경로를 수정하지 않았다.

## 실행 결과

- 통과: `tests/m6l_walk_cycle_preview_smoke.gd`
- 통과: `tests/player_visual_animator_smoke.gd` — actual Window, 전체 체크 통과
- 통과: `tests/m6l_pose_handoff_window_smoke.gd` — actual Window, 69 프레임, fail=0
- 통과: `tests/m6l_skill_readability_window_smoke.gd` — actual Window, 실제 Player/판정/중단 처리
- 통과: `tests/m6l_reference_video_extraction_smoke.ps1` — SHA·UNVERIFIED 처리와 게이트 확인
- 빌드: 저장소 빌드 매니페스트가 없어 건너뜀

Godot 로그 파일과 Windows 인증서 저장소를 열지 못했다는 환경 로그가 있었지만, 위 스크립트들은 해당 로그 뒤에 결과를 출력하고 종료했다. 이 검토는 Godot GUI Window 스크립트를 직접 실행했다. 에디터 F6 조작 및 실제 키보드·컨트롤러 물리 입력은 확인하지 않았다.
