# 플레이어 프레임 레지스트리 승인 게이트

## 편집기 schema v1 계약

`data/art/animation_manifest.json`과 BeltScroll Animation Workspace JSON은 다음 구조를 사용한다.

```json
{
  "schema_version": 1,
  "clips": [{
    "id": "attack2",
    "frames": [{
      "phase": "contact",
      "duration": 0.12,
      "texture": "textures/frame.png",
      "foot_anchor": { "x": 0.5, "y": 0.92 },
      "approval_state": "review"
    }]
  }]
}
```

`id`는 비어 있지 않고 문서 안에서 중복되지 않는 문자열이다. `action` 별칭은 허용하지 않는다. `frames`는 하나 이상의 객체를 가진 배열이며, 각 프레임은 `phase`, `duration`, `texture`, `foot_anchor`, `approval_state`를 모두 포함한다. 공격 phase는 `startup`, `inbetween`, `contact`, `recovery`이고, idle clip만 `idle` phase를 쓴다. duration은 유한한 숫자 `(0, 10]`이다. `texture`는 null 또는 존재하는 파일을 가리키는 경로 문자열이다. 편집기 export는 문서 위치 기준 상대 경로를 쓴다. 상대 경로의 `..`, 절대 경로, drive 경로, 임의 URI, 역슬래시 경로는 거부한다. 체크인 manifest의 기존 `res://` project 경로는 허용한다.

`foot_anchor`는 0~1 범위 숫자 `x`, `y`를 가진 객체이며 이미지 캔버스 기준점이다. 예전 문자열 `alpha_bottom_center`는 더 이상 schema v1 입력으로 받지 않는다. 기본 manifest의 정규화 anchor 값은 각 기존 키포즈의 alpha 바운드 중앙/하단 픽셀에 맞춰 기록했다.

## 승인 및 gameplay 연결

후보 이미지가 `approved`라고 표시되어도 아래의 바이트 allowlist를 통과해야 gameplay에 등록된다.

| Clip | 승인 contact 파일 | 고정 contact 시간 |
| --- | --- | ---: |
| `attack1` | `elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png` | 0.105 s |
| `attack2` | `elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png` | 0.120 s |
| `attack3` | `elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png` | 0.140 s |

비교는 이미지 변환 결과가 아닌 기존 승인 PNG의 파일 바이트와 수행한다. 승인 contact는 해당 파일과 phase, clip, 공격 hitbox 활성 시간까지 일치해야 한다. 다른 승인 그림이나 승인 시간은 bank 전체 로드를 거부한다. 한 manifest를 검증하는 동안 모든 clip/frame/path/type 검증이 끝나기 전에는 등록을 시작하지 않는다. 승인된 키포즈 등록 후 좌우 방향은 PoseBlender의 `flip_h` 한 번으로만 바뀌며 좌우 양쪽에서 alpha 발 anchor가 공통 anchor와 일치해야 한다.

Idle은 기존 승인 v8 정지 원화만 허용한다. attack startup/inbetween/recovery와 새 후보는 계속 `temporary`, `unapproved`, 또는 편집기 산출물의 `review`로 둔다. 현재 v6 후보 참조는 실제 파일 `elven_fighter_attack2_contact_v6_candidate_1254x1254.png`를 가리키며 `unapproved`다. 이 파일을 allowlist에 넣거나 사람의 시각 승인으로 간주하지 않는다.

## 독립 검증 및 왕복 테스트

프로젝트 smoke:

```powershell
godot --headless --path . --script res://tests/player_animation_bank_smoke.gd
```

실제 GUI 편집기 EXE가 임시 폴더에 export한 JSON과 texture를 Godot에 전달하는 왕복 smoke:

```powershell
.\tests\editor_animation_bank_roundtrip_smoke.ps1
```

두 번째 명령은 편집기 EXE의 `--animation-gui-acceptance`로 실제 `animation.json`을 생성하고, 그 파일 경로를 headless Godot에 전달한다. Godot bank가 id, 필수 필드, normalized anchor 및 manifest 기준 상대 texture를 파싱한 다음 acceptance용 임시 이미지를 승인으로 위조한 부분은 byte allowlist에서 거부하는지 검사한다. 작업 폴더 산출물은 temp 아래에 둔다.

독립 smoke는 승인 contact 세 장의 원본 바이트 allowlist, 공격 active window 시간, 우/좌 facing 및 공통 발 anchor, 미승인 v5/v6 contact, 승인 위조, `../` 경로 탈출, legacy alias/anchor와 문자열 duration 거부를 검사한다. 이 기계 검증은 원화의 동작 연속성이나 시각 품질을 승인하지 않는다.
