# 미승인 애니메이션 원화 통합 검수 패킷

`assets/art/review/pending_animation_review_packet.png`는 사람의 시각 검수를 위한 자동 생성 비교판이다. 이 이미지는 검수/승인 기록이 아니며, 생성기 실행이나 스모크 통과도 승인 근거가 아니다. 검수 후에는 [수동 검수 기록 양식](records/REVIEW_TEMPLATE.md)을 작성한다.

## 포함 범위

- 비교 기준: v8 승인 idle 정지 원화 1장과 기존 승인 공격 접촉 원화 3장(attack1 0.105초, attack2 0.120초, attack3 0.140초).
- 미승인 후보: attack1 startup, attack3 startup, run stride v1/v2/v3, jump rise, Num4(skill1 전방 돌진) contact. 후보는 저장소의 원본 파일이 있는 경우에만 패킷에 실린다.
- v4 기준 이미지는 `elven_fighter_reference_v4_1254x1254.png`가 있을 때에만 선택 비교 항목으로 포함한다. 존재 여부는 승인 상태를 뜻하지 않는다.

각 항목은 원본, safe 파일이 있으면 safe, alpha 바운드 기준으로 잘라 192×192 게임 표시 영역에 맞춘 그림, 그 좌우 미러, 192px 표시를 최근접 방식으로 3배 확대(576×576)한 그림을 나란히 보여준다. safe가 없으면 패킷이 그 사실을 명시하고 원본 이미지를 비교 칸에 반복한다. 미러는 비교용 수평 반전이지 별도 승인 포즈가 아니다.

## 무엇을 확인할지

- 원본과 safe 사이에 의도치 않은 색/알파/실루엣 손실 또는 잘림이 있는지 확인한다.
- 패킷의 빨간 십자 및 수치는 alpha 외곽 바운드의 아래쪽 중앙을 계산한 기하학적 추정치다. 이는 발의 실제 접지점이나 애니메이션 지지발을 자동 판정하지 않는다. 특히 run의 왼발/오른발 지지, jump의 공중 여부, 공격 준비와 접촉 사이의 접지는 사람이 판단하고 기록한다.
- 좌우 미러 시 칼·팔·머리 장식의 방향과 지지발 논리가 자연스러운지 확인한다.
- startup에서 contact, run stride 반복, jump rise, Num4 동작으로 이어질 때 프레임 전환, 캐릭터 identity, 비율 및 잘림이 유지되는지 게임 맥락에서 검토한다. 단일 정지 이미지로 연속성을 승인하지 않는다.
- 게임 표시 이미지는 알파 영역을 192px 상자에 맞춰 축소한 검수 근사다. 게임 내 실제 카메라, atlas/frame 배치, 런타임 타이밍과의 일치를 보증하지 않는다.

## 안전 및 재생성

승인 프레임 레지스트리는 `data/art/reviewed_frame_allowlist.json`이며 본 작업은 여기에 항목을 추가하지 않는다. 현 allowlist가 비어 있는 저장소 상태를 그대로 유지한다. 신규 승인 수는 0건이다. 패킷은 게임 애니메이션 bank에 등록되거나 승인 파일을 덮어쓰지 않는다.

프로젝트 루트에서 Godot 4로 생성한다.

```powershell
godot --headless --path . --script res://tools/build_pending_animation_review_packet.gd
```

기본 출력은 `assets/art/review/pending_animation_review_packet.png`다. 선택 인수로 출력 PNG 경로를 지정할 수 있다. 비주얼 검수는 별도로 수행하고, 수동 기록은 `docs/review/records/REVIEW_TEMPLATE.md`에 남긴다.

패킷 wiring 확인은 아래 스모크로 할 수 있다. 이 결과는 파일 존재/열기, 필수 입력 및 신규 레지스트리 승인 0건만 확인하며 그림의 품질이나 사람의 판정을 검증하지 않는다.

```powershell
godot --headless --path . --script res://tests/pending_animation_review_packet_smoke.gd
```

