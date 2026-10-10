# M6K Num5 회전 백피스트 가독성 게이트

## 구현 결과

`Skill2SpinVisual`은 기존 Num5 startup 0.22초, active 0.18초, recovery 0.55초 phase 시계를 그대로 사용한다. 전투 컨트롤러와 피해·쿨다운 값을 변경하지 않았다.

- 준비에서는 PlayerArt에 facing 반대 방향의 몸통 회전을 최대 0.48 rad 추가해 어깨가 먼저 감기는 동작을 만든다. 어깨·골반 축과 뒤로 물러난 팔 위치도 함께 보인다.
- active에서는 PlayerArt의 실루엣 회전을 추가로 밀어 주고, 손을 몸 뒤에서 앞쪽으로 이동시킨다. 반경 104px의 분홍·흰색 수평 원호, 어깨에서 팔꿈치와 주먹까지 이어지는 팔, 접선 방향 주먹 표시와 회전 화살표가 원형 판정 범위를 설명한다.
- 발 아래 고정 축과 바닥 원호는 제자리 회전을 표시한다. 화면상 캐릭터가 기울어도 pivot 기준은 플레이어 위치에 남는다.
- recovery에서는 반대 방향의 몸통 토크를 감속하고, 원호와 바닥 자취의 반경·길이·불투명도를 줄여 준비 자세로 돌아간다.
- 취소, 피격, KO 또는 Num5 phase 종료 때 효과를 숨기고 PlayerArt에 추가했던 회전을 되돌린다. 접촉 섬광은 실제 `Skill2Hitbox`가 monitoring 중일 때만 시작한다.

## Window 시각 검수

`tests/m6k_skill2_spin_readability_smoke.gd`는 실제 PlayerArt 텍스처를 사용하는 1920×1080 Window 검수 화면을 만든다. Num4 직선 cue와 Num5 준비·휘두름·회복을 2×2로 동시에 보여 주며, 캐릭터 실루엣, 팔과 원호의 관계, 고정 발 기준선을 함께 비교한다. Window 프레임을 OS 임시 디렉터리에 잠시 저장해 시각 확인했고, 검수 이미지나 기타 산출물은 프로젝트에 추가하지 않았다.

시각 검수에서 Num4는 수평 직선, Num5는 몸통 회전과 뒤에서 앞으로 도는 팔·주먹 원호로 구분된다. active에서 캐릭터 아트가 회전하며 바닥 pivot은 고정되고, recovery에서 아트와 자취가 시작 자세 쪽으로 감속한다.

## 계약 및 중단 정리 확인

M6K smoke는 다음 기존 계약을 확인한다.

| 항목 | 유지 값 |
|---|---:|
| Skill2 startup | 0.22초 |
| Skill2 active | 0.18초 |
| Skill2 recovery | 0.55초 |
| 원형 Skill2Hitbox | 반경 64px |
| Skill2 추가 피해 | 2 |
| Skill2 쿨다운 | 1.8초 |

취소·피격·KO 시 효과 정리, active 중 판정 활성 및 접촉 섬광 조건을 확인했고 smoke가 통과했다.

## 재검증 상태와 잔여 승인

2026-10-10 HIGH 재검증에서 `tests/m6k_skill2_spin_readability_smoke.gd`를 실제 Window renderer로 실행했고 계약, 역방향 startup, active 원호, 지지발 pivot, recovery 감속, 취소·피격·KO 정리를 모두 PASS했습니다. 1920×1080 Window 프레임은 OS 임시 디렉터리에 저장해 Num4 직선 cue 및 PlayerArt와 함께 관계를 직접 확인했습니다. 같은 수정에서 Player 장면을 막던 Skill1 VFX 파서 오류도 바로잡혔고, 실제 gameplay Window 캡처 16장도 갱신했습니다.

검수 화면은 실제 PlayerArt 텍스처와 Skill2 효과를 독립 Actor에서 합성해 비교합니다. 실제 gameplay 캡처는 본편 Player를 사용하지만 대표 상태 프레임 기반입니다. Num4 대비 최종 가독성, 움직임 연속성, 기준 영상 타이밍 비교 및 사람의 시각 승인은 여전히 대기 중이며 자동 검수는 원화 승인이 아닙니다.
