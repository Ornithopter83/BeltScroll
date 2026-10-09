# 플레이어 프레임 레지스트리 승인 게이트

## Manifest 계약

`data/art/animation_manifest.json`은 외부 편집기 `schema_version: 1` 계약의 `clips`, `frames`, `texture`, `phase`, `duration`, `foot_anchor`, `approval_state` 필드를 사용한다. `foot_anchor`는 프레임 alpha 경계의 수평 중앙과 최하단을 뜻하는 `alpha_bottom_center`로 기록한다. PoseBlender는 동일한 alpha 경계 기준으로 발 위치를 맞춘다.

`PlayerAnimationBank`는 manifest만 읽고 파일/후보 폴더를 검색하지 않는다. 승인된 기본 allowlist는 v8 idle과 세 기존 접촉 키포즈로 제한한다. 공격 시작/회수/중간은 `temporary` 또는 `unapproved`로 남겨 승인 프레임에 등록하지 않는다. v5 접촉, v6 clean 후보, attack2 중간본은 파일이 있어도 `approval_state`가 승인 상태가 아니므로 로드되지 않는다. 향후 manifest에 다른 그림을 `approved`로 표시해도 현재 기본 allowlist 밖이면 등록을 거부한다.

## 시간과 표시 연결

VisualAnimator는 bank의 startup/contact/recovery duration을 공격 phase clock에 적용한다. contact duration은 PlayerController의 active hitbox window와 일치한다. 공격 phase를 고르는 기존 `set_timed_pose` 및 `register_pose_frame` API를 유지한다. 현재 승인된 각 contact phase는 단일 실제 텍스처를 사용한다. 시작/중간/회수 구간에는 v8 fallback과 명시적인 임시 transform status를 유지하며, 등록된 실제 프레임으로 보고하지 않는다.

VisualRoot가 좌우 반전을 담당하므로 PoseBlender 내부 `flip_h`는 통합 시 꺼 둔다. 독립 bank 등록 smoke는 직접 좌우 반전된 PoseBlender Sprite의 alpha 발 anchor도 common anchor에 맞는지 확인한다.

## 독립 검증

```powershell
godot --headless --path . --script res://tests/player_animation_bank_smoke.gd
```

Smoke는 schema 및 파일 존재, 세 contact texture, startup/contact/recovery 시간, active hitbox window와의 시간 일치, 누락 phase 비등록, alpha 발 anchor, 좌우 반전, v5 후보 비등록을 검사한다. 자동 smoke는 새 중간/시작/회수 원화의 시각 승인으로 간주하지 않는다.