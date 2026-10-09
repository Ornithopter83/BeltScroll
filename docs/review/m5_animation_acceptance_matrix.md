# M5 플레이어 애니메이션 실제 화면 수용 매트릭스

이 문서는 `player_controller.gd`, `player_visual_animator.gd`, `player_animation_bank.gd`, `player_pose_blender.gd`와 `data/art/animation_manifest.json` 및 최신 검수 게이트의 현재 상태를 기록합니다. 화면 근거는 [플레이어 상태 Window 비교판](../../assets/art/review/player_animation_state_matrix.png)이며 생성기는 `tools/capture_player_animation_state_matrix.gd`입니다. 제품 필수 동작은 10종이고, 편집기 JSON은 `jump`를 `jump_rise`/`jump_fall`로 분리해 11개 클립을 사용합니다. Num5 회전 입증은 `skill2`의 별도 수용 조건입니다.

## 상태별 화면 검수

| 상태 | 화면 원화/표현의 실제 출처 | 시간 / 좌향 / 발 anchor | 중단·전환 / hitbox 동기 | 판정 경계 |
|---|---|---|---|---|
| idle | 승인된 v8 clean 정지 원화 1장. Animator는 미세 호흡 transform을 얹음. | manifest idle duration 0.800 s는 정지 항목 메타데이터이며 반복 프레임 재생이 아님. 좌우는 `VisualRoot.scale.x`; alpha 하단 중앙 anchor 유지 (`0.500000, 0.928230`). | 이동·점프·피격·공격 입력 시 상태 전환. hitbox 없음. | 실제 정지 원화. 완성 idle 프레임 시퀀스는 아님. |
| run / walk | 현재 본편은 v8 정지 원화에 stride 변형을 적용. v1~v5 정지 접촉 후보와 safe 자료는 검토됐으나 본편 run 프레임 승인이 아니다. | 0.120 s 임시 상태 주기, 속도 280 px/s 기준. 좌향은 root flip, 발 anchor 보정. | 입력 속도가 10 초과하면 walk. 피격·점프·공격 상태가 우선. hitbox 없음. | v1~v5가 모두 같은 보폭으로 판정되어 반대 보폭/완성 사이클 수용 실패. v3·v4·v5 원화가 확보된 사실은 수용과 다르다. |
| turn | 본편은 기존 idle/walk 원화의 절차적 회전 표시. 전용 rear-mid 원본과 별도 safe 후보가 확보됐으나 검수용 후보만이며 본편 미연결. | 방향 변경 시 0.13 s: 반대 방향 anticipation → 압축 중심 → `VisualRoot` 부호를 한 번 변경 → settle. 이동 입력·속도는 지연하거나 변경하지 않으며 alpha 발 보정을 유지. 실제 Window 표본은 발 anchor `(960, 792)`, 빠른 역입력·피격 취소·좌우 flip을 기록. | KO·hitstun·스킬·공격·방어·점프·착지가 우선하며 turn clock을 지우고 facing을 즉시 적용. 빠른 역입력은 새 방향으로 절차를 재시작. | rear-mid 원화에서 후방 3/4와 얼굴·귀·포니테일 identity는 읽히나 보폭이 달리기로 보여 키포즈 미수용/사람 승인 대기. idle 대비 실루엣은 폭 약 14.4%, 높이 약 13.5% 크다. 지지발 접촉선·좌우 authored frame은 미검증. 원본 SHA-256 `43ae0c54ee26ece7121ec60a265d507877b2cfea8408026f8bccd0ff3779da72`, 1,032,791 bytes. |
| jump rise / fall | 본편 재생은 v8 기반 절차적 포즈와 물리 상승/하강, 지면 shadow를 사용. rise/fall v1 원화 및 safe 후보와 비교 자료가 별도로 확보됨. | 편집기 JSON은 각각 `jump_rise`, `jump_fall`; 제품 동작은 jump 하나. 비행 시간은 물리 속도·중력·점프 입력에 따르며 0.160 s 표기는 절차 상태 단계 메타데이터. 좌향 root flip, 지면 shadow 분리, 착지 변형 0.140 s. | 피격/KO 우선. 점프 중 공격·스킬 시작은 거부. 공격 hitbox 없음. | rise/fall 원화 후보는 미승인·미등록. 후보 존재나 Window 캡처는 사람 승인 아님. |
| hit | 본편은 v8 정지 원화의 knockback 방향 회전/압축, hit flash를 사용. hit reaction v1 원화와 safe 후보 및 비교 자료가 별도로 확보됨. | 기본 hit 상태 0.120 s; 게임 경직은 타격 데이터가 정하고 별도 남은 시간으로 시각 상태를 유지. 좌향은 root flip; alpha foot 보정. | 피격은 현재 공격 phase와 공격 hitbox를 취소. KO이면 hit 대신 KO. | hit 원화 후보는 미승인·미등록. 절차 변형 및 smoke는 원화 승인 근거가 아니다. |
| attack1 | startup/recovery는 v8 기반 임시 transform. active contact는 승인된 `elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png`. | startup 0.075 s, contact/hitbox 0.105 s, recovery 0.200 s. 좌향 root flip 1회; contact anchor `(0.500000, 0.927432)`. | 공격 controller phase remaining이 Animator 시계와 동기. active 외 hitbox 비활성. 피격/KO 시 취소. | contact 1장만 승인. clean, edge_v2, final 후보는 미승인. 준비/회수/연결 원화 미구현. |
| attack2 | startup/recovery는 임시 transform. active contact는 승인된 `elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png`; 초반 contact에는 transform 기반 inbetween. | startup 0.085 s, contact/hitbox 0.120 s, recovery 0.220 s. progress 42%까지 절차적 연결. root flip 1회; contact anchor `(0.499601, 0.928230)`. | controller active 타이머와 접촉 이미지/hitbox가 일치. active 외 hitbox 비활성. 피격/KO 시 취소. | contact 1장 승인. v5/v6 접촉 및 inbetween safe 후보는 미승인·미등록. 준비/회수/연결 원화 미구현. |
| attack3 | startup/recovery는 임시 transform. active contact는 승인된 `elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png`. | startup 0.100 s, contact/hitbox 0.140 s, recovery 0.280 s. 좌향 root flip 1회; contact anchor `(0.500000, 0.928230)`. | controller active 타이머와 contact/hitbox 동기. active 외 hitbox 비활성. 피격/KO 시 취소. | contact 1장만 승인. reference v1, v2 clean 등 대체 후보는 미승인. 기타 phase 원화 미구현. |
| Num4 / skill 1 | 전방 돌진 스킬은 실제 gameplay와 Animator `skill1_startup/contact/recovery`로 연결됨. Sprite 포즈는 v8 원화의 절차적 transform이며 승인된 전용 원화 프레임은 없음. | startup 0.160 s, active 0.120 s, recovery 0.420 s, cooldown 1.350 s. facing 방향으로 startup 120 px lunge + active 이동. 발 anchor는 기본 원화 기준. | active 동안 Skill1Hitbox(108×58) 활성, 전방 52 px. blocking 입력은 스킬을 취소. 스킬 중 일반 공격·다른 스킬 거부; 피격/KO 시 hitbox가 꺼짐/스킬 종료. | gameplay와 상태 clock/절차적 포즈 구현. skill1 전용 원화 후보는 미승인. |
| Num5 / skill 2 | 주변 범위 스킬은 실제 gameplay와 Animator `skill2_startup/contact/recovery`로 연결됨. Sprite 포즈는 v8 원화의 절차적 transform이며 승인된 전용 원화 프레임은 없음. | startup 0.220 s, active 0.180 s, recovery 0.550 s, cooldown 1.800 s. 별도 lunge 없음. 발 anchor 기본 원화 기준. | active 동안 Skill2Hitbox(radius 64) 활성, 중심 배치. blocking 입력 취소, 스킬 중 공격 불가, 피격/KO에서 중단. | gameplay와 상태 clock/절차적 포즈 구현. Num5 회전 입증은 skill2의 별도 수용 조건이며 v2 원화 후보는 확보됐지만 미승인. |
| KO | v8 정지 원화에 회색 tint, 기울기 0.12 rad, scale `(1.035, 0.91)` 변형. 1개 상태 프레임. | 상태 clock 1.000 s이나 포즈는 정지 유지. 좌향 root flip 및 alpha 발 anchor 보정. | 최우선 상태. 공격 phase와 skill을 종료하고 모든 공격 hitbox를 비활성화. | KO 전용 원화 프레임/눕기 모션은 미구현. |

## 화면 및 구현 확인 기준

- Window 비교판은 실제 Window Viewport에서 재생성한 PNG이며 캡처 상태와 라벨에 `실제 원화`, `절차적 변형`, `미구현`, `미승인 후보`를 별도로 표시합니다.
- 현재 승인 원화 프레임은 v8 idle 1장과 attack1~3 contact 각 1장, 총 4장입니다. 이 중 기존 승인 원화가 아닌 신규 승인 원화는 0건입니다. Num4~5의 스킬 gameplay·hitbox clock·procedural pose는 구현되어 있고 전용 원화는 승인되지 않았습니다. 원화의 부재는 gameplay 기능 부재와 같은 뜻이 아닙니다.
- 공격 접촉 시간은 controller hitbox active 값과 bank 승인값이 일치해야 합니다. hit-stop 동안 게임 시계와 hitbox, 접촉 프레임이 함께 멈춥니다.
- 왼쪽은 `VisualRoot` 미러링 한 번만 적용합니다. PoseBlender 지역 Sprite에는 추가 flip을 적용하지 않고 alpha 하단 anchor를 맞춥니다. jump 중 anchor는 VisualRoot 로컬 기준이므로 수직 상승하지만, GroundShadow는 지면에 남습니다.
- 기본 idle 원화의 정규화 alpha foot anchor는 `(0.500000, 0.928230)`이며 run/turn/jump/hit/KO의 v8 기반 변형은 이 공통 발점을 유지합니다. 공격 contact 각 anchor는 표에 적은 manifest 좌표를 사용하고 blender가 alpha 발점을 공통 local anchor로 정렬합니다.
- 검수 smoke는 상태 API와 이 캡처 증거의 존재/크기를 확인합니다. 화면이 캡처되거나 smoke가 통과해도 미구현 원화와 미승인 후보를 승인 프레임으로 올리지 않습니다.

## 독립 편집기와 프레임 뱅크

독립 편집기 실행 파일은 `dist/BeltScrollEditor.exe`이며 실행 인수, 외부 프로젝트 경로, GUI 저장은 [편집기 EXE 인수 검수 게이트](editor_acceptance_gate.md)에서 확인합니다. 프레임 등록은 `data/art/animation_manifest.json` schema v1로 유지하고, 승인 접촉 원화/시간/경로/anchor 규칙은 [프레임 레지스트리 승인 게이트](animation_frame_registry_gate.md)를 따릅니다. 검수 후보 PNG는 파일이 존재하더라도 승인 상태가 아니면 프레임 뱅크가 로드하지 않습니다.

재생성 및 증거 존재 확인:

```powershell
godot --path . --script res://tools/capture_player_animation_state_matrix.gd
godot --headless --path . --script res://tests/player_animation_state_matrix_smoke.gd
```
