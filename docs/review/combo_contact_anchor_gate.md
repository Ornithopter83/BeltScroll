# 콤보 접촉 포즈 anchor 검수 게이트

## 구현 범위

기존에 승인된 attack1/attack2/attack3 접촉 이미지에만 포즈별 접지 후보를 설정합니다. 각 후보는 그림에서 보이는 앞발의 지면 접점이며, 반대 방향에서는 미러된 발을 사용합니다. 후보점은 정규화 이미지 좌표이며 공통 전투 기준점과 별도 저장됩니다. alpha bounds의 최하단은 후보점이 등록되지 않은 독립 블렌더 이미지에서만 기존 fallback으로 사용됩니다.

VisualAnimator는 idle 기준점 주위로 회전·스케일을 시간 기반 보정하고, 공격 단계 전환의 실제 phase 시계(남은 시간)를 계속 따릅니다. 두 이미지 crossfade는 3차 smoothstep으로 시작/끝 속도를 낮춥니다. Sprite 레이어는 각자 포즈별 후보점을 공통 전투 기준점에 정렬합니다. 새 중간 원화는 등록하지 않았고, 연결 구간의 임시 transform은 승인 원화 프레임으로 표시하지 않습니다.

물리 Player 위치, `Hitboxes` 모양/위치와 활성 시점, 피해 계산, hit-stop, 콤보 버퍼의 코드는 변경하지 않았습니다.

## 회귀 확인

| 경우 | 확인 항목 |
| --- | --- |
| 우향 2→3타 | crossfade 양쪽 후보점 정렬, 바닥점 미끄러짐, 물리 root/hitbox 위치 유지, 몸통 회전 변화 |
| 좌향 2→3타 | 위와 동일한 항목과 반대 방향 회전 |
| 중단 | 새 포즈 요청이 기존 2레이어 전환을 인계하고 최신 포즈에 정착 |
| KO | 즉시 안전 idle로 복귀하고 KO 중 포즈 요청 무시 |

`tests/player_pose_blender_smoke.gd`는 임시 RGBA fixture에서 alpha 최하단과 다른 명시 후보를 두 방향으로 확인합니다. `tests/player_visual_animator_smoke.gd`는 Player 씬에서 좌우 2→3타의 수치상 발 anchor/root/hitbox를 비교하고 기존 hitstun/KO 중단도 재검사합니다. 이 자동 검사는 픽셀 단위 화면 캡처의 시각 검수는 아니며, 후보 좌표의 아트 디렉터 승인도 뜻하지 않습니다. 두 후보점은 현재 승인된 그림에 대한 동작 보정값이며 새 그림/프레임을 승인하지 않습니다.

## 실행

```powershell
godot --headless --path . --script res://tests/player_pose_blender_smoke.gd
godot --path . --script res://tests/player_visual_animator_smoke.gd
```
