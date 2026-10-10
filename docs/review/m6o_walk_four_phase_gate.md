# M6O 4위상 보행 후보 검토 게이트

## Window 미리보기

Godot 에디터에서 `scenes/review/m6o_walk_four_phase_preview.tscn`을 열어 **F6**으로 실제 gameplay Window를 실행한다. WASD로 걷고 J를 눌러 기본 콤보와 걷기 재진입을 본다. 걷는 동안 Player 위의 DEBUG 라벨과 청록/분홍 지지점 마커에서 현재 위상과 좌우 anchor를 읽는다. 이동 속도를 바꾸거나 방향을 바꾸며 cadence, 좌우 지지점, 실루엣(골반 높이 포함)과 인계를 관찰한다.

## 후보 순서

|순서|위상|독립 PNG|지지발|기준 시간|검토 메모|
|---:|---|---|---|---:|---|
|1|왼발 접지|`elven_fighter_walk_opposite_stride_v1_candidate_1254x1254.png`|왼발|0.24초|왼쪽 지지점 추정값|
|2|왼발 passing|`elven_fighter_walk_passing_v1_candidate_1254x1254.png`|왼발 추정|0.18초|1번과 별도 원화, 왼발 지지 anchor 유지|
|3|오른발 접지|`elven_fighter_walk_right_contact_v1_candidate_1254x1254.png`|오른발|0.24초|왼발과 다른 지지 anchor 사용|
|4|오른발 passing|`assets/art/player`의 `walk`·`right`·`passing` 이름을 가진 PNG|오른발 추정|0.18초|선택 리소스. 있으면 4위상 후보에 포함|

현재 `elven_fighter_walk_right_passing_v1_candidate_1254x1254.png`가 확보되어 있다. 따라서 네 PNG를 왼발 접지 → 왼발 passing → 오른발 접지 → 오른발 passing 순으로 각 한 번 재생한다. 오른발 passing은 별도 원화다. Resource가 없는 체크아웃에서는 3장을 재생하고 `RIGHT PASSING MISSING`을 표시한다. 오른발 passing을 합성하거나 왼발 그림을 뒤집어 채우지 않는다. 선택 리소스는 파일명에 `walk`, `right`, `passing`이 포함된 독립 PNG에서 찾는다.

접지점은 PNG에 기록된 관절 데이터가 아닌 리뷰용 수동 추정값이다. 왼발과 오른발에는 서로 다른 anchor를 사용하며, 이는 발 미끄러짐을 교정하거나 실제 접지를 증명하는 데이터가 아니다. 이동 속도에 따라 프레임 시간이 기준 속도 280px/s에 반비례한다. Player의 공격 상태가 되면 후보 표시가 즉시 물러나며, 콤보 종료 후 걷기에서 다시 시작한다.

## 격리와 판정

이 원화들은 미승인 후보로 DEBUG 표시 계층과 격리 preview에서만 사용한다. Release 표시 경로, animation manifest, allowlist에는 등록하지 않는다. Window smoke는 현재 네 단계 순서, 좌우 지지발 전환, 각 발의 별도 anchor 마커, 속도 cadence, 화면 프레임 렌더링과 걷기↔콤보 인계를 검사한다. PNG 실루엣으로 보는 골반 움직임은 정성 관찰이며 정밀 발 추적이나 승인 판정은 별도 사람 검토가 필요하다.

검증 명령:

```powershell
& 'C:\Project\Godot\godot.exe' --path . --script res://tests/m6o_walk_four_phase_window_smoke.gd
```

이 smoke는 headless 대신 Window 렌더러를 요구한다. 현재 판정은 **4위상 격리 후보, 승인 대기**다. 선택 리소스가 빠진 경우에는 **3위상 미완성 후보** 상태를 검사한다.
