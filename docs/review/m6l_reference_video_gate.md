# M6L 기준 영상 프레임 증거 게이트

## 판정

**UNVERIFIED — 기준 MP4의 순차 프레임 추출을 이 환경에서 신뢰성 있게 완료하지 못했다.** 반복 프레임을 정상 추출로 간주하거나, 임의 seek 결과를 타임라인 증거로 기록하지 않았다.

## 입력 영상 식별

| 항목 | 확인값 |
|---|---|
| 파일 | `temp/ProjectHub/attachments/30319a1f00274afb8876fbb88d14dd9ahq/BeltScroll (DEBUG) 2026-10-10 12-23-33.mp4` |
| 크기 | 62,174,216 bytes |
| SHA256 | `7C1129069189F35E4BBE1FEBB789D0CA552A45DF688320AE6A93C3DF13F596BE` |

## 디코더 조사와 제한

확인 당시 `ffmpeg`, `ffprobe`, VLC, mpv, GStreamer 실행 파일은 PATH에서 발견되지 않았다. Windows의 `mfplat.dll`과 `mfreadwrite.dll`은 존재했고 Windows Media Player COM 객체 생성도 가능했다. 다만 이 환경에서 검증된 Media Foundation 순차 프레임 내보내기 경로는 구현·확인되지 않았다. WMP COM의 재생 위치와 화면 캡처만으로는 각 이미지가 새로 디코딩한 프레임인지, 원본 presentation timestamp가 무엇인지 보증할 수 없다. 그러므로 이를 대체 추출기로 쓰지 않았다.

## 추출 및 검증 도구

`tools/extract_m6l_reference_video_frames.ps1`은 MP4 SHA256을 계산하고 디코더를 조사한다. ffmpeg가 없으면 `UNVERIFIED` 매니페스트를 출력 디렉터리에 기록하고 종료 코드 2로 끝난다. ffmpeg가 있으면 단일 프로세스에서 입력을 처음부터 순차 디코딩하며, 프레임 PTS 기반으로 간격을 선택하고 `showinfo`의 source `pts_time`과 PNG를 기록한다. 각 PNG의 SHA256, 인접 이미지의 평균 RGB 절대 차이, 엄격한 timestamp 증가, 해시 중복 여부를 매니페스트에 남긴다. 모든 조건을 통과한 경우에만 `VERIFIED`다.

재현 명령 (Windows PowerShell 5.1):

```powershell
$video = Get-ChildItem -Path .\temp\ProjectHub\attachments -Recurse -File -Filter *.mp4 | Select-Object -First 1
& .\tools\extract_m6l_reference_video_frames.ps1 -InputPath $video.FullName -OutputDirectory .\temp\m6l_reference_frames -IntervalSeconds 0.25
```

Smoke 검사:

```powershell
& .\tests\m6l_reference_video_extraction_smoke.ps1
```

## 비교 증거 목록

| 자료 | 경로 또는 상태 | 비교 용도 |
|---|---|---|
| 기준 영상 | 위 첨부 MP4, SHA256 기록 완료 | 입력 원본 식별 |
| 추출 프레임 및 PTS 목록 | 미생성 — 디코더 부재로 `UNVERIFIED` | 시간순 원본 동작 비교 |
| 추출 매니페스트 | 추출 스크립트를 실행할 때 출력 디렉터리에 생성 | 입력/프레임 해시, timestamp, 이미지 차이, 판정 |
| M6K 게임 Window 캡처 시트 | `assets/art/review/m6k_motion_contact_sheet.png` (M6K 캡처 도구 출력) | idle, walk, attack 및 동작 단계 대조 |
| 이후 Window 캡처 | 아직 연결된 증거 없음 | 같은 동작·시간대의 기준 프레임과 비교 |

M6K 시트의 경로는 `tools/capture_m6k_motion_window.gd`에 설정된 출력 경로다. 실제 파일 존재 여부는 이 판정에서 증거로 간주하지 않았다. 추출이 검증된 뒤 매니페스트의 `M6KWindowComparisonEvidence` 배열에 캡처 파일과 비교 메모를 추가한다. 현재는 비교 가능한 원본 프레임/타임스탬프가 없으므로 시각적 유사도나 시간 정렬을 판정하지 않는다.
