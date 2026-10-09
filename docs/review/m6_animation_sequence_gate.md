# M6 애니메이션 연속 프레임 추출·승인 게이트

## 목적과 경계

`tools/build_player_motion_frames.gd`는 투명 RGBA8 PNG 스프라이트 시트 또는 번호가 붙은 PNG 원화 시퀀스를 읽어 같은 캔버스 크기와 지지발 기준점으로 정규화한 후보 프레임을 별도 출력 폴더에 쓴다. 프레임 PNG와 함께 `motion_candidate.json`을 만들며 상태는 항상 `unapproved`다. 이 파일은 Animation Workspace나 `data/art/animation_manifest.json`의 schema v1 manifest가 아니다.

녹화·게임 화면 캡처와 원화를 픽셀 분석만으로 구별할 수는 없다. 실행자는 입력이 원본 원화임을 확인하고 아래 `--source-kind=original_art` 확인 인자를 넣어야 한다. 이 표시는 작업자 확인 기록이지 원화 출처의 자동 증명이 아니다. 화면 녹화, 캡처 이미지, 리뷰 합성물은 원화 입력으로 사용하지 않는다. 산출물도 시각 검토와 출처 확인을 대체하지 않는다.

도구는 입력 파일을 변경하지 않고 기존 파일이 들어 있는 출력 폴더를 덮어쓰지 않는다. manifest와 reviewed-frame allowlist에 접근하거나 이를 생성·수정하지 않는다. 성공 산출물의 metadata에는 `approval_state: unapproved`, 사람 검토 필요, 두 등록 파일이 수정되지 않았다는 표시가 포함된다.

## 입력과 실행

모든 프레임 PNG는 PNG signature로 확인하고 Godot 디코더의 RGBA8 형식을 요구한다. 투명 픽셀은 alpha bounds 계산에서 제외한다. 전부 투명한 프레임, 잘못된 PNG, 균등하게 나눌 수 없는 시트, 누락/중복 번호, 불연속 번호, 잘못된 duration, 정규화 캔버스 밖으로 밀려 잘리는 지지발 정렬은 실패 처리한다.

시트는 좌상단에서 시작하는 행 우선(row-major) 순서다. 입력 크기는 열·행 수로 나누어 떨어져야 하며 모든 셀은 같은 크기다.

```powershell
godot --headless --path . --script res://tools/build_player_motion_frames.gd -- --sheet <원화시트.png> <새_후보폴더> <열수> <행수> <프레임초> <지지발X_0to1> <지지발Y_0to1> --source-kind=original_art
```

순서화 PNG 시퀀스는 한 폴더 안에 두고 파일명 끝에 연속된 숫자를 붙인다. 예를 들어 `run_0001.png`, `run_0002.png`, `run_0003.png` 순으로 처리한다. 숫자 구간이 겹치는 접미사는 허용하지 않는다.

```powershell
godot --headless --path . --script res://tools/build_player_motion_frames.gd -- --sequence <입력폴더> <새_후보폴더> <프레임초> <지지발X_0to1> <지지발Y_0to1> --source-kind=original_art
```

`duration`은 전체 프레임에 공통 적용되며 0.001~10초 범위다. 지지발 좌표는 원본 각 셀/이미지의 전체 캔버스 기준 정규화 값이다. 지정 지점 주변 2px 안에서 실제 alpha 픽셀이 발견되어야 한다. 프레임의 원본 크기는 각각 메타데이터에 남고, 가장 큰 입력의 크기를 출력 공통 캔버스로 사용한다. 각 입력 지지발 픽셀을 공통 정규화 지지발 좌표에 정렬하며 alpha bounds가 캔버스 밖으로 나가면 작업을 중단한다. 각 프레임 metadata에는 원본 크기와 alpha bounds, 출력 alpha bounds, 이동량, 프레임 번호, source label, duration, 지지발 anchor를 기록한다.

출력 예시는 다음과 같다.

```text
<후보폴더>/
  frame_0000.png
  frame_0001.png
  motion_candidate.json
```

이 도구는 이름순 숫자 연속성과 기술적 이미지 계약만 검사한다. 포즈가 자연스럽게 이어지는지, 지지발 지정이 실제 그림의 지지발인지, 색/선화/실루엣이 원화 기준에 맞는지는 판정하지 않는다.

## 사람 승인 및 기존 런타임 연결

1. 작업자는 `motion_candidate.json`의 `source_kind_attestation` 및 입력 원본 위치를 대조해 후보가 녹화 화면이 아닌 원화에서 만들어졌는지 확인한다. 애니메이터/아트 리뷰어는 순서, 실루엣 변화, 지지발 미끄러짐, 잘림, alpha 가장자리, duration을 실제 크기와 재생 상태에서 확인한다. 승인 전에는 후보를 계속 격리한다.
2. 승인자는 클립 이름, 프레임별 phase/label, duration, normalized `foot_anchor`, 후보 SHA-256을 사람 검토 기록(`docs/review/records/`)에 남긴다. 검토 기록에는 원본/후보 식별자와 검토자 및 날짜, 시각적 결정 근거, 수정 요청을 포함한다. 자동 smoke 통과는 사람 승인이 아니다.
3. 담당자가 검토한 특정 프레임만 의도적으로 체크인 자산 위치로 복사하고, 기존 `data/art/animation_manifest.json` schema v1의 clip `frames` 항목으로 수동 등록한다. 한 프레임의 texture 경로, phase, duration, normalized `foot_anchor` 및 `approval_state`를 manifest에 기록한다. 프레임 순서는 배열 순서로 보존한다. 추출 metadata를 manifest로 복사하거나 후보 전체를 자동 승격하지 않는다.
4. 승인 PNG 바이트 SHA-256, manifest 바이트 SHA-256, duration, anchor, clip/phase/texture 경로와 수동 검토 기록을 `data/art/reviewed_frame_allowlist.json`에 별도로 검토·기록한다. registry의 값은 manifest 및 사람이 본 파일과 일치해야 한다. 승인된 contact는 기존 고정 파일/시간 제약도 계속 따른다. 이 도구는 해당 두 등록을 수행하지 않는다.
5. `PlayerAnimationBank.load_and_register(blender, manifest_path, registry_path)`가 manifest와 고정 reviewed-frame allowlist를 검증한 후에만 승인 프레임을 런타임에 등록한다. 이 경로는 전체 manifest 검사 전 부분 등록을 시작하지 않으며 새로운 승인 프레임을 allowlist 해시/기록과 대조한다. `review`, `temporary`, `unapproved` 후보는 gameplay 승격이 아니다.

`PlayerPoseBlender.register_pose_frame(action, phase, texture, duration, status, label, foot_anchor)`는 상태 문자열이 `approved`로 시작할 때만 등록한다. 그러므로 이 런타임 등록 API를 후보 검토용 우회 경로로 쓰지 않는다. 사람 승인 전에는 후보 폴더를 격리해 별도 리뷰 도구에서 확인하고 gameplay 장면에는 배선하지 않는다. 승인 후 지속적인 gameplay 사용은 AnimationBank manifest와 reviewed-frame allowlist 게이트를 거친다.

## Smoke 확인

```powershell
godot --headless --path . --script res://tests/player_motion_frames_smoke.gd
```

스모크는 합성 RGBA8 시트와 연속 번호 PNG를 만들어 row-major 추출, 크기 정규화, alpha bounds, anchor/duration metadata, 파일 입력 불변성 및 unapproved 상태를 확인하도록 작성됐다. 시트 나눗셈 오류, 사람 출처 확인 누락, 숫자 누락, duration 오류, alpha 없는 anchor, 기존 출력 덮어쓰기 거부도 확인한다. 합성 이미지를 사용하므로 실제 애니메이션의 시각적 연속성, 캡처/원화 출처, 사람 승인은 검증하지 않는다.
