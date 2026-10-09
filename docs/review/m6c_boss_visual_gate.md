# M6C 보스 시각 비교 검수

## 목적과 승인 경계

독립 도구가 기존 Raider 기준 원화와 선택한 보스 후보를 같은 표시 영역에 배치하고, 실루엣·표시 크기·얼굴·갑옷의 시각 차이와 발 anchor를 검토할 수 있게 합니다. 후보 PNG를 게임 장면이나 리소스 연결에 반영하지 않습니다. 본편에 쓰려면 사람이 이 검수판을 확인하고 별도로 승인해야 합니다.

## 현재 검수판

`assets/art/review/m6c_boss_visual_comparison.png`는 `forest_raider_reference_v1_clean_1254x1254.png`만으로 만든 기준 원화 검수판입니다. 현재 `assets/art/bosses`에 PNG/WebP 후보가 없어 **후보 부재**가 표시됩니다. 따라서 보스 후보 차이 분석은 아직 수행되지 않았습니다.

## 실행

저장소 루트에서 후보 자동 검색과 기준 원화 전용 검수판 생성을 실행합니다.

```powershell
godot --headless --path . --script res://tools/build_m6c_boss_visual_review.gd
```

도구는 `assets/art/bosses` 안의 첫 PNG/WebP를 후보로 사용합니다. 임의 경로의 후보와 출력 위치를 지정하려면 다음처럼 실행합니다.

```powershell
godot --headless --path . --script res://tools/build_m6c_boss_visual_review.gd -- --candidate res://path/to/boss.png --output res://assets/art/review/m6c_boss_visual_comparison.png
```

추가 옵션 `--reference <path>`로 Raider 기준 이미지를 바꿀 수 있습니다. 후보가 없으면 정상 종료 코드 0과 함께 기준 원화 검수판을 만듭니다. 지정 후보가 잘못되었거나 후보 품질 기준에 걸리면 출력은 저장하되 종료 코드 1로 검토 필요를 알립니다.

## 측정 항목

- PNG 디코딩 후 RGBA 형식인지, 투명 픽셀이 포함되는지, alpha 경계가 캔버스 테두리에 닿는지와 최소 바깥 여백을 기록합니다. alpha 경계는 alpha 0.05 초과 픽셀 기준입니다.
- alpha 경계 상자 크기로 후보와 기준의 표시 크기 비율을 비교합니다. 높이 비율 0.5~2.0 바깥은 검토 대상으로 표시합니다.
- 두 alpha 실루엣을 각각 정규화해 계산한 64×64 mask IoU와 얼굴·갑옷 영역 평균 RGB 차이를 보여 줍니다. 색차는 자동 합격 판정 대신 시각 검토 자료입니다.
- 원본 캔버스 기준 발 alpha anchor y 차이를 비교합니다. 기준 원화 높이의 4%를 넘는 차이는 검토 대상으로 표시합니다.
- 후보와 기준 실루엣을 겹친 패널에서 파랑은 기준만 있는 영역, 주황은 후보만 있는 영역, 빨강은 겹치는 영역입니다.

이 수치는 자동 채택 점수가 아닙니다. 표시 크기, 얼굴/갑옷의 정체성, 실루엣 적합성은 사람이 최종 판단합니다. 합성 이미지 검증은 아래 스모크 테스트에서 별도로 수행합니다.

## 독립 스모크 테스트

```powershell
godot --headless --path . --script res://tests/m6c_boss_visual_review_smoke.gd
```

테스트는 메모리에서 합성 Raider형 기준과 변형 후보를 만들고 RGBA/투명도, 여백·잘림, 실루엣 유사도, 얼굴·갑옷 RGB 차이, 발 anchor, 후보 부재 경로와 저장 PNG 재열기를 확인합니다. 캔버스 가장자리에 닿는 합성 후보가 검토 실패로 표시되는지도 검사합니다.
