# M6K Motion Video Gate

## 범위와 실행

첨부 기준 영상은 `temp/ProjectHub/attachments/30319a1f00274afb8876fbb88d14dd9ahq/BeltScroll (DEBUG) 2026-10-10 12-23-33.mp4`이며, 파일 크기는 62,174,216 bytes입니다. Windows Media Foundation에서 MP4를 열어 2560×1440 영상, 약 26초 길이를 확인했습니다. Godot 4.7.2의 실제 Window Viewport는 1280×720으로 고정했습니다. 프레임을 같은 크기로 취득한 뒤 640×360 셀로 축소해 4×4 시트에 담습니다. 시트의 왼쪽 위부터 아래 순서로 다음 상태를 배치합니다.

| 칸 | 캡처 상태 | 확인 항목 |
|---:|---|---|
| 1–2 | 대기, 걷기 | 정지 기준과 이동 중 포즈 |
| 3–5 | 기본 공격 1·2·3타 | 단계별 타격 실루엣 |
| 6 | 연속 공격 후 걷기 | 콤보 종료와 이동 복귀 |
| 7–9 | Num4 준비·접촉·회복 | 대시 계열 기술 단계 |
| 10–12 | Num5 준비·접촉·회복 | 회전 계열 기술 단계 |
| 13–14 | Num4 중단 직전·이동 복귀 | KP3 가드 입력 뒤 기술 취소와 이동 입력 |
| 15–16 | Num5 중단 직전·이동 복귀 | KP3 가드 입력 뒤 기술 취소와 이동 입력 |

캡처 도구는 `scenes/game/main.tscn`을 실제 창으로 실행하고, 입력 이벤트와 렌더된 Window Viewport를 사용합니다. 공격 단계와 기술 단계는 물리 상태가 도달한 뒤 저장하고, 각 캡처의 물리 프레임 번호를 출력합니다. Num4/Num5 중단은 실제 KP3 가드 입력 뒤 KP_D 이동을 확인합니다. 캡처와 smoke는 사람의 시각 승인을 대체하지 않습니다.

## 결과

| 항목 | 판정 | 기록 |
|---|---|---|
| 실제 창 프레임 | CAPTURED | 대기, 걷기, 1·2·3타, Num4/Num5 3단계, 각 기술 중단 전후 총 16장. 모두 1280×720 원본 viewport입니다. |
| 단계와 복귀 | AUTOMATED | 2026-10-10 수정 후 실제 Window에서 다시 캡처했습니다. 기본 공격 active 대표 캡처는 physics frame 138/159/186, Num4 준비·접촉·회복은 296/300/305, Num5는 337/345/355에 저장됐습니다. 가드 중단 후 이동 복귀는 Num4 396→428, Num5 449→482입니다. |
| 발 미끄러짐 | UNVERIFIED | 정지 프레임 시트만으로 발 접지점과 월드 이동의 시간 상관을 확인할 수 없습니다. 기준 MP4에서 재생 구간을 얻지 못했습니다. |
| 포즈 점멸 | PARTIAL | PlayerArt/PoseBlender 교차 표시 발 앵커는 보행·공격 smoke에서 각각 확인했습니다. 16장의 대표 프레임은 연속 렌더 시점의 밝기·가시성 변화를 보여 주지 않아 게임 실행 중 점멸 여부는 미검증입니다. |
| 전환 시간 | PARTIAL | phase 대표 캡처 간 간격은 Num4가 3/6 physics frame, Num5가 8/11 physics frame입니다. 컨트롤러에 선언된 기본 타격 구간은 준비 0.075/0.085/0.10초, 활성 0.105/0.12/0.14초, 회복 0.20/0.22/0.28초이며, Num4는 0.16/0.12/0.42초, Num5는 0.22/0.18/0.55초입니다. 캡처 프레임 간격은 실제 phase 경계 시각과 같지 않으므로 정밀 전환 시간 측정으로 간주하지 않습니다. 영상 기준과 맞춘 시각 승인값도 아닙니다. |
| 기술별 실루엣 | PARTIAL | 실제 Player가 포함된 gameplay Window를 수정 후 다시 캡처했습니다. 별도 1920×1080 Window에서 실제 PlayerArt 텍스처와 Num4 직선 cue/Num5 원호를 나란히 표시해 관계를 확인했습니다. 기준 MP4의 대응 타이밍 화면 및 최종 가독성 승인은 미확보입니다. |
| 사람 시각 승인 | PENDING | 자동 캡처나 smoke 결과를 승인으로 세지 않았습니다. |

기준 MP4는 누락되지 않았습니다. 다만 Windows 미디어 디코더로 임의 시각 seek 후 만든 프레임이 모두 동일하게 렌더되어 타임라인 표본으로 신뢰할 수 없었습니다. 그래서 기준 영상 대조는 `UNVERIFIED`이며, 존재하지 않는 비교 결과를 채우지 않았습니다.

## 렌더링 및 기준 영상 한계

초기 검수에서 `player_skill1_dash_visual.gd`의 `interrupted`·`point` 타입 추론 파서 오류가 확인되어 이번 HIGH에서 두 타입을 명시했습니다. 이후 Player scene load, 실제 Skill1Hitbox 명중·접촉 효과·취소/피격 정리 smoke와 본편 gameplay Window 16상태 재캡처가 모두 성공했습니다. 따라서 이전 helper `new()` 실패는 재현되지 않습니다.

기준 MP4는 존재하고 SHA256은 `7C1129069189F35E4BBE1FEBB789D0CA552A45DF688320AE6A93C3DF13F596BE`입니다. Windows 미디어 디코더에서 임의 시각 seek 후 얻은 프레임이 반복되어 시간별 비교에 사용할 수 없었습니다. 이 환경에는 ffmpeg/ffprobe도 없어 신뢰할 수 있는 동일 타이밍 표본을 만들지 못했습니다. 기준 영상 비교와 사람의 최종 시각 승인은 `UNVERIFIED`/`PENDING`으로 남깁니다.

## 산출물과 재실행

- 캡처 스크립트: `tools/capture_m6k_motion_window.gd`
- 검증 스크립트: `tests/m6k_motion_window_smoke.gd`
- 비교 contact sheet: `assets/art/review/m6k_motion_contact_sheet.png`
- 창 캡처 실행: `godot --path . --script res://tools/capture_m6k_motion_window.gd`
- smoke 실행: `godot --headless --path . --script res://tests/m6k_motion_window_smoke.gd`

스모크는 성공해도 이미지가 자동 시각 승인됐다고 표시하지 않습니다. 기준 비교 및 육안 승인 상태는 위 표와 같이 명시적으로 보류/미검증입니다.
