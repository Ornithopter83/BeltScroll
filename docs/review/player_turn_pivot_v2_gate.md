# Player turn pivot v2 review gate

## 상태: 확보

v2 원본: `res://assets/art/player/elven_fighter_turn_pivot_v2_candidate_1254x1254.png` (있음)  
safe 후보: `res://assets/art/player/elven_fighter_turn_pivot_v2_safe_candidate_1254x1254.png`  
비교 이미지: `res://assets/art/review/player_turn_pivot_v2_comparison.png` (624×480)

### 원본 provenance와 후보

SHA256 `e4bbfe3684cb49c70604a785e6a2f4e1a1f832e971635337a9ec56dbe40525a3`, 원본 788226 bytes. 원본 파일 바이트는 수정하지 않았다.

후보 처리: 1254×1254 RGBA8; 알파 bounds [P: (129, 90), S: (995, 1074)]; 여백 [129, 90, 130, 90] px; 고립 alpha 제거 133개; 결과 고립 alpha 0개.

### 비교 배치

3열×2행의 각 카드는 전체 원본 캔버스를 같은 192×192 픽셀로 축소했다. 열 순서는 v8 idle, 기존 rear-mid v1, 원본 v2이며, 위 행은 원래 방향, 아래 행은 좌우 반전이다. 반전은 각 전체 캔버스 이미지에 한 번만 적용했다. v2 열은 확보된 원본 바이트를 직접 읽어 표시했다.

### 시각 검토 기록

- v1 rear-mid는 idle보다 alpha bounds 폭이 14.4%, 높이가 13.5% 크다. 큰 보폭과 들린 부츠가 달리기로 읽히는 미수용 후보 상태를 유지한다. v1은 이번 작업에서 수정하거나 수용 처리하지 않았다.
- v2 시각 메모: Window 캡처에서 두 부츠 landmark는 약 61 px 떨어져 골반 아래 가까이 모여 보인다. anchor 정렬은 오른쪽 부츠 landmark (770,1135)를 지지발로 가정해 맞춘 결과이므로 실제 뒤꿈치 접촉은 사람 확인이 필요하다. v8 idle 대비 원본 alpha bounds 폭은 약 18.9 percent 좁고 높이는 약 11.0 percent 커서 크기 팝 우려가 있다. 머리카락·뾰족 귀·의상 색과 형태는 같은 캐릭터로 읽히지만, 회전축의 자연스러움과 뒤꿈치 접촉은 미승인 상태다.
- 회전축과 뒤꿈치 접촉, 반대 방향 mirror 대응: 미승인 — 반대 방향 mirror 접점은 Window 캡처와 비교판에서 확인 가능하나 사람 검토 필요
- 얼굴·귀·의상 identity 및 idle 대비 크기: identity는 같은 캐릭터로 보임; alpha bounds가 idle보다 좁고 높아 크기 팝 우려, 사람 수용 보류
- foot anchor와 지지발 이동: anchor 좌표는 (960,790) 고정; 지지발 landmark를 수동 가정해 정렬했으므로 실제 뒤꿈치 접촉·이동은 사람 검토 필요
- 사람 검토 전 본편, manifest, allowlist에 등록하지 않는다.

