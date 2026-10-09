# M6C 보스 후보 시각 검수 게이트

## 검수 범위와 승인

검수 도구는 플레이 중 사용하는 Raider 원화 `forest_raider_reference_v1_final_candidate_1254x1254.png`와 확보된 보스 원화 `ruins_warden_boss_v1_candidate_1254x1254.png`를 직접 대조합니다. 기본 후보 경로는 `assets/art/enemies` 아래 파일로 명시되어 있습니다. 존재하지 않는 `assets/art/bosses` 폴더를 탐색하지 않습니다.

보스 후보는 검수용 PNG로만 읽습니다. 게임 씬, 리소스 참조 또는 보스 외형은 변경하거나 자동 등록하지 않습니다. 이 게이트를 통과해도 보스의 최종 외형 승인은 사람이 별도로 내려야 합니다.

## 현재 비교 결과물

`assets/art/review/m6c_boss_visual_comparison.png`는 Raider와 보스 후보를 한 화면에 배치하고, 투명 체크 배경, 공통 바닥선, alpha 실루엣 겹침, 자동 측정 결과를 표시합니다. 양쪽에 `scenes/enemies/forest_raider.tscn`의 실제 `RaiderArt` 배율 `0.446928`를 똑같이 적용하여 게임 표시 크기 차이를 보존합니다. 패널에 맞춰 각각 별도로 확대/축소하지 않습니다. 검수판 크기 때문에 패널 안에서 잘리는 경우도 검수 지적에 포함해야 합니다.

현재 후보 검사 결과: RGBA 투명 픽셀 있음, alpha 경계는 캔버스에 닿지 않음, 최소 여백 5px(필요 8px에 미달), Raider 대비 실루엣 높이 1.387배/너비 1.645배, 발 anchor y 차이 86.7 표시 px, 정규화 silhouette IoU 0.536. 따라서 도구 상태는 `REVIEW_REQUIRED`이며 외형 승인 상태가 아닙니다. 사람은 실제 표시 크기, 바닥 배치와 후보 이미지의 표현을 검수판에서 확인해야 합니다.

측정 항목은 다음과 같습니다.

- 디코딩 포맷, 부분 투명 픽셀 존재 여부, alpha 경계의 최소 여백과 캔버스 가장자리 접촉 여부
- 공통 게임 배율로 환산한 실루엣 너비/높이 및 Raider 대비 크기 비율
- 바닥에 닿는 최하단 alpha 행의 anchor y 차이(공통 게임 배율의 화면 픽셀)
- 각 alpha 실루엣을 자체 경계 상자에 정규화한 mask IoU와 색상 참고값
- 체크 무늬 위 투명도 및 발 기준선을 포함한 시각 비교

실루엣 IoU/색상 차이는 서로 다른 역할의 인물을 기계적으로 합격시키기 위한 점수가 아닙니다. 이 결과물은 후보의 잘림, 투명도, 기준 대비 크기 및 anchor를 빠르게 검토하기 위한 보조 자료입니다.

## 결과물 재생성

저장소 루트에서 실행합니다. 별도 후보를 지정하지 않으면 문서 상단의 실제 후보 경로를 사용합니다.

```powershell
godot --headless --path . --script res://tools/build_m6c_boss_visual_review.gd
```

대조 입력을 바꾸려면 `--reference <경로>`, `--candidate <경로>`, 출력 위치를 바꾸려면 `--output <경로>`를 `--` 뒤에 지정합니다. 지정 후보가 없거나 읽을 수 없으면 검수판을 생성하지 않고 실패 종료합니다. 품질 검토 항목이 기준에 걸리면 측정 결과를 저장하고 종료 코드 1을 반환합니다.

## 스모크 검증

```powershell
godot --headless --path . --script res://tests/m6c_boss_visual_review_smoke.gd
```

스모크는 합성 입력으로 alpha/잘림/실루엣/anchor 측정과 PNG 저장을 확인하고, 실제 기본 Raider 및 Ruins Warden 후보가 열리며 실제 후보가 검수 지표에 포함되는지 확인합니다. 사람의 외형 승인을 대신하지 않습니다.
