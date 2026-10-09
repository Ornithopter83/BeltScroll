# 미승인 애니메이션 원화 통합 검수 패킷

`assets/art/review/pending_animation_review_packet.png`는 사람의 시각 검수를 위한 자동 생성 비교판이다. 이 이미지는 검수/승인 기록이 아니며, 생성기 실행이나 스모크 통과도 승인 근거가 아니다. 검수 후에는 [수동 검수 기록 양식](records/REVIEW_TEMPLATE.md)을 작성한다.

## 포함 범위와 현재 판정

- 기존 승인 4장: v8 idle 정지 원화 1장과 기존 승인 공격 접촉 원화 3장(attack1 0.105초, attack2 0.120초, attack3 0.140초). 이 네 장만 기존 승인 상태다.
- 미승인 후보 8장: attack1 startup, attack3 startup, run stride v1/v2/v3/v4, jump rise, Num4(skill1 전방 돌진) contact. 후보 원화와 safe 원화는 승인되지 않았다.
- Num5 후보는 `assets/art/player` 안에 `num5` 또는 `skill2`와 `candidate` 문자열을 포함하는 PNG가 실제로 있을 때만 미승인 항목으로 추가한다. 없어도 패킷은 생성된다.
- run v4는 `elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png`와 `elven_fighter_run_stride_v4_safe_candidate_1254x1254.png`를 비교한다. `reference_v4` 원화가 아니다. 기존 판정은 v1~v4가 같은 방향의 보폭 계열이며, v4도 명확한 반대 보폭이 아니어서 미수용이다.
- run v1~v4의 지지발은 정지 원화만으로 확정하지 않아 미판정으로 둔다. alpha 하단 중앙 표식은 기하학적 추정점이며 실제 접지를 뜻하지 않는다.

## 표시와 해석

모든 1254×1254 원화와 safe 원화는 동일한 전체 캔버스 배율 1254→192로 축소해 나란히 표시한다. alpha 바운드를 잘라 각 이미지의 그림 영역을 별도로 192px에 맞추지 않는다. 따라서 패킷은 게임 내 실제 크기, 카메라, atlas/frame 배치, 런타임 타이밍을 측정한 비교로 주장하지 않는다. 2배 최근접 확대는 이 동일한 192px 원본 캔버스 표시의 세부 확인용이며 별도 실측이 아니다.

각 카드에는 원본과 safe(있는 경우), 동일 캔버스 배율의 192px 표시와 좌우 미러, 확대 보기를 둔다. safe가 없으면 패킷에 그 사실을 표시하고 원본을 반복한다. 미러는 비교용 수평 반전이지 별도 승인 포즈가 아니다.

- 원본과 safe 사이에 의도치 않은 색/알파/실루엣 손실 또는 잘림이 있는지 확인한다.
- startup에서 contact, run stride 반복, jump rise, Num4 동작으로 이어질 때 프레임 전환, 캐릭터 identity, 비율 및 잘림이 유지되는지 게임 맥락에서 검토한다. 단일 정지 이미지로 연속성을 승인하지 않는다.
- 좌우 미러 시 칼·팔·머리 장식의 방향과 지지발 논리가 자연스러운지 확인한다. run 지지발은 사람이 시퀀스 및 게임 맥락에서 별도로 판정해 기록한다.
- run의 기존 동일 보폭 판정과 v4 미수용 판정을 카드에 보존했다. 이는 새 승인이나 지지발 판정이 아니다.

## 안전 및 재생성

승인 프레임 레지스트리는 `data/art/reviewed_frame_allowlist.json`이며 본 작업은 여기에 항목을 추가하지 않는다. `data/art/animation_manifest.json`과 승인 레지스트리는 변경하지 않는다. 신규 승인 수는 0건이다. 패킷은 게임 애니메이션 bank에 등록되거나 승인 파일을 덮어쓰지 않는다.

프로젝트 루트에서 Godot 4로 생성한다.

```powershell
godot --headless --path . --script res://tools/build_pending_animation_review_packet.gd
```

기본 출력은 `assets/art/review/pending_animation_review_packet.png`다. 선택 인수로 출력 PNG 경로를 지정할 수 있다. 후보 수에 따라 페이지 높이를 자동 계산해 마지막 카드를 포함한다. 비주얼 검수는 별도로 수행하고, 수동 기록은 `docs/review/records/REVIEW_TEMPLATE.md`에 남긴다.

패킷 wiring 확인은 아래 스모크로 할 수 있다. 이 결과는 파일 존재/열기, 필수 입력, 선택 Num5 파일 존재 검사와 신규 레지스트리 승인 0건만 확인하며 그림의 품질이나 사람의 판정을 검증하지 않는다.

```powershell
godot --headless --path . --script res://tests/pending_animation_review_packet_smoke.gd
```
