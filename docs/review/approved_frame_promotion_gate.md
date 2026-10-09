# 승인 프레임 본편 승격 계약

`data/art/animation_manifest.json`의 GUI `approval_state`는 승인 권한이 아니다. `approved`로 바꾸기만 한 신규 프레임, 외부 편집기 export, 미승인 manifest는 런타임에서 등록되지 않는다. 신규 gameplay 프레임은 체크인 manifest와 `data/art/reviewed_frame_allowlist.json`의 명시적 쌍으로만 승격한다.

## 레지스트리 형식

초기 레지스트리는 다음과 같이 신규 승인 0건이다.

```json
{
  "schema_version": 1,
  "entries": []
}
```

사람이 프레임을 검수한 뒤 한 항목을 추가할 때 `entries` 객체는 모두 다음 정보를 가져야 한다.

```json
{
  "clip": "attack2",
  "phase": "inbetween",
  "texture": "res://assets/art/player/example.png",
  "sha256": "64자리 소문자 PNG 파일 SHA-256",
  "duration": 0.05,
  "foot_anchor": { "x": 0.5, "y": 0.92 },
  "review_record": "res://docs/review/records/attack2-inbetween-2026-10-09.md",
  "manifest_sha256": "최종 animation_manifest.json 파일의 64자리 SHA-256"
}
```

`review_record`는 저장소 안 `docs/review/records/`의 비어 있지 않은 수동 검수 기록을 가리켜야 한다. 기록에는 검수자, 검수 날짜, clip/phase, 프레임의 시각적 판단 및 승격 결정을 적는다. 레지스트리의 PNG 해시는 이미지 디코딩 전 원본 파일 바이트에서 계산한다. `manifest_sha256`는 `approval_state`와 프레임 정보를 포함한 최종 manifest 바이트에 대한 해시다. manifest를 바꾸면 이 해시도 다시 계산한다. 레지스트리 파일 자체는 manifest 해시 계산에 포함되지 않는다.

## 런타임 조건

런타임은 clip/phase 중복, 필수 필드, 유한한 duration, 정규화된 anchor, 소문자 64자리 해시, 프로젝트 내 안전한 `res://` PNG 경로, 검수 기록 경로·존재 여부를 확인한다. 신규 승격은 공격의 `startup`, `inbetween`, `recovery` phase를 대상으로 한다. `contact`는 기존 고정 hitbox 시간과 byte allowlist를 유지하기 위해 레지스트리 승격 대상으로 열지 않는다. 새 `approved` 프레임은 체크인 manifest에서 레지스트리의 texture, 실제 PNG SHA-256, duration, anchor와 모두 일치하고 manifest SHA-256도 일치할 때만 등록한다. 레지스트리에 있으나 manifest에 없는 승인 항목도 거부한다. 경로 탈출, 잘못된 해시, 누락 또는 빈 수동 기록, GUI 상태 변경만으로는 승격할 수 없다.

기존 idle v8 원화와 attack1/2/3 접촉 프레임은 기존 코드의 byte-level allowlist와 고정 hitbox 시간으로 계속 검증한다. PNG allowlist와 타격 시간은 이 계약으로 변경하지 않는다.

## 수동 승격 절차와 검증

1. 사람이 후보 프레임을 검수하고 `docs/review/records/` 아래 기록을 작성한다.
2. 체크인 manifest의 해당 프레임에 clip, phase, texture, duration, normalized `foot_anchor`, `approval_state: "approved"`를 명시한다.
3. 실제 PNG 파일과 최종 manifest의 SHA-256을 계산해 레지스트리의 `sha256`, `manifest_sha256`에 기록하고, 모든 프레임 값과 기록 경로를 채운다.
4. `powershell -ExecutionPolicy Bypass -File .\tools\verify_reviewed_frame_allowlist.ps1`로 독립 검증한다. 런타임 bank도 같은 계약을 다시 확인한다.

자동 테스트와 검증 스크립트는 레지스트리에 승인 항목을 생성하지 않는다. 현재 신규 레지스트리는 비어 있으며 기존 후보는 manifest에서 미승인 상태로 유지된다.
