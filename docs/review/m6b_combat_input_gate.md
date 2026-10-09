# M6B 전투 입력 Window 캡처 및 검수 게이트

## 실행 결과

`tools/capture_m6b_combat_input_window.gd`를 Godot 4.7.2 Compatibility 렌더러의 실제 Window로 실행했다. `scenes/game/main.tscn`의 Player, VisualAnimator, HUD, 적과 스테이지를 올린 뒤 동작을 순서대로 재생하고 `RenderingServer.frame_post_draw` 뒤 Window Viewport 픽셀을 읽었다. 1920×1080 Window 프레임 21장을 640×360 셀로 줄여 세 열×일곱 행의 [캡처 보드](../../assets/art/review/m6b_combat_input_window.png)에 저장했다. 한 행의 열 순서는 시작, 접촉, 종료이고 행 순서는 1타, 2타, 3타, Num4, Num5, 피격 경직, final-down이다.

| 동작 | 시작 상태 | 접촉 상태 | 종료 상태 |
|---|---|---|---|
| 기본 1타 | startup | active / Hitbox1 | idle |
| 기본 2타 | startup | active / Hitbox2 | idle |
| 기본 3타 | startup | active / Hitbox3 | idle |
| Num4 돌진 주먹 | skill startup | skill active / Skill1Hitbox | skill idle |
| Num5 회전 백피스트 | skill startup | skill active / radial Skill2Hitbox | skill idle |
| 피격 경직 | hitstun 시작 | hitstun 진행 | hitstun 종료 / idle |
| final-down | KO 시작 | 낙하 진행 | animator 안정 상태 |

## Window에서 계측한 프레임

좌표는 1920×1080 Window 픽셀이다. `주먹 대용점`은 현재 프레임에서 켜진 공격 hitbox의 중심이며, 종료 프레임에서는 idle 때 첫 공격 hitbox의 기준 중심이다. Num5 원형 hitbox는 몸 중심이므로 이 값은 해부학적인 주먹 위치가 아니다. 상체 회전은 캐릭터 원화 Sprite의 실제 회전값, 실루엣 스케일은 VisualRoot × Sprite의 X/Y 배율, 수직량은 발 기준점의 지면 기준 Y 오프셋이다. 지면 기준 오프셋의 중립값은 약 23.4px이므로 표의 값은 중립 대비 움직임을 읽는다.

| 동작 | 프레임 | 상태 | 주먹 대용점 (x,y) px | 회전 ° | 실루엣 배율 (x,y) | 지면 기준 Y px |
|---|---|---|---:|---:|---:|---:|
| 1타 | 시작 | startup | 1029, 936 | 0.8 | .4451, .4495 | 23.5 |
| 1타 | 접촉 | active | 1037, 936 | -4.9 | .4510, .4440 | 23.2 |
| 1타 | 종료 | idle | 1013, 936 | -0.8 | .4474, .4468 | 23.4 |
| 2타 | 시작 | startup | 1046, 936 | 0.3 | .4468, .4470 | 23.4 |
| 2타 | 접촉 | active | 1070, 936 | -4.7 | .4509, .4437 | 23.2 |
| 2타 | 종료 | idle | 1014, 936 | -1.1 | .4475, .4468 | 23.4 |
| 3타 | 시작 | startup | 1070, 936 | 0.3 | .4468, .4470 | 23.4 |
| 3타 | 접촉 | active | 1100, 935 | -13.4 | .4561, .4395 | 22.4 |
| 3타 | 종료 | idle | 1070, 936 | -1.6 | .4478, .4465 | 23.4 |
| Num4 돌진 주먹 | 시작 | startup | 1115, 936 | -0.5 | .4469, .4473 | 23.4 |
| Num4 돌진 주먹 | 접촉 | active | 1237, 935 | 5.4 | .4469, .4522 | 23.6 |
| Num4 돌진 주먹 | 종료 | idle | 1216, 936 | 0.4 | .4467, .4473 | 23.4 |
| Num5 회전 백피스트 | 시작 | startup | 1169, 936 | 0.5 | .4466, .4475 | 23.4 |
| Num5 회전 백피스트 | 접촉 | active | 1169, 936 | -14.2 | .4485, .4467 | 22.7 |
| Num5 회전 백피스트 | 종료 | idle | 1216, 936 | -0.3 | .4472, .4469 | 23.4 |
| 피격 경직 | 시작 | hitstun | 1215, 935 | 3.7 | .4487, .4445 | 23.2 |
| 피격 경직 | 진행 | hitstun | 1212, 936 | 5.8 | .4472, .4465 | 23.3 |
| 피격 경직 | 종료 | idle | 1212, 936 | 0.3 | .4477, .4481 | 23.5 |
| final-down | 시작 | final-down | 1331, 779 | 0.2 | .4446, .4457 | 23.3 |
| final-down | 진행 | final-down | 1331, 779 | 6.0 | .4436, .4450 | 23.2 |
| final-down | 안정 | final-down | 1331, 779 | 79.1 | .4313, .4380 | 4.4 |

캡처 시 전투 scene의 적이 동시에 진행하므로 캐릭터 Window X좌표와 공격 대상도 시퀀스에 따라 달라진다. 플레이어의 지면 고정점은 기본 타격·Num4·피격에서 약 ±1.2px, Num5 접촉에서 -0.7px 범위로 유지됐다. final-down 종료는 지면 기준점이 19.0px 낮아지고 원화 회전이 79.1°가 되어 옆으로 쓰러진 실루엣을 보였다. Num4 접촉에서 Player의 X좌표가 시작보다 약 123px 이동했다. 기본 공격은 3타 contact에서 가장 큰 측정 회전(-13.4°)과 Y 배율 변화(0.4395)를 보였다.

## 시각 인수 판정

- 기본 1·2·3타의 접촉은 각각 등록된 공격 contact 그림을 사용한다. 시작과 idle 복귀는 타이밍과 변환을 쓰며 연속 원화 전체가 갖춰졌다는 뜻은 아니다. 전이의 연속성 및 각 프레임의 손 위치는 추가 시각 검수가 필요하다.
- Num4와 Num5는 전용 승인 프레임 대신 임시 절차 변형을 사용하는 동작이다. Num4 대시의 전진 이동은 계측되지만 그림이 돌진 주먹 동작을 온전히 보여 주는지, Num5가 회전 백피스트로 명확히 읽히는지는 승인되지 않았다. Num5는 radial hitbox 중심만 측정했으며 개별 주먹 위치를 재지 않았다.
- 피격 경직과 final-down도 전용 승인 프레임 연속 애니메이션이 아닌 runtime 절차 변형이다. final-down에서 회전·축소·낮아진 발 기준점은 계측됐으나, 측정만으로 시각 인수를 통과시키지 않는다.
- 따라서 기본 타격은 contact 포즈를 확인했고, Num4·Num5·피격·final-down은 **시각 인수 미완료**로 기록한다. VFX나 절차 변형은 승인 원화를 대신하지 않는다.

## 회귀 스모크

```powershell
godot --path . --script res://tests/m6b_combat_input_window_smoke.gd
```

스모크는 headless가 아닌 실제 Window 캡처 프로세스를 시작한다. 1·2·3타의 startup→active→idle, Num4·Num5의 startup→active→idle, 피격 경직의 시작/해제, KO 신호 뒤 animator final-down 안정 상태, 21개 계측 로그 및 PNG 크기를 검사한다. headless 실행에서는 Window 요구를 설명하고 실패한다.

## 재현

```powershell
godot --path . --script res://tools/capture_m6b_combat_input_window.gd
godot --path . --script res://tests/m6b_combat_input_window_smoke.gd
```

실행 로그에 `user://logs` 쓰기 및 Windows 인증서 저장소 접근 오류가 출력됐지만 Window 캡처는 종료 코드 0으로 끝났고 21프레임 PNG를 생성했다. 이 오류 메시지는 캡처 산출물 실패로 이어지지 않았다.
