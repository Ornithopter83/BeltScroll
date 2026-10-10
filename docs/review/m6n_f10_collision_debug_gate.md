# M6N F10 판정 영역 디버그 게이트

## 구현

`CombatCollisionOverlay` 전역 오토로드가 F10 입력을 받아 표시를 전환합니다. 기본 상태는 OFF이며 씬 재시작/교체 때도 OFF로 초기화합니다. 별도의 `CanvasLayer`에 그려 본편과 Godot F6로 실행한 연습 씬 양쪽에서 쓸 수 있습니다.

표시 대상은 실제 `CollisionShape2D` 노드입니다.

- Player 몸체, 기본 1~3타, Num4, Num5
- ForestRaider 몸체, 공격, 피격 영역
- RuinsWardenBoss 몸체, 공격, 피격 영역

사각형·원·캡슐 윤곽은 각 `Shape2D` 자원과 크기에서 읽습니다. 라벨에는 역할, 실제 `Area2D.monitoring` 상태, 충돌 레이어와 마스크를 표시합니다. 공격 영역은 활성일 때 초록색, 비활성일 때 빨간색이며 몸체·피격 영역은 별도 색상입니다. 변환은 shape 노드의 캔버스 변환에서 매 프레임 읽으므로 카메라 이동과 줌, 방향 전환, 보스 공격 위치/형태 변화가 반영됩니다.

오버레이는 표시 전용입니다. 충돌 shape, 레이어, 마스크, monitoring, 피해, 일반 HUD를 쓰지 않습니다.

## 확인 절차

1. 본편을 실행해 시작 상태에서 판정 윤곽이 없는지 확인합니다.
2. F10을 눌러 켠 다음 Player와 생성된 Raider의 몸체·영역 및 모양 종류, 활성 상태와 L/M 값을 확인합니다. 공격·Num4·Num5를 실행해 monitoring 상태가 실제 공격 프레임에만 켜지는지 봅니다.
3. F10을 여러 번 눌러 매번 반전되는지 확인합니다. 이동·좌우 방향 전환·카메라 경계 이동 중 윤곽이 실제 캐릭터와 함께 움직이는지 확인합니다.
4. 보스 구간에서 F10을 켜고 slash와 slam 공격 중 보스 공격 영역의 실제 위치 및 크기 변화를 확인합니다.
5. Raider와 보스를 KO시키고 표시가 남아 충돌 레이어 0과 monitoring 비활성 상태를 반영하는지 확인합니다. R로 재시작하면 표시가 OFF인지 확인합니다.
6. `scenes/review/m6i_combat_test_arena.tscn`을 Godot 편집기에서 F6로 실행하고 1~3을 반복합니다. 씬별 Player/Raider 트리에서도 전역 오토로드가 표시되어야 합니다.

## 자동 스모크

`tests/m6n_f10_collision_overlay_smoke.gd`는 기본 OFF, Player/Raider/보스 생성과 실제 shape 개수, 비활성/활성 monitoring과 레이어, 보스 공격 영역 transform, 카메라 줌 투영, Raider/보스 KO, F10 반복 전환, 씬 교체 후 OFF 초기화를 확인합니다.

실행 예: `godot --headless --path . --script res://tests/m6n_f10_collision_overlay_smoke.gd`
