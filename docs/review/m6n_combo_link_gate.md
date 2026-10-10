# M6N Combo Link Gate

## 변경 내용

1·2타의 기존 startup, active, recovery 경계를 그대로 둡니다. 해당 타격의 recovery가 끝나고 다음 J가 버퍼되지 않았으면 `combo_hold`로 진입해 마지막 contact 그림과 타격 자세를 유지합니다. 링크 허용시간은 recovery 종료 뒤 0.45초입니다. 이 동안 모든 basic hitbox monitoring은 꺼지며 `_update_attack`은 피해 확인 함수를 호출하지 않습니다.

링크 중 J는 같은 입력 프레임에 다음 타격 startup을 시작합니다. recovery 전에 들어온 J는 기존 0.60초 입력 버퍼로 유지되어 recovery 경계에서 다음 startup을 바로 시작합니다. 3타는 기존 recovery 종료 후 정상 `idle`로 돌아갑니다. 가드, 피격, KO, 스킬 시작 및 링크 만료는 타격 단계·버퍼·링크 타이머를 초기화하고 모든 basic hitbox를 끕니다.

시각 계층은 `combo_hold`를 해당 타격의 contact 상태로 해석합니다. 등록된 contact 애니메이션은 마지막 검토 프레임에 고정하고, 임시 포즈 변환도 contact 자세에 고정합니다. 다음 타격은 held pose에서 startup으로 직접 넘어갑니다.

## 타이밍 불변 조건

| 타격 | Startup | Active 피해 구간 | Recovery |
|---|---:|---:|---:|
| 1 | 0.075초 | 0.105초 | 0.20초 |
| 2 | 0.085초 | 0.12초 | 0.22초 |
| 3 | 0.10초 | 0.14초 | 0.28초 |

콤보 링크 대기는 피해 시간이 아니며, hitbox를 끈 채 별도 phase로 추적합니다. 버퍼 전환과 hold 입력 전환은 `idle`로 상태를 초기화하지 않고 다음 타격 startup으로 직접 전환합니다.

## Smoke 확인

`godot.exe --headless --path . --script res://tests/m6n_combo_link_window_smoke.gd` 실행에서 전용 smoke의 25개 체크가 통과하고 종료 코드 0을 반환했습니다. startup/active/recovery 경계, 무입력 hold 및 hitbox 비활성, 즉시 연결, recovery 중 선입력, 3타 후 idle, 만료와 가드·스킬·피격·KO 정리를 확인했습니다.

실행 중 프로젝트 외부 의존 스크립트 `scripts/player/player_walk_motion.gd:52`에서 별도 타입 추론 Parse Error가 출력됐으나 smoke 체크는 통과했습니다. 해당 파일은 이 작업의 허용 쓰기 경로에 포함되지 않아 수정하지 않았습니다. Godot 사용자 로그 및 루트 인증서 저장소 오류도 출력됐으며 smoke 결과에는 영향을 주지 않았습니다.
