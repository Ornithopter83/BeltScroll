# M6N 본편 Player 보행 표시 게이트

## 구현과 실행 범위

`Player/WalkMotion`은 기존 `VisualAnimator.get_animation_state()`가 `walk`를 반환할 때만 동작하는 별도 표시 계층이다. PlayerArt의 변환 반복 대신 독립 PNG 원화를 실제 프레임으로 표시한다. 보행이 끝나거나 공격 상태가 되면 오버레이를 숨기고 PlayerArt 표시를 돌려준다. 방향 전환은 VisualRoot의 기존 좌우 반전을 따른다.

표시는 `OS.is_debug_build()`에서만 생성된다. 접지 후보 `elven_fighter_walk_opposite_stride_v1_candidate_1254x1254.png`와 passing 후보 `elven_fighter_walk_passing_v1_candidate_1254x1254.png`를 각각 읽는다. 두 프레임은 별도 원화이며 280px/s 기준 0.24초와 0.18초로 재생하고, 이동 속도에 반비례해 cadence를 바꾼다. 수동으로 정한 왼발 지지 anchor를 공유해 프레임 전환 중 위치가 튀지 않게 한다.

오른발 접지 후보 `elven_fighter_walk_right_contact_v1_candidate_1254x1254.png`도 존재해 실제 Texture2D 리소스로 읽히는 경우에만 DEBUG 프레임으로 포함한다. 이는 미승인 후보이므로 DEBUG 외에는 사용하지 않는다. 오른발 접지 다음의 오른발 passing 원화는 없다. 화면 표시와 조회 API는 **RIGHT PASSING: MISSING · CYCLE INCOMPLETE**를 유지한다. 접지→passing→반대 접지의 세 프레임만으로 완전한 양발 사이클을 승인하거나 PASS 처리하지 않는다. 후보 프레임이 없을 때는 그 위상을 합성하지 않고 누락 상태를 표시한다.

후보는 DEBUG 연습 실행용 임시 표시다. Release에서 프레임과 라벨을 만들지 않으며 Player animation manifest, reviewed allowlist, 승인 기록은 수정하거나 승격하지 않는다. 후보 PNG 자체도 변경하지 않았다.

## 자동 확인

`tests/m6n_walk_gameplay_window_smoke.gd`는 본편 Player 씬에서 기존 walk 상태 연동, 독립 접지와 passing 재생, 속도에 따른 표시 주기, 접지 anchor 고정, 좌우 반전, 오른발 위상 누락 표시, 걷기→공격→걷기 인계를 확인한다. 실행 예:

```powershell
& 'C:\Project\Godot\godot.exe' --headless --path . --script res://tests/m6n_walk_gameplay_window_smoke.gd
```

자동 검사는 텍스처와 상태 전환, anchor 계산을 확인한다. 실제 캐릭터 실루엣의 접지 해석이나 사람의 시각 승인을 대신하지 않는다. 오른발 passing 원화가 없어 완전한 양발 주기 판정은 보류다.
