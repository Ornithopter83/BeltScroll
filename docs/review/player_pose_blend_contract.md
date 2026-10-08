# 독립 Player 포즈 블렌더 계약

## 범위와 승인 경계

`scripts/player/player_pose_blender.gd`는 독립 `Node2D`이며 내부에 `Sprite2D` 두 개를 생성합니다. Player 씬과 기존 `VisualAnimator`에는 연결하지 않습니다. idle에는 본편 사용 승인을 받은 v8 clean 정지 이미지(`elven_fighter_reference_v8_clean_candidate_1254x1254.png`)만 기본 사용합니다. 공격 키포즈는 기본 등록되지 않습니다. 호출자가 시각 승인을 마친 뒤 `approve_pose_texture(action, phase, texture_path_or_texture)`를 명시적으로 호출한 키만 노출할 수 있습니다.

공격 상태 키는 `attack1`, `attack2`, `attack3`이고 단계는 `startup`, `contact`, `recovery`입니다. `set_pose("idle")`는 안전 정지 이미지로 이동합니다. 잘못된 키, 승인되지 않은 키, 로드되지 않거나 alpha가 비어 있는 이미지는 모두 표시하지 않고 v8 clean으로 대체합니다. v2 키포즈 sheet, safe/candidate 공격 이미지는 기본 목록에 연결하지 않습니다.

## 배치와 전환

두 Sprite는 각 텍스처의 실제 alpha used rect를 구하고, alpha bounds의 수평 중앙과 최하단을 발점으로 사용합니다. 이 발점이 `common_foot_anchor`에 오도록 중심 피벗 기준 표시 위치를 계산합니다. 투명 상하좌우 여백이 서로 다른 이미지도 동일한 발 위치를 공유하며 `set_facing_left`는 alpha bounds의 좌우 변환을 위치 계산에 반영합니다. `sprite_scale`은 기본 v8 표시 배율입니다.

일반 포즈 변경은 기본 75ms의 선형 alpha 교차 전환을 사용합니다. 두 레이어를 넘지 않으며, 전환 중 재요청은 현재 더 많이 보이는 Sprite를 이어받습니다. `set_ko(true)`와 `interrupt_to_idle()`은 진행 중 전환을 즉시 끝내고 안전 idle로 복귀합니다. 기본 process mode는 `inherit`이므로 SceneTree pause 동안 전환 시간이 멈춥니다. KO 이후 공격 포즈는 `clear_ko()`로 KO를 해제하기 전까지 무시됩니다.

## 독립 검증

`tests/player_pose_blender_smoke.gd`는 파일 자산을 만들거나 실제 공격 그림을 사용하지 않고, 투명 여백이 서로 다른 절차형 RGBA 사각형 fixture를 메모리에서 생성합니다. 승인 등록, 세 공격의 세 phase 전환과 시간, alpha bounds 발 정렬, 좌우 반전, 페이드 중단 후 최신 요청, SceneTree 일시정지/재개, KO 복귀, 누락/미승인/잘못된 자산 fallback을 확인합니다. Suite 등록은 `tools/smoke_suite.cmd`의 headless smoke 목록에 있습니다.

이 smoke는 렌더링된 실제 공격 그림의 시각 승인, Player 씬 통합, 공격 타이밍 정책을 승인하지 않습니다. 추후 승인된 개별 키포즈를 등록하는 단계 전까지 본편 연결은 별도 작업입니다.
